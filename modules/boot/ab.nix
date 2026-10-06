# modules/boot/ab.nix — generation-based A/B boot.
#
# The whole policy lives in modules/boot/bin/astra-boot; this file only wires it
# into the system: the config file, the health checks, three systemd units and
# one activation hook. Everything the tool can do, a human can also do by hand
# with the same command, which is the property that makes this safe to leave
# running unattended.
#
# The model, in one paragraph: every `nixos-rebuild switch` marks the generation
# it activated as "testing". The next boot runs a handful of health checks; a
# generation that stays healthy for `promoteAfter` seconds becomes the stable
# one and the boot menu is rewritten to default to it. A generation that fails
# `failures` times in a row gets skipped and the machine reboots itself into the
# last generation that did work.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.astra.ab;

  # snapshots.nix declares astra.ab.snapshot.*, which ab.nix writes into
  # boot.conf. Imported here so any host that gets the A/B layer also gets the
  # snapshot knobs, switched off.
  #

  checkType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "File name; the leading number is the order checks run in.";
      };

      script = lib.mkOption {
        type = lib.types.lines;
        description = "sh script. Exit 0 means healthy; printed text becomes the log line.";
      };
    };
  };

  # Checks that apply to any machine. Host-specific ones are added by hosts.
  defaultChecks =
    [
      {
        name = "10-store.check";
        script = ''
          # The store is the system. If this is gone there is nothing to roll
          # back to and the machine is already in recovery, so fail loudly
          # rather than sitting at a black screen waiting for a login prompt
          # that will never work.
          [ -d /nix/store ] || { echo "no /nix/store"; exit 1; }
          [ -e /run/current-system/init ] || { echo "/run/current-system is not a NixOS system"; exit 1; }
          nix-store --load-db >/dev/null 2>&1 || { echo "cannot load the nix database"; exit 1; }
          echo "store ok ($(ls -1 /nix/store | wc -l) paths)"
        '';
      }
      {
        name = "20-rootfs.check";
        script = ''
          # A read-only root means activation silently half-worked. It also means
          # the next switch cannot fix anything, so this is worth a reboot.
          if findmnt -no OPTIONS / | grep -qw ro; then
            echo "root filesystem is mounted read-only"
            exit 1
          fi
          echo "root rw"
        '';
      }
      {
        name = "30-units.check";
        script = ''
          failed=0
          for unit in ${lib.concatStringsSep " " cfg.requiredUnits}; do
            if ! systemctl is-active --quiet "$unit"; then
              echo "required unit $unit is not active: $(systemctl is-active "$unit")"
              failed=1
            fi
          done
          [ "$failed" = 0 ] || exit 1
          echo "units ok (${toString (lib.length cfg.requiredUnits)} required)"
        '';
      }
    ]
    ++ lib.optional cfg.requireNetwork {
      name = "40-network.check";
      script = ''
        # Only a check when you asked for one: a laptop with the wifi off is
        # perfectly healthy, and rolling a generation back because of it would
        # be worse than the bug it is meant to catch.
        if ! systemctl is-active --quiet NetworkManager; then
          echo "NetworkManager is not active"
          exit 1
        fi
        if ! getent hosts one.one.one.one >/dev/null 2>&1; then
          echo "DNS is not resolving"
          exit 1
        fi
        echo "network ok"
      '';
    }
    ++ lib.optional (cfg.supportBootEntries && config.boot.loader.systemd-boot.enable) {
      name = "05-bootloader.check";
      script = ''
        # If the boot menu cannot be rewritten we cannot promise a rollback, so
        # this is a first-class health check rather than a hope.
        esp=""
        for m in /boot /efi; do
          if mountpoint -q "$m"; then esp=$m; break; fi
        done
        [ -n "$esp" ] || { echo "no EFI system partition mounted at /boot or /efi"; exit 1; }
        [ -w "$esp" ] || { echo "ESP at $esp is not writable"; exit 1; }
        if [ ! -d "$esp/loader/entries" ]; then
          echo "no boot entries directory at $esp"
          exit 1
        fi
        n=$(ls -1 "$esp"/loader/entries/astra-*.conf 2>/dev/null | wc -l)
        [ "$n" -ge 1 ] || { echo "astra has no boot entries on $esp"; exit 1; }
        echo "boot menu ok ($n astra entries on $esp)"
      '';
    };
