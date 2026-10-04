# astra-laptop — the machine this whole repo is actually for.
#
# A profile is 95% of this file; what lives here is the stuff that is genuinely
# about *this* machine: how it boots, what it is plugged into, and who logs in.
{
  config,
  lib,
  pkgs,
  ...
}:
{
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
  boot.loader.systemd-boot = {
    enable = true;
    # A boot menu you can actually read when something is wrong.
    timeout = 10;
    editor = false;
  };
  boot.loader.efi.canTouchEfiVariables = true;
  # Ask for a maintenance shell instead of silently dropping to a black screen
  # when the initrd cannot mount the root filesystem. This single option is the
  # difference between "unbootable" and "type one command".
  boot.initrd.systemd.ask-console = true;
  # NixOS's built-in "Rescue system" boot entry. astra-boot's recovery session
  # boots it, so recovery exists even when the normal system has no /nix.
  boot.rescueSystem.enable = true;
  boot.kernelParams = [ "quiet" "splash" "rd.systemd.show_status=1" ];
  boot.kernel.sysctl."kernel.kptr_restrict" = 1;

  # ------------------------------------------------------------------ disks --
  # PLACEHOLDER — replaced by hardware-configuration.nix on real install
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # -------------------------------------------------------------- accounts --
  astra.userGroups = [ "bluetooth" "lp" "scanner" ];
  # Declared explicitly so `extraGroups` above can never reference a group that
  # some module forgot to create. Merging an empty attrset is a no-op if nixpkgs
  # already made it.
  users.groups = {
    bluetooth = { };
    lp = { };
    scanner = { };
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
  # A laptop keyboard's firmware sends brightness/volume keys as ordinary
  # keycodes; Plasma's PowerDevil reads the right ones but only if libinput
  # knows about the media keys.
  services.logind.extraConfig = ''
    HandlePowerKey=suspend
    HandleLidSwitch=suspend
  '';

  system.stateVersion = "24.11";
}