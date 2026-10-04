# SSH defaults for every astra machine.
#
# Lives in its own module rather than in profiles/base.nix so that hosts which
# do not want a remote shell at all (`astra.ssh.enable = false`) can say so
# without base.nix growing a second opinion about it.
{ config, lib, pkgs, ... }:
let
  cfg = config.astra.ssh;
in
{
  options.astra.ssh = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run sshd. Turn off for machines that never accept a remote login.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 22;
      description = "sshd port.";
    };

    hostKeys = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "Extra host keys to generate. Empty means the distro default (ed25519 + rsa).";
    };
  };

  config = lib.mkIf cfg.enable {
    services.openssh = {
      enable = true;
      ports = [ cfg.port ];
      hostKeys = lib.mkIf (cfg.hostKeys != [ ]) cfg.hostKeys;
      settings = {
        # No root login, no X11 forwarding (we are Wayland), no password
        # guessing games. Servers tighten PasswordAuthentication further.
        PermitRootLogin = "no";
        X11Forwarding = "no";
        KbdInteractiveAuthentication = "no";
        # WhyThisIsRequired... n/a. Compression costs CPU on a LAN.
        Compression = "no";
        ClientAliveInterval = "120";
        ClientAliveCountMax = "3";
      } // cfg.extraSettings;
    };

    # Host keys live on the persistent root fs and are generated on first boot;
    # systemd creates /etc/ssh early enough, this just makes the intent explicit.
    systemd.tmpfiles.rules = [ "d /etc/ssh 0755 root root -" ];
  };
}