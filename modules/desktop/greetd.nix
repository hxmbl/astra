# modules/desktop/greetd.nix — the login screen.
#
# greetd + tuigreet, not SDDM/SD-Greeter and not GDM. It is a few hundred KB,
# it starts before anything else, it never phones home, and when it breaks it
# fails to a text console instead of a black rectangle. The cost is that it has
# no session picker of its own, so the sessions it offers are declared here.
#
# The NixOS module already creates the `greeter` system user that the session
# runs as; we only tell it what to run.
{ config, lib, pkgs, ... }:
let
  cfg = config.astra;
in
{
  config = lib.mkIf (cfg.enable && cfg.desktop) {
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
  };
}