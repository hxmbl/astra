# SSH defaults for every astra machine.
#
# The astra.ssh.* options are declared in profiles/base.nix, which owns the
# whole astra.* surface; this module is only the implementation. It used to
# declare them itself, and importing both made every host fail to evaluate:
#
#   error: The option `astra.ssh.enable' in `.../profiles/base.nix' is already
#          declared in `.../modules/astra/ssh.nix'
#
# In NixOS two mkOption declarations of the same path are a hard error, not a
# merge, so the ownership has to be in exactly one file.
{
  config,
  lib,
  ...
}: let
  cfg = config.astra.ssh;
in {
  config = lib.mkIf cfg.enable {
    services.openssh = {
      enable = true;
      ports = [cfg.port];
      hostKeys = lib.mkIf (cfg.hostKeys != []) cfg.hostKeys;
      settings =
        {
          # No root login, no X11 forwarding (we are Wayland), no keyboard-interactive
          # auth. Servers tighten PasswordAuthentication further.
          #
          # Types matter here: settings is freeform (so Compression and the
          # ClientAlive* keys take plain strings), but the keys nixpkgs declares
          # are checked. X11Forwarding and KbdInteractiveAuthentication are
          # `nullOr bool` (sshd.nix:536, :565), PermitRootLogin is an enum that
          # does include "no" (:550).
          PermitRootLogin = "no";
          X11Forwarding = false;
          KbdInteractiveAuthentication = false;
          Compression = "no";
          ClientAliveInterval = "120";
          ClientAliveCountMax = "3";
        }
        // cfg.extraSettings;
    };

    # Host keys live on the persistent root fs and are generated on first boot;
    # systemd creates /etc/ssh early enough, this just makes the intent explicit.
    systemd.tmpfiles.rules = ["d /etc/ssh 0755 root root -"];
  };
}
