# modules/astra/secrets.nix — a place for secrets that is not the Nix store.
#
# Anything written from a Nix expression ends up world-readable in /nix/store,
# including "secrets". So the rule in astra is: the flake knows *where* a secret
# lives, never what it is.
#
# Two ways a secret gets to ${astra.secrets.dir}:
#
#   1. Generated. List a name in `astra.secrets.generate` and this module creates
#      `<name>.env` (KEY=value, 0600) on every activation if it does not already
#      exist. Good for service-to-service tokens where losing the value just
#      means "log in again".
#
#   2. Injected from outside. sops, agenix, a password manager, a systemd
#      credential — anything that writes the file at boot. Point
#      `virtualisation.oci-containers...environmentFiles` at it and it is read
#      only by that one unit.
#
# The directory is deliberately outside the store and outside /run, because a
# generated secret that changes on every reboot breaks exactly the things that
# depend on it.
{ config, lib, pkgs, ... }:
let
  cfg = config.astra.secrets;
in
{
  options.astra.secrets = {
    dir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/astra/secrets";
      description = ''
        Root-only directory for generated and injected secrets. Persistent on
        purpose: regenerating a secret on every boot invalidates whatever was
        signed with it.
      '';
    };

    mode = lib.mkOption {
      type = lib.types.str;
      default = "0700";
      description = "Permissions for astra.secrets.dir.";
    };

    generate = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Base file name; the file written is <name>.env.";
            };

            key = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = ''
                Environment variable name to put the secret in. Defaults to
                <name> with dashes replaced by underscores, uppercased.
              '';
            };

            length = lib.mkOption {
              type = lib.types.int;
              default = 32;
              description = "Hex characters of entropy.";
            };
          };
        }
      );
      default = [ ];
      example = [
        {
          name = "searxng-secret";
          length = 32;
        }
      ];
      description = "Secrets to generate on activation if they do not exist yet.";
    };
  };

  config = {
    systemd.tmpfiles.rules = [ "d ${cfg.dir} ${cfg.mode} root root -" ];

    # Runs before switch-to-configuration changes anything, so a service can
    # already read its file during activation.
    #
    # A plain string: system.activationScripts.<name> is types.lines, so
    # lib.stringAfter's list is a type error ("cannot coerce a function to a
    # string"). Ordering is lexicographic by attribute name instead, which for
    # these four scripts is already the order we want:
    #   astra-ab, astra-secrets, astra-snapshot, astra-snapshot-prune
    # ('e' < 'n', so "astra-secrets" sorts before "astra-snapshot").
    system.activationScripts.astra-secrets = ''
      mkdir -p ${cfg.dir}
      chmod ${cfg.mode} ${cfg.dir}
    ''
    + lib.concatMapStrings (
      s:
      let
        key =
          if s.key != "" then
            s.key
          else
            lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] s.name);
        file = "${cfg.dir}/${s.name}.env";
      in
      ''
        if [ ! -s ${lib.escapeShellArg file} ]; then
          umask 077
          printf '%s=%s\n' ${lib.escapeShellArg key} "$(openssl rand -hex ${toString s.length})" > ${lib.escapeShellArg file}
          echo "astra: generated ${file}"
        fi
        chmod 0600 ${lib.escapeShellArg file}
      ''
    ) cfg.generate;

    environment.systemPackages = [ pkgs.openssl ];
  };
}