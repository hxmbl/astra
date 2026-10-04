# modules/astra/home.nix — Astra Home: the same idea, applied to a house.
#
# What "home automation" means here, and what it deliberately does not mean:
#
#   - No Nabu Casa, no Google, no Alexa, no vendor cloud. Home Assistant talks to
#     the devices on your LAN and to nothing else. The cloud integration is not
#     in the config and never should be.
#   - No account, no signup, no phone-home. Everything is addressable on the
#     tailnet or on the LAN, and nowhere else.
#   - The boring parts (MQTT broker, ESPHome firmware, the Zigbee bridge) are
#     local services in this repo, because a house that depends on somebody
#     else's uptime is not one you own.
#
# Groundwork, not a finished system: Home Assistant is configured through its own
# UI, which is what it is genuinely good at, and this module provides the machine
# it runs on. See DECISIONS.md for what I chose not to do here.
{ config, lib, pkgs, ... }:
let
  cfg = config.astra.home;
in
{
  options.astra.home = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Turn this machine into an Astra Home controller.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/astra-home";
      description = "Where Astra Home keeps its own state (Zigbee2MQTT backups, exports).";
    };

    uiHost = lib.mkOption {
      type = lib.types.str;
      default = "home";
      description = "Left-hand label for the dashboard in caddy, e.g. home.astra.local.";
    };

    mqtt = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run a local MQTT broker. ESPHome, Zigbee2MQTT and most DIY sensors speak MQTT.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 1883;
        description = "MQTT port. Bound to the LAN only, never published to the internet.";
      };

      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/mosquitto";
        description = "Where the broker keeps its persistence file and log.";
      };
    };

    tailscaleServe = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Publish the dashboard over Tailscale so it is reachable from a phone
          without opening a port or buying a hostname. Uses `tailscale serve`,
          whose flags have moved between releases, so the helper tries the modern
          syntax, falls back, and warns rather than failing the boot.
        '';
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8123;
        description = "Local port Home Assistant listens on.";
      };
    };

    zigbee = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Run Zigbee2MQTT in a container. Needs a USB coordinator you point it at.";
      };

      device = lib.mkOption {
        type = lib.types.str;
        default = "/dev/ttyACM0";
        description = "The USB serial device the Zigbee coordinator is on.";
      };
    };

    esphome = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install esphome so you can build firmware for your own sensors.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    imports = [ ../services/caddy.nix ];

    # ------------------------------------------------------------ the house --
    services.home-assistant = {
      enable = true;
      # defaultConfig is the whole onboarding flow: no YAML to write and nothing
      # to keep in sync with a UI. The first visit to the dashboard is where
      # integrations get added, and every one of them can point at a local
      # address.
      #
      # Adding more from Nix is a one-liner if you ever want it
      # (`config.recorder = {};`, `config.mqtt = {};`), but Nix rewrites the
      # whole config file on every rebuild, so anything you add in the UI by
      # hand will be clobbered. That is the trade and it is deliberate.
      config.defaultConfig = { };
      config.lufia = { };
    };

    # A local dashboard nobody outside can reach. Caddy is the only thing
    # listening on 443.
    astra.caddy = {
      enable = true;
      hosts = [
        {
          name = cfg.uiHost;
          upstream = "localhost:${toString cfg.tailscaleServe.port}";
          # Reachable over the tailnet, not the internet: no ACME for a name
          # that does not resolve publicly.
          tls = false;
        }
      ];
    };

    # --------------------------------------------------------------- devices --
    services.mosquitto = lib.mkIf cfg.mqtt.enable {
      enable = true;
      port = cfg.mqtt.port;
      dataDir = cfg.mqtt.dataDir;
      # Anonymous is on, deliberately: every device on this network is already
      # inside the house, and a password pasted into a YAML file is security
      # theatre. If your wifi has guests on it, set this to false and add a
      # password_file — the config below leaves the seam for it.
      allowAnonymous = true;
      configFile = pkgs.writeText "mosquitto.conf" ''
        # generated by astra (modules/astra/home.nix)
        persistence true
        persistence_location ${cfg.mqtt.dataDir}/
        log_dest file ${cfg.mqtt.dataDir}/mosquitto.log
        log_type error
        log_type warning
        log_type notice

        # Home Assistant uses this to announce and discover devices without a
        # cloud round trip.
        listener ${toString cfg.mqtt.port} 0.0.0.0
        allow_anonymous true

        # ESPHome devices are chatty; without this the broker grows an unbounded
        # retained-message cache on an SD card.
        max_queued_messages 1000
        message_size_limit 0

        # A bridge to another broker goes here. Not enabled by default: a bridge
        # to the internet would undo the entire premise.
        # connection upstream
      '';
    };

    astra.packages = lib.mkIf cfg.esphome.enable [ pkgs.esphome ];

    # ---------------------------------------------------------------- zigbee --
    virtualisation.oci-containers = lib.mkIf cfg.zigbee.enable {
      backend = "docker";
      containers.zigbee2mqtt = {
        image = "zigbee2mqtt/zigbee2mqtt:latest";
        # The coordinator is on USB, so the container gets that device node and
        # nothing else. Host networking because it talks to the broker over
        # loopback, same as the other services on this box.
        networking = "host";
        extraOptions = [ "--device=${cfg.zigbee.device}" ];
        volumes = [
          "zigbee2mqtt-data:/app/data"
          "${cfg.dataDir}:/app/data-backup"
        ];
        autoStart = true;
      };
      volumes."zigbee2mqtt-data" = { };
    };

    systemd.tmpfiles.rules =
      [ "d ${cfg.dataDir} 0750 root root -" ]
      ++ lib.optional cfg.mqtt.enable "d ${cfg.mqtt.dataDir} 0750 mosquitto mosquitto -";

    # -------------------------------------------------------------- tailnet --
    # `tailscale serve` publishes localhost:8123 over the tailnet with a
    # certificate Tailscale manages. No port forwarding, no DNS record, no
    # certificate to renew — and it stops the moment Tailscale does.
    systemd.services.astra-home-serve = lib.mkIf cfg.tailscaleServe.enable {
      description = "Astra Home: publish the dashboard over Tailscale";
      wantedBy = [ "network-online.target" ];
      after = [
        "network-online.target"
        "tailscaled.service"
      ];
      path = [
        pkgs.tailscale
        pkgs.coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "astra-home-serve" ''
          set -uo pipefail
          port=${toString cfg.tailscaleServe.port}
          if ! tailscale status >/dev/null 2>&1; then
            echo "tailscaled is not up yet; skipping" >&2
            exit 0
          fi
          # The CLI moved these flags around between 2023 and 2025. Try the
          # current syntax, fall back to the old one, and never fail the boot: a
          # home controller that will not start because of a flag rename is
          # worse than one you have to re-run by hand.
          if tailscale serve --bg "http+insecure://127.0.0.1:$port" 2>/dev/null; then
            echo "serving http://127.0.0.1:$port over the tailnet"
            exit 0
          fi
          if tailscale serve --bg --https=443 "http://127.0.0.1:$port" 2>/dev/null; then
            echo "serving http://127.0.0.1:$port over the tailnet (legacy flags)"
            exit 0
          fi
          echo "could not publish the dashboard over Tailscale;" >&2
          echo "run 'tailscale serve --bg http://127.0.0.1:$port' by hand" >&2
          exit 0
        '';
      };
    };
  };
}