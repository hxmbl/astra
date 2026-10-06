# desktop.nix — base + core + KDE Plasma 6.
#
# This profile was Hyprland until 2026-10-04. The short version of why KDE:
# a tiling WM is a hobby you maintain; Plasma is a product that handles
# docking, external monitors, colour management, sleep/resume and a working
# settings app for free. Everything hand-tuned in hyprland.conf has a
# first-class equivalent now, and the things that do not (suspend-then-resume on
# a laptop with two GPUs) were never going to be worth debugging.
#
# What this profile deliberately does NOT do:
#   - start a second compositor, a second greeter or a second lock screen
#   - install vendor IDEs by default (see astra.desktop.vendorTools below)
#   - layer an app launcher on top of Plasma's own
{
  config,
  lib,
  pkgs,
  cursor,
  zen-browser,
  ...
}: let
  cfg = config.astra;
  system = pkgs.stdenv.hostPlatform.system;
in {
  imports = [
    ./core.nix
    ../modules/desktop/plasma.nix
    ../modules/desktop/greetd.nix
  ];

  options.astra.desktop = {
    vendorTools = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install VS Code, Cursor, Android Studio and JetBrains Toolbox. Off by
        default: astra is meant to run on Zed plus free software, and these are
        the four places vendor telemetry and forced accounts creep in. Turn it on
        per host with `astra.desktop.vendorTools = true;`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    astra.profiles = ["desktop"];
    astra.desktop.enable = true;

    astra.userGroups = ["video" "audio" "input" "render"];

    astra.packages =
      (with pkgs; [
        ghostty # the terminal. Wayland-native, GPU-accelerated, one config file
        zed-editor # the editor
        localsend # local file/clipboard transfer, no cloud, no account
      ])
      ++ lib.optionals cfg.desktop.vendorTools (
        with pkgs; [
          android-studio
          cursor.packages.${system}.default
          jetbrains-toolbox
          # The nixpkgs attribute is `vscode`, not `visual-studio-code`
          # (pkgs/top-level/all-packages.nix:10005, mainProgram "code").
          vscode
        ]
      )
      ++ [
        # Zen is a Firefox fork we can build from source; nixpkgs' firefox is
        # the boring fallback when a site breaks. `pkgs.` is spelled out
        # because this list is not inside a `with pkgs;`.
        zen-browser.packages.${system}.default
        pkgs.firefox
      ];
  };
}
