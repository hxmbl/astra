# astra-vm-full — the KDE desktop in a VM. Use this to test display changes
# without risking the laptop.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ../../../profiles/desktop.nix
    ../../../modules/boot/ab.nix
  ];

  networking.hostName = "astra-vm-full";

  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
  };
  # The A/B layer is designed around systemd-boot's entry list. It still tracks
  # generations and runs the health guard under grub, but there is no menu for
  # it to rewrite, so this VM is a fair test of "does the desktop come up",
  # not of rollback.
  astra.ab.supportBootEntries = false;

  fileSystems."/" = {
    device = "/dev/sda1";
    fsType = "ext4";
  };

  # A VM has no real GPU; llvmpipe is what makes Plasma start at all.
  virtualisation.graphics = {
    enable = true;
    options = [ "-vga virtio" ];
  };

  system.stateVersion = "24.11";
}