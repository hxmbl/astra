# astra-server-full — the box that owns the internet-facing services.
#
# Structure: one ingress (Caddy, ports 80/443), everything else bound to
# loopback or to a published port that genuinely needs the outside world
# (RustDesk's relay). This file is now almost entirely "which services and
# which hostname" — the definitions live in modules/services/ so the same
# modules can serve astra-home.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ../../../profiles/core.nix
    ../../../modules/boot/ab.nix

    ../../../modules/services/caddy.nix
    ../../../modules/services/dashdot.nix
    ../../../modules/services/searxng.nix
    ../../../modules/services/rustdesk.nix
  ];

  networking.hostName = "astra-server";

  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
  };

  # PLACEHOLDER — replace with real mounts on install
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # Key-only ssh. Passwords on a box that runs the front door are how people
  # lose a weekend.
  astra.ssh.extraSettings = {
    PasswordAuthentication = false;
    AuthenticationMethods = "publickey";
  };

  # ------------------------------------------------------------- the stack --
  astra.caddy = {
    enable = true;
    # No email: this box serves internal hostnames only. Put a real domain and
    # an ACME email in here when you decide it needs to be public.
    email = "";
    domain = "astra.local";
  };

  services.dashdot.enable = true;
  services.searxng.enable = true;
  services.rustdesk.enable = true;

  astra.ab = {
    supportBootEntries = false; # grub owns the boot menu on this box
    reboot = false; # it runs other people's services; never bounce it
    # This is the one machine where "is the network up" is a real health
    # question rather than a laptop in a cafe.
    requireNetwork = true;
  };

  # Server-only conveniences on top of the core profile.
  astra.packages = with pkgs; [
    restic # backups of the things that are not in the store
    tree
  ];

  # A server wants a bigger disk cache headroom than a laptop does, but it does
  # not want to hold generations forever.
  astra.nixGcDays = 30;

  system.stateVersion = "24.11";
}