# modules/services/searxng.nix — a metasearch engine you own.
#
# Searxng is the single best answer to "privacy-first search": it queries a
# dozen engines, merges the results and never sees you. It wants a Valkey
# (redis-compatible) instance for its result cache, so both run here.
#
# Networking note, because this is the decision that took the longest: both
# containers run with `--network host` and talk over 127.0.0.1. The alternative —
# a private docker network with per-container DNS aliases — is the textbook
# answer, and it is a pain to express through `virtualisation.oci-containers`
# without a compose file. Host networking costs container isolation and buys us:
#   - no port-publishing rules to get wrong
#   - searxng's config is just SEARXNG_BIND_ADDRESS=127.0.0.1
# Both services bind to loopback only, so nothing about it is reachable from the
# LAN and only Caddy is.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.searxng;
in
{
  options.services.searxng = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Run searxng + valkey as containers, behind caddy.";
    };

    settingsDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/searxng";
      description = ''
        Where settings.yml lives. A host directory rather than a docker volume
        so that editing it is `sudoedit /var/lib/searxng/settings.yml` and not a
        trip through `docker volume inspect`.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Loopback port searxng listens on.";
    };
  };

  config = lib.mkIf cfg.enable {
    imports = [ ./caddy.nix ../astra/secrets.nix ];

    astra.caddy = {
      enable = true;
      hosts = [
        {
          name = "searx";
          upstream = "localhost:${toString cfg.port}";
        }
      ];
    };

    # searxng refuses to start without a secret key and uses it to sign what it
    # writes to valkey. Generated once, reused forever, never in the store.
    astra.secrets.generate = [
      {
        name = "searxng-secret";
        key = "SEARXNG_SECRET";
        length = 32;
      }
    ];

    virtualisation.oci-containers = {
      backend = "docker";

      containers.searxng-valkey = {
        image = "valkey/valkey:9-alpine";
        networks = [ "host" ];
        volumes = [ "searxng-valkey:/data" ];
        autoStart = true;
      };

      containers.searxng = {
        image = "searxng/searxng:latest";
        networks = [ "host" ];
        volumes = [ "${cfg.settingsDir}:/etc/searxng:rw" ];
        environmentFiles = [ "${config.astra.secrets.dir}/searxng-secret.env" ];
        environment = {
          SEARXNG_BASE_URL = "http://searx.${config.astra.caddy.domain}/";
          SEARXNG_BIND_ADDRESS = "127.0.0.1";
          SEARXNG_PORT = toString cfg.port;
          SEARXNG_VALKEY_URL = "redis://127.0.0.1:6379/0";
        };
        autoStart = true;
      };

      volumes.searxng-valkey = { };
    };

    systemd.tmpfiles.rules = [ "d ${cfg.settingsDir} 0755 root root -" ];
  };
}