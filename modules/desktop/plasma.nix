# modules/desktop/plasma.nix — KDE Plasma 6, the display stack it needs, and
# nothing else.
#
# The greeter lives in greetd.nix, the app/binary choices live in
# profiles/desktop.nix. This module is "make a seat" and "make it work".
{ config, lib, pkgs, ... }:
let
  cfg = config.astra;
in
{
  config = lib.mkIf cfg.enable {
    # ------------------------------------------------------------- session --
    # `enable` is the whole interface. This nixpkgs has no
    # services.desktopManager.plasma6.polkitAgent and no .xserver — enabling
    # Plasma already brings in polkit-kde-agent-1 (plasma6.nix:117) and turns on
    # XWayland (line 72), which is what the old apps need.
    services.desktopManager.plasma6.enable = true;

    # KDE is a Wayland session, so the graphics stack has to be in place for
    # anything but a framebuffer.
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    # --------------------------------------------------------- portalling --
    # The option namespace is xdg.portal, not xdg-desktop-portal
    # (nixos/modules/config/xdg/portal.nix:38) — there is no `xdg-desktop-portal`
    # option at all.
    #
    # And enabling Plasma already sets enable, extraPortals (kwallet,
    # xdg-desktop-portal-kde, xdg-desktop-portal-gtk) and configPackages
    # (plasma6.nix:294-300). Setting them again with different values is at best
    # redundant; the list below would have replaced the module's own. Left
    # alone on purpose.
    #
    # If screen sharing or the file dialog misbehaves, the thing to check first
    # is that xdg-desktop-portal-kde is in xdg.portal.extraPortals, which it
    # already is.

    # ------------------------------------------------------------- audio ---
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };
    services.pulseaudio.enable = false; # pipewire *is* the pulse server now

    # ---------------------------------------------------------- power/udev --
    services.upower.enable = true; # battery reporting without TLP fighting it
    services.udisks2.enable = true; # mounting disks from the Plasma UI
    # Lid/power-key handling is set with the typed options in
    # profiles/base.nix. Do not use services.logind.extraConfig here as well:
    # two modules setting the same attribute is an eval error, not a merge.

    # -------------------------------------------------------------- input ---
    # The submodule is enable + mouse + touchpad (libinput.nix:425), and
    # tap-to-click is `clickMethod` under touchpad — an enum of
    # none | buttonareas | clickfinger (line 158). A flat `tap-to-click` key
    # does not exist on this option.
    services.libinput = {
      enable = true;
      touchpad.clickMethod = "clickfinger";
    };

    # -------------------------------------------------------------- fonts ---
    # Ghostty's config asks for JetBrainsMono Nerd Font, so ship exactly that
    # one rather than the full 200MB Nerd Fonts bundle.
    fonts.packages = with pkgs; [
      dejavu_fonts
      noto-fonts
      (nerdfonts.override { fonts = [ "JetBrainsMono" ]; })
    ];
    fonts.fontconfig = {
      # There is no `enableDefaultFonts` in this nixpkgs — the option is
      # `enable`, and the default-font aliases are emitted whenever it is on
      # (nixos/modules/config/fonts/fontconfig.nix, defaultFontsConf at line 96).
      enable = true;
      # defaultFonts is an attrset of three lists — monospace, sansSerif and
      # serif — not a single list (same file, line 348). The values are font
      # *family* names, not packages.
      defaultFonts = {
        monospace = [
          "JetBrainsMono Nerd Font"
          "DejaVu Sans Mono"
        ];
        sansSerif = [
          "Noto Sans"
          "DejaVu Sans"
        ];
        serif = [ "Noto Serif" "DejaVu Serif" ];
      };
    };

    # ---------------------------------------------------------- behaviour ---
    # Plasma's own settings are managed from home/desktop.nix; the few knobs
    # that only make sense system-wide are here.
  };
}