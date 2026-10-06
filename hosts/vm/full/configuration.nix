# astra-vm-full — the KDE desktop in a VM. Use this to test display changes
# without risking the laptop.
{...}: {
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
  astra.ab = {
    enable = true;
    supportBootEntries = false;
  };

  fileSystems."/" = {
    device = "/dev/sda1";
    fsType = "ext4";
  };

  # No QEMU options here on purpose. This is the *guest* configuration: it is
  # whatever runs inside the VM, and the VM's own build (nixos-rebuild build-vm,
  # or a `virtualisation.vmVariant` wrapper) supplies the hardware flags.
  # virtualisation.graphics and virtualisation.qemu.* only exist when
  # qemu-vm.nix is in the module list (nixos/modules/virtualisation/qemu-vm.nix:537),
  # which it is not for this host:
  #
  #   error: The option `virtualisation.graphics' does not exist.

  system.stateVersion = "24.11";
}
