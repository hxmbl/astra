# astra-vm-mini — core profile in a VM. The dev toolchain, docker and tailscale
# without a display: closest thing to the server hosts you can poke at.
{
  ...
}:
{
  imports = [ ../../../profiles/core.nix ];

  networking.hostName = "astra-vm-mini";

  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
  };

  fileSystems."/" = {
    device = "/dev/sda1";
    fsType = "ext4";
  };

  system.stateVersion = "24.11";
}