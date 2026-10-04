# astra-server-core — the smallest thing that is useful as a server: sshd, a
# firewall, a hostname. Everything else on it is deliberate.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ../../../profiles/base.nix

    # Generation health checks, but no rebooting: nobody wants a headless box to
    # bounce itself because a check failed. The log is the notification.
    ../../../modules/boot/ab.nix
  ];

  networking.hostName = "astra-server-core";

  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
  };

  # PLACEHOLDER — replace with real mounts on install
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # Key-only ssh. Anything else on this box is a mistake.
  astra.ssh.extraSettings = {
    PasswordAuthentication = false;
    AuthenticationMethods = "publickey";
  };

  networking.firewall.allowedTCPPorts = [ 22 ];

  astra.ab = {
    # enable explicitly: the default is "on if systemd-boot is the loader", and
    # this box boots grub.
    enable = true;
    # grub owns the boot menu here, so astra does not try to rewrite it.
    supportBootEntries = false;
    # Log, never reboot. A server that bounces itself because a health check
    # failed turns a small problem into an outage.
    reboot = false;
  };

  # A server has no use for a dev toolchain, but it does need the tools that
  # make `nixos-rebuild` and a container runtime pleasant to live with.
  astra.packages = with pkgs; [ bash-completion tree ];

  system.stateVersion = "24.11";
}