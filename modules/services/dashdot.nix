# modules/services/dashdot.nix — a dashboard for the machine it runs on.
#
# Dashdot is a self-hosted alternative to the wall of vendor status pages: it
# watches one machine and tells you what that machine is doing. Local only, no
# account, no outbound calls.
{
  config,
  lib,
  ...
}: let
  cfg = config.services.dashdot;
in {
  # Imports go here, at module top level, NOT inside the mkIf below:
  #
  #   error: The option `imports' does not exist.
  #
  # The module system treats `imports` as a special key only when it is a
  # direct child of the module. Under mkIf it becomes a plain config
  # definition of a non-existent option and evaluation fails. The config
  # itself stays gated, so a host that does not enable this service still
  # gets nothing but inert option declarations.
  imports = [./caddy.nix];

  options.services.dashdot = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Run dashdot in docker, behind caddy.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3001;
      description = "Loopback port dashdot listens on.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/dashdot";
      description = "Where dashdot keeps its database.";
    };
  };

  config = lib.mkIf cfg.enable {
    astra.caddy = {
      enable = true;
      hosts = [
        {
          name = "dashdot";
          upstream = "localhost:${toString cfg.port}";
        }
      ];
    };

    virtualisation.oci-containers = {
      backend = "docker";

      containers.dashdot = {
        image = "mauricenino/dashdot:latest";
        # No inter-container dependencies, so plain bridge networking plus an
        # explicit publish is both simpler and closer to what upstream expects.
        # Bound to loopback: Caddy is the only thing that needs to reach it.
        ports = ["127.0.0.1:${toString cfg.port}:3001"];
        volumes = [
          "${cfg.dataDir}:/app/data"
          # The dashboard's whole reason to exist: host metrics.
          "/:/mnt/host:ro"
        ];
        autoStart = true;
      };
    };

    systemd.tmpfiles.rules = ["d ${cfg.dataDir} 0755 root root -"];
  };
}
