# home/default.nix — the entry point for every home-manager profile in astra.
#
# The host decides *who* this is and *whether* it is a desktop; everything else
# is here. Keeping the desktop bits behind `astra.desktop.enable` means a
# server gets a good shell without a single KDE-specific file being activated.
{
  config,
  lib,
  ...
}:
{
  imports = [ ./common.nix ./desktop.nix ];

  options.astra = {
    userName = lib.mkOption {
      type = lib.types.str;
      default = "user";
      description = "Login name; set by profiles/core.nix from astra.user.";
    };

    desktop = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Manage the KDE desktop session (Ghostty, browser policy, Plasma settings).";
      };
    };
  };

  config = {
    # mkDefault, not a plain assignment: home-manager's NixOS module already
    # derives these from the `home-manager.users.<name>` attribute, and two
    # definitions of the same option is a hard eval error. mkDefault yields
    # politely when someone else has an opinion.
    home.username = lib.mkDefault config.astra.userName;
    home.homeDirectory = lib.mkDefault "/home/${config.astra.userName}";
    # Bump when you have actually migrated; never bump to "make it quiet".
    home.stateVersion = "24.11";

    xdg.enable = true;
  };
}