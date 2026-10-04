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
    services.desktopManager.plasma6 = {
      enable = true;
      # Without a polkit agent every "do you want to remount /" dialog silently
      # never appears, which is the single most common "KDE is broken" report.
      polkitAgent.enable = true;
      # Plasma 6 is Wayland; XWayland is still pulled in by the session itself
      # for the apps that need it (older Electron, some CAD tools).
      xserver.enable = false;
    };

    # KDE is a Wayland session, so the graphics stack has to be in place for
    # anything but a framebuffer.
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    # --------------------------------------------------------- portalling --
    xdg-desktop-portal = {
      enable = true;
      # gtk covers Qt/GTK apps, plasma covers Plasma's own (screenshare, the
      # file chooser, global shortcuts). `plasma` here is xdg-desktop-portal-kde,
      # which ships inside plasma-workspace.
      extraPortals = [ "gtk" "plasma" ];
    };

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
    services.logind.extraConfig = ''
      HandleLidSwitch=suspend
      HandleLidSwitchExternalPower=ignore
    '';

    # -------------------------------------------------------------- input ---
    # Tap-to-click is not on by default in NixOS and turning it on in System
    # Settings is the sort of thing you rediscover every fresh install.
    services.libinput = {
      enable = true;
      tap-to-click = true;
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
      enableDefaultFonts = true;
      defaultFonts = [
        "Noto Sans"
        "DejaVu Sans Mono"
        "JetBrainsMono Nerd Font"
      ];
    };

    # ---------------------------------------------------------- behaviour ---
    # Plasma's own settings are managed from home/desktop.nix; the few knobs
    # that only make sense system-wide are here.
  };
}