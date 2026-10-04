# astra-home — the house controller.
#
# Same flake, same profile stack, same A/B boot layer as every other machine.
# The only thing that makes this box different is modules/astra/home.nix: a local
# Home Assistant, a local MQTT broker, ESPHome for writing your own sensor
# firmware, and no cloud account anywhere in sight.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ../../profiles/core.nix
    ../../modules/boot/ab.nix
    ../../modules/astra/home.nix
  ];

  networking.hostName = "astra-home";

  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
  };

  # PLACEHOLDER — replace with real mounts on install
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  astra.ssh.extraSettings = {
    PasswordAuthentication = false;
    AuthenticationMethods = "publickey";
  };

  # A house controller is a server: it should never bounce itself because a
  # health check failed while you are not there to notice.
  astra.ab = {
    enable = true; # the default assumes systemd-boot; this box boots grub
    supportBootEntries = false;
    reboot = false;
    requireNetwork = true;
  };

  astra.home = {
    enable = true;
    uiHost = "home";

    mqtt.enable = true;

    # Turn this on once a coordinator is plugged in and you know its device
    # path (`ls /dev/ttyACM*` or `dmesg | tail` after plugging it in).
    zigbee.enable = false;
  };

  # Sensors on the bookshelf, a switch in the hallway, the printer in the hall:
  # all local, all mDNS, none of it leaving the house.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  system.stateVersion = "24.11";
}