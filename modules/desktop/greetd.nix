# modules/desktop/greetd.nix — the login screen.
#
# greetd + tuigreet, not SDDM/SD-Greeter and not GDM. It is a few hundred KB,
# it starts before anything else, it never phones home, and when it breaks it
# fails to a text console instead of a black rectangle. The cost is that it has
# no session picker of its own, so the sessions it offers are declared here.
#
# The NixOS module already creates the `greeter` system user that the session
# runs as; we only tell it what to run.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.astra;
in {
  config = lib.mkIf (cfg.enable && cfg.desktop.enable) {
    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          # --time is the only reason to use tuigreet. --cmd keeps the choice
          # of session out of the greeter entirely, so a broken session list can
          # never lock you out of the machine.
          command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd startplasma-wayland";
          user = "greeter";
        };
      };
    };

    # greetd looks for named sessions in $XDG_DATA_DIRS/greetd/session, and
    # nothing on NixOS puts /etc/xdg on that list by default. Without this line
    # the recovery sessions that astra-boot installs are silently never found,
    # which is exactly the kind of thing that looks like it works right up until
    # the day you need it. This one line is what makes "press Tab at the login
    # screen" true.
    systemd.services.greetd.environment.XDG_DATA_DIRS = "/etc/xdg:/run/current-system/sw/share";
  };
}
