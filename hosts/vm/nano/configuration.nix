# astra-vm-nano — the smallest thing that boots. Throwaway VM for testing the
# flake itself; if this one evaluates and boots, the hierarchy is wired up.
{
  lib,
  pkgs,
  ...
}:
{
  imports = [ ../../../profiles/base.nix ];

  networking.hostName = "astra-vm-nano";

  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
  };

  fileSystems."/" = {
    device = "/dev/sda1";
    fsType = "ext4";
  };

  # Proof of life: if the profile stack is broken, this fails loudly at boot
  # instead of leaving you to guess from an empty shell.
  systemd.services.astra-smoke-test = {
    description = "Astra smoke test";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      type = "oneshot";
      ExecStart = lib.getExe' pkgs.coreutils "true";
      RemainAfterExit = true;
    };
  };

  system.stateVersion = "24.11";
}