in {
  imports = [./snapshots.nix];

  options.astra.ab = {
    enable = lib.mkOption {
      type = lib.types.bool;
      # systemd-boot is the loader this is designed around: it can have its entry
      # list rewritten at runtime, which is what makes "boot the old one" a thing
      # the machine can do by itself.
      default = config.boot.loader.systemd-boot.enable;
      description = "Generation A/B: health guard, self-rollback, recovery tooling.";
    };

    supportBootEntries = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Let astra write its own systemd-boot entries. Turn this off on hosts
        where something else owns the boot menu; the health guard, the state
        machine and the CLI keep working, there is just no menu to roll back
        into automatically.
      '';
    };

    keep = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "How many recent generations to keep in the boot menu.";
    };

    interval = lib.mkOption {
      type = lib.types.int;
      default = 20;
      description = "Seconds between guard runs.";
    };

    failures = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "Consecutive failed guard runs before rolling back.";
    };

    promoteAfter = lib.mkOption {
      type = lib.types.int;
      default = 300;
      description = "Seconds a generation must be healthy before it becomes the stable one.";
    };

    reboot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Let the guard reboot into the last good generation. Off means it reports
        and leaves the decision to a human, which is the right setting for a
        machine somebody is sitting in front of.
      '';
    };

    requireNetwork = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Add a network health check. Off by default: being offline is not broken.";
    };

    requiredUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      # A desktop is only healthy if you can log into it. Nothing is required of
      # a headless machine: nothing about it should decide to reboot the box.
      default = lib.optional config.astra.desktop.enable "greetd.service";
      description = "systemd units that must be active for a generation to count as healthy.";
    };

    haltOnPanic = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Hang on a kernel panic instead of rebooting, so a panicking kernel lands
        you at the boot menu instead of in a reboot loop. Off means the machine
        reboots after 10 seconds, which is what you want on a headless box and
        is a loop you have to break by hand on a laptop.
      '';
    };

    checks = lib.mkOption {
      type = lib.types.listOf checkType;
      default = defaultChecks;
      description = ''
        Health checks, in order. Each is a shell script run with `sh`; exit 0 is
        healthy. Add to this list from a host to add a check without editing this
        module.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && config.astra.enable) {
    environment.systemPackages = [(import ../../lib/astra-boot.nix {inherit pkgs;})];

    # ------------------------------------------------------------- astra-boot --
    # One attribute set, built in one place: Nix refuses two definitions of
    # `environment.etc` in the same module, and merging three unrelated things
    # with `//` is clearer than remembering which one goes where.
    environment.etc =
      {
        "astra/boot.conf" = {
          text = ''
            # generated by astra (modules/boot/ab.nix) — edit modules/boot/ab.nix
            ASTRA_KEEP=${toString cfg.keep}
            ASTRA_INTERVAL=${toString cfg.interval}
            ASTRA_FAILURES=${toString cfg.failures}
            ASTRA_PROMOTE_AFTER=${toString cfg.promoteAfter}
            ASTRA_REBOOT=${
              if cfg.reboot
              then "1"
              else "0"
            }
            ASTRA_REQUIRE_NETWORK=${
              if cfg.requireNetwork
              then "1"
              else "0"
            }
            ASTRA_SNAPSHOT_ROOT=${config.astra.ab.snapshot.root}
            ASTRA_SNAPSHOT_PREFIX=${config.astra.ab.snapshot.prefix}
            ASTRA_DEFAULT_CMDLINE=(${lib.escapeShellArgs (config.boot.kernelParams ++ ["systemd.show_status=1"])})
          '';
          mode = "0444";
        };

        "xdg/greetd/session/astra-recover.conf" = {
          text = ''
            # astra recovery session: a root shell on tty1, no password, no
            # display. Pick it at the login screen with Tab.
            #
            # greetd runs the command itself on the tty it has already set up,
            # so this is a shell, not an agetty — nesting agetty inside a greeter
            # session means two things fighting over the same tty.
            [command]
            command = "${pkgs.bash}/bin/bash --login"
            user = "root"
            type = "tty"

            # greetd has moved this key between sections between versions;
            # setting it in both is harmless and works either way.
            [default]
            type = "tty"
          '';
          mode = "0444";
        };

        "xdg/greetd/session/astra-shell.conf" = {
          text = ''
            # A plain console login for ${config.astra.user}, for when the desktop
            # is the thing that is broken.
            [command]
            command = "${pkgs.zsh} -l"
            user = "${config.astra.user}"
            type = "tty"

            [default]
            type = "tty"
          '';
          mode = "0444";
        };
      }
      // lib.listToAttrs (
        map (c: {
          name = "astra/health.d/${c.name}";
          value = {
            text = c.script;
            mode = "0555";
          };
        })
        cfg.checks
      );

    # ---------------------------------------------------------------- units --
    # Arming runs before the display manager: if this generation is going to be
    # rejected, find out before anyone tries to log into it.
    systemd.services.astra-boot-arm = {
      description = "astra: A/B arm (decide if this generation is under test)";
      wantedBy = ["multi-user.target"];
      before = [
        "greetd.service"
        "display-manager.service"
        "systemd-user-sessions.service"
      ];
      after = [
        "local-fs.target"
        "systemd-remount-fs.service"
      ];
      path = [
        pkgs.coreutils
        pkgs.util-linux
        pkgs.systemd
        pkgs.gnugrep
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "astra-boot arm";
      };
    };

    # The passive pass: pure logging, no side effects. Run it by hand when you
    # want to know what the machine thinks of itself.
    systemd.services.astra-health = {
      description = "astra: health check (logs only; the guard acts on it)";
      wantedBy = ["multi-user.target"];
      after = [
        "multi-user.target"
        "astra-boot-arm.service"
      ];
      path = [
        pkgs.coreutils
        pkgs.util-linux
        pkgs.systemd
        pkgs.gnugrep
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "astra-boot health";
        # A failing check is information, not a broken unit: the guard is what
        # acts on it. Keeping this unit green means `systemctl --failed` stays
        # meaningful for the things that are actually broken.
        SuccessExitStatus = 1;
      };
    };

    systemd.services.astra-boot-guard = {
      description = "astra: A/B guard (promote or roll back)";
      after = ["multi-user.target"];
      path = [
        pkgs.coreutils
        pkgs.util-linux
        pkgs.systemd
        pkgs.gnugrep
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "astra-boot guard";
      };
    };

    systemd.timers.astra-boot-guard = {
      description = "astra: A/B guard";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "${toString (cfg.interval * 3)}s";
        OnUnitActiveSec = "${toString cfg.interval}s";
        AccuracySec = "5s";
        RandomizedDelaySec = "3s";
        Unit = "astra-boot-guard.service";
      };
    };

    # ----------------------------------------------------------- activation --
    # Every switch marks the generation it activated as "testing". This is the
    # line that makes the whole thing work; if it fails to run, a new generation
    # silently becomes the default with nobody watching it.
    system.activationScripts.astra-ab = ''
      if command -v astra-boot >/dev/null 2>&1; then
        astra-boot pending >/dev/null 2>&1 ||
          logger -t astra "could not arm the A/B guard (see: journalctl -u astra-boot-arm)"
      fi
    '';

    # --------------------------------------------------------------- panics --
    # haltOnPanic = true hangs on a kernel panic, which lands you at the boot
    # menu where you can pick another generation. Otherwise reboot after ten
    # seconds, which is right for a headless machine and a reboot loop you have
    # to break by hand on a laptop.
    #
    # Via kernelParams, because boot.kernel.panic and boot.panicOnOops are not
    # options in this nixpkgs — 'panicOnOops' appears nowhere under nixos/, and
    # every module that wants this behaviour passes it on the command line
    # instead (misc/crashdump.nix:66, virtualisation/azure-common.nix:43,
    # digital-ocean-config.nix:51).
    boot.kernelParams =
      lib.optional cfg.haltOnPanic "panic=0"
      ++ lib.optionals (!cfg.haltOnPanic) [
        "panic=10"
      ];
  };
}
