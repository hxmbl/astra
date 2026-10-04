# modules/services/rustdesk.nix — remote desktop that is not a screen share.
#
# RustDesk's self-hosted relay lets you get into a machine behind NAT with no
# third party in the middle: hbbs is the ID/rendezvous server, hbbr relays the
# traffic. Both need raw TCP ports open, so unlike the HTTP services on this box
# they are not behind Caddy — only the web client is.
#
# The relay key is generated into astra.secrets on first activation. Clients
# need the same key typed in, which is the whole point: without it, nobody can
# use the relay even if they find the address.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.rustdesk;
in
{
  options.services.rustdesk = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Run hbbs + hbbr in docker.";
    };

    ports = lib.mkOption {
      type = lib.types.attrs;
      default = {
        hbbs = 21115;
        hbbr = 21117;
        web = 21118;
      };
      description = ''
        Relay ports. These are baked into what you tell clients, so changing them
        means re-configuring every machine that connects here.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    imports = [ ./caddy.nix ../astra/secrets.nix ];

    astra.caddy = {
      enable = true;
      hosts = [
        {
          name = "rustdesk";
          upstream = "localhost:${toString cfg.ports.web}";
          # The web client is reached over the tailnet far more often than over
          # the open internet; leave TLS off unless you have a real name.
          tls = false;
        }
      ];
    };

    astra.secrets.generate = [
      {
        name = "rustdesk-key";
        key = "RUSTDESK_KEY";
        length = 32;
      }
    ];

    networking.firewall = {
      allowedTCPPorts = [
        cfg.ports.hbbs
        cfg.ports.hbbr
        cfg.ports.web
      ];
      # hbbs also serves UDP so clients can try a direct connection that skips
      # the relay entirely.
      allowedUDPPorts = [ cfg.ports.hbbs ];
    };

    virtualisation.oci-containers = {
      backend = "docker";

      containers.rustdesk-hbbs = {
        image = "rustdesk/rustdesk-server:latest";
        cmd = [
          "hbbs"
          "-r"
          "${config.networking.hostName}:${toString cfg.ports.hbbs}"
        ];
        networks = [ "host" ];
        environmentFiles = [ "${config.astra.secrets.dir}/rustdesk-key.env" ];
        volumes = [ "rustdesk-data:/root" ];
        autoStart = true;
      };

      containers.rustdesk-hbbr = {
        image = "rustdesk/rustdesk-server:latest";
        cmd = [ "hbbr" ];
        networks = [ "host" ];
        environmentFiles = [ "${config.astra.secrets.dir}/rustdesk-key.env" ];
        volumes = [ "rustdesk-data:/root" ];
        autoStart = true;
      };
    };
  };
}