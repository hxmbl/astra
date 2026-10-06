# astra-laptop — the machine this whole repo is actually for.
#
# A profile is 95% of this file; what lives here is the stuff that is genuinely
# about *this* machine: how it boots, what it is plugged into, and who logs in.
{...}: {
  imports = [
    ../../profiles/desktop.nix

    # Generation-based A/B boot, health guard, recovery. See modules/boot/ab.nix.
    ../../modules/boot/ab.nix
    ../../modules/boot/snapshots.nix

    # ./hardware-configuration.nix   # generated on install by install.sh
  ];

  networking.hostName = "astra-laptop";
  # astra.timeZone = "Europe/Amsterdam";

  # --------------------------------------------------------------- bootloader --
  boot.loader = {
    # A boot menu you can actually read when something is wrong.
    #
    # `boot.loader.timeout`, not boot.loader.systemd-boot.timeout: the
    # systemd-boot module has no such option (its only sub-options are
    # editor, extraEntries, extraFiles, windows, graceful, configurationLimit,
    # consoleMode). The menu timeout lives on the loader-generic module
    # (nixos/modules/system/boot/loader/loader.nix:12, nullOr int, default 5)
    # and systemd-boot reads it (systemd-boot.nix:54, "menu-force" when null).
    timeout = 10;
    systemd-boot = {
      enable = true;
      editor = false;
    };
  };
  boot.loader.efi.canTouchEfiVariables = true;
  # Ask for a maintenance shell instead of silently dropping to a black screen
  # when the initrd cannot mount the root filesystem. This single option is the
  # difference between "unbootable" and "type one command".
  #
  # `boot.initrd.systemd.ask-console` does not exist. The real option is
  # emergencyAccess (bool or a hashed password string):
  # nixos/modules/system/boot/systemd/initrd.nix:312. After the initrd, the
  # equivalent is systemd.enableEmergencyMode
  # (nixos/modules/system/boot/emergency-mode.nix:13), which defaults to true.
  boot.initrd.systemd.emergencyAccess = true;
  boot.kernelParams = ["quiet" "splash" "rd.systemd.show_status=1"];
  boot.kernel.sysctl."kernel.kptr_restrict" = 1;

  # ------------------------------------------------------------------ disks --
  # PLACEHOLDER — replaced by hardware-configuration.nix on real install
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # -------------------------------------------------------------- accounts --
  astra.userGroups = ["bluetooth" "lp" "scanner"];
  # Declared explicitly so `extraGroups` above can never reference a group that
  # some module forgot to create. Merging an empty attrset is a no-op if nixpkgs
  # already made it.
  users.groups = {
    bluetooth = {};
    lp = {};
    scanner = {};
  };

  # ---------------------------------------------------------------- memory --
  zramSwap = {
    enable = true;
    memoryPercent = 50;
    # Compressed swap makes suspend-to-disk cheap enough that the lid switch
    # does not have to be rationed.
    priority = 5;
  };

  # A static swap file is a hard floor for hibernation; 8 GB is the minimum
  # that makes `memfd_auto` style suspend useful on a modern laptop.
  swapDevices = [
    {
      device = "/swapfile";
      size = 8192;
    }
  ];

  # -------------------------------------------------------------- hardware --
  hardware.enableAllFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;

  # printing + scanning, locally, no cloud print service
  services.printing.enable = true;
  hardware.sane.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  # --------------------------------------------------------------- keyboard --
  # The lid switch, power key and idle behaviour are all set with the typed
  # logind options in profiles/base.nix. A laptop keyboard's brightness and
  # volume keys are read by Plasma's own PowerDevil, so there is no keybinding
  # to add here.

  system.stateVersion = "24.11";
}
