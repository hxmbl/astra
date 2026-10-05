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
  # Imports go here, at module top level, NOT inside the mkIf below:
  #
  #   error: The option `imports' does not exist.
  #
  # The module system treats `imports` as a special key only when it is a
  # direct child of the module. Under mkIf it becomes a plain config
  # definition of a non-existent option and evaluation fails. The config
  # itself stays gated, so a host that does not enable this service still
  # gets nothing but inert option declarations.
  imports = [ ../services/caddy.nix ];

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
      # NB: `config` is a freeform submodule, so a misspelled key is not an eval
      # error — it silently becomes a YAML key that Home Assistant ignores. HA
      # integration domains are snake_case: `default_config`, not
      # `defaultConfig`. nixpkgs' own example for this option uses
      # homeassistant/frontend/http/feedreader.
      config.default_config = { };
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
    # The module generates mosquitto.conf itself from these options (see
    # nixos/modules/services/networking/mosquitto.nix:684), so there is no
    # configFile to set and no top-level port/allowAnonymous: those live on a
    # per-listener submodule (same file, listenerOptions at line 306).
    services.mosquitto = lib.mkIf cfg.mqtt.enable {
      enable = true;
      dataDir = cfg.mqtt.dataDir;

      listeners = [
        {
          port = cfg.mqtt.port;
          address = "0.0.0.0";
          # Anonymous is on, deliberately: every device on this network is
          # already inside the house, and a password pasted into a config file
          # is security theatre. If your wifi has guests on it, drop this and
          # add `users` — the seam is right there.
          omitPasswordAuth = true;
          # allow_anonymous is a *listener* freeform key
          # (mosquitto.nix:269, in freeformListenerKeys).
          settings = {
            allow_anonymous = true;
          };
        }
      ];

      # The module emits `persistence true` but not persistence_location, so
      # without this the broker file lands in its own default directory.
      #
      # These three are *global* freeform keys, not listener ones — the two
      # listener whitelists (freeformListenerKeys at :265, freeformGlobalKeys at
      # :530) are separate sets, and putting a global key under a listener
      # asserts:
      #   Failed assertions:
      #   - Invalid config key services.mosquitto.listener.0.settings.max_queued_messages.
      persistence = true;
      settings = {
        persistence_location = "${cfg.mqtt.dataDir}/";
        # ESPHome devices are chaty; without these the broker grows an unbounded
        # retained-message cache on an SD card.
        max_queued_messages = 1000;
        message_size_limit = 0;
      };

      logDest = [ "${cfg.mqtt.dataDir}/mosquitto.log" ];
      logType = [
        "error"
        "warning"
        "notice"
      ];

      # A bridge to another broker would go in `bridges`. Not enabled by
      # default: a bridge to the internet would undo the entire premise.
    };

    astra.packages = lib.mkIf cfg.esphome.enable [ pkgs.esphome ];

    # The broker listens on the LAN, so the LAN has to be able to reach it.
    # Caddy (imported above) opens 80/443; this is the one port that has to be
    # open for the house to have any sensors at all.
    networking.firewall = lib.mkIf cfg.mqtt.enable {
      allowedTCPPorts = [ (toString cfg.mqtt.port) ];
    };

    # ---------------------------------------------------------------- zigbee --
    virtualisation.oci-containers = lib.mkIf cfg.zigbee.enable {
      backend = "docker";
      containers.zigbee2mqtt = {
        image = "zigbee2mqtt/zigbee2mqtt:latest";
        # The coordinator is on USB, so the container gets that device node and
        # nothing else. Host networking because it talks to the broker over
        # loopback, same as the other services on this box.
        networks = [ "host" ];
        extraOptions = [ "--device=${cfg.zigbee.device}" ];
        volumes = [
          "zigbee2mqtt-data:/app/data"
          "${cfg.dataDir}:/app/data-backup"
        ];
        autoStart = true;
      };
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