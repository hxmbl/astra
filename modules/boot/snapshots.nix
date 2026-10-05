# modules/boot/snapshots.nix — optional btrfs safety net under the A/B layer.
#
# Generation A/B protects the *system*: /etc, the kernel, the package set. It
# does not protect your data, because Nix has nothing to say about /home or
# /var/lib. Snapshots do, and on btrfs they cost a few hundred MB and one
# subvolume.
#
# This is deliberately not snapper and not timeshift. `btrfs subvolume snapshot`
# plus one GC root is about sixty lines of shell that we can read, and the
# failure modes are things you can fix with a `mount` command from the rescue
# system. It only runs if you ask for it and only if / is btrfs.
#
# Ordering that matters: the snapshot has to be taken *before* switch-to-configuration
# changes anything, which is what system.activationScripts does.
{ config, lib, ... }:
let
  cfg = config.astra.ab.snapshot;
in
{
  options.astra.ab.snapshot = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Snapshot / (btrfs only) before every rebuild, and pin the previous
        generation's closure so the snapshot is still bootable after the
        garbage collector has run.
      '';
    };

    root = lib.mkOption {
      type = lib.types.str;
      default = "/.snapshots";
      description = "Directory holding the snapshots. Must be a btrfs subvolume itself.";
    };

    prefix = lib.mkOption {
      type = lib.types.str;
      default = "nixos";
      description = "Subvolume name prefix, e.g. nixos-42.";
    };

    prune = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Keep this many snapshots; 0 disables pruning.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.enable || config.fileSystems."/".fsType == null || config.fileSystems."/".fsType == "btrfs";
        message = ''
          astra.ab.snapshot.enable needs a btrfs root. Either set
          fileSystems."/".fsType = "btrfs" (and make / a subvolume, not just a
          btrfs filesystem) or turn the snapshots off — the A/B layer in
          ab.nix does not need btrfs and works on ext4.
        '';
      }
    ];

    # A subvolume to put them in. Without this they land on / and then get
    # snapshotted into themselves, which fills the disk in about a week.
    systemd.tmpfiles.rules = [ "d ${cfg.root} 0700 root root -" ];

    # The snapshot settings themselves are appended to /etc/astra/boot.conf by
    # modules/boot/ab.nix — one config file, one owner.

    system.activationScripts.astra-snapshot = ''
      if command -v astra-boot >/dev/null 2>&1; then
        if ! astra-boot snapshot >/dev/null 2>&1; then
          logger -t astra "snapshot skipped (is / a btrfs subvolume?)"
        fi
      fi
    '';

    # Pruning is done at activation rather than by a timer: a rebuild is a
    # natural moment for it, and it avoids another timer.
    system.activationScripts.astra-snapshot-prune = ''
      if [ "${toString cfg.prune}" -gt 0 ] && [ -d ${cfg.root} ]; then
        count=$(ls -1d ${cfg.root}/${cfg.prefix}-* 2>/dev/null | wc -l)
        if [ "$count" -gt ${toString cfg.prune} ]; then
          ls -1d ${cfg.root}/${cfg.prefix}-* 2>/dev/null |
            head -n $((count - ${toString cfg.prune})) |
            while read -r old; do
              logger -t astra "pruning snapshot $old"
              btrfs subvolume delete "$old" >/dev/null 2>&1
            done
        fi
      fi
    '';
  };
}