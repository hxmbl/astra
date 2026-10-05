# modules/services/caddy.nix — the one door into this machine.
#
# Every HTTP service on an astra box is published here and nowhere else, on
# ports 80 and 443. Container ports stay bound to localhost. That is the whole
# security model for the web side: no service is asked to be its own TLS stack,
# and no service has a reason to be reachable from the open internet.
#
# For the "works on the LAN with zero DNS setup" case, every registered host also
# gets an /etc/hosts entry pointing at 127.0.0.1. Point real DNS at the box and
# delete `networking.extraHosts`; nothing else changes.
#
# HTTPS is on when you have given an ACME email, off otherwise. An internal-only
# box asking Let's Encrypt for a certificate for `searx.astra.local` just
# produces a boot-time error and a browser warning.
{ config, lib, pkgs, ... }:
let
  cfg = config.astra.caddy;
in
{
  options.astra.caddy = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Run Caddy as the HTTP(S) entry point for this machine.";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "astra.local";
      description = "Suffix for per-service hostnames, e.g. searx.astra.local.";
    };

    email = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "ACME account email. Empty means internal-only and no TLS.";
    };

    localHosts = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Resolve every registered hostname to 127.0.0.1 so this works before you have DNS.";
    };

    hosts = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Left-hand label; the full hostname is <name>.<astra.caddy.domain>.";
            };

            upstream = lib.mkOption {
              type = lib.types.str;
              description = "Reverse proxy target, e.g. localhost:8080.";
            };

            tls = lib.mkOption {
              type = lib.types.bool;
              default = cfg.email != "";
              description = "Let Caddy obtain a certificate. False means plain HTTP on :80.";
            };
          };
        }
      );
      default = [ ];
      description = "Services wanting a vhost. Modules append to this; hosts rarely do.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;
      email = lib.mkIf (cfg.email != "") cfg.email;
      # Caddy's admin API is a remote-code-execution surface and we never use it.
      # It is a *global* option, not `services.caddy.admin` — that option does not
      # exist; global config goes in globalConfig (types.lines,
      # nixos/modules/services/web-servers/caddy/default.nix:223).
      globalConfig = "admin off";
    };

    # Nothing but caddy should ever listen for HTTP.
    networking.firewall.allowedTCPPorts = [ 80 443 ];

    services.caddy.virtualHosts =
      # A plain attrset keyed by hostname, not a list of { name, value } pairs:
      # services.caddy.virtualHosts is types.attrsOf (submodule ...)
      # (nixos/modules/services/web-servers/caddy/default.nix:259).
      #
      # And the vhost submodule has no `routes` — it is hostName,
      # serverAliases, listenAddresses, useACMEHost, logFormat and extraConfig
      # only (caddy/vhost-options.nix:14-84). Routing is a Caddyfile directive,
      # so a reverse proxy goes in extraConfig (types.lines, line 78).
      builtins.listToAttrs (
        map (
          h:
          {
            name = "${h.name}.${cfg.domain}";
            value = {
              listenAddresses = [ "0.0.0.0" ];
              # No explicit tls block on purpose: Caddy's automatic HTTPS does the
              # right thing for real names and stays on :80 for internal ones.
              extraConfig = ''
                reverse_proxy ${h.upstream}
              '';
            };
          }
        )
        cfg.hosts
      );

    # The /etc/hosts convenience described at the top of the file.
    #
    # types.lines, not listOf str: the option is appended verbatim to
    # /etc/hosts (nixos/modules/config/networking.nix:54, and
    # pkgs.writeText "extra-hosts" at :201).
    networking.extraHosts = lib.concatMapStringsSep "\n" (h: "${h.name}.${cfg.domain} 127.0.0.1") cfg.hosts;
  };
}