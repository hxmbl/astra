# core.nix — base plus the things you need to actually work on and run things.
#
# core = a workstation without a screen, or a server with a keyboard you never
# touch. It adds: dev toolchain, containers, tailnet, and home-manager.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.astra;
in
{
  imports = [ ./base.nix ];

  config = lib.mkIf cfg.enable {
    astra.profiles = [ "core" ];

    # Docker puts the `docker` group in existence itself, so adding it here is
    # safe and is the only way a host gets rootless-ish docker access.
    astra.userGroups = [ "docker" ];

    astra.packages = with pkgs; [
      adb
      btop
      docker-compose
      fastfetch
      fd
      gh
      go
      jq
      neovim
      nil
      nix-direnv
      python3
      rustup
      speedtest-cli
      tailscale
      tmux
      zoxide
    ];

    # --------------------------------------------------------------- docker --
    virtualisation.docker = {
      enable = true;
      autoPrune.enable = true;
    };

    # ------------------------------------------------------------ tailscale --
    services.tailscale = {
      enable = true;
      # Client-only by default: no exit node, no subnet router, no DNS
      # takeover. A host that needs one must say so out loud.
      useRoutingFeatures = "client";
      extraUpFlags = [ "--accept-dns=false" ];
    };

    # --------------------------------------------------------- home-manager --
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      users = {
        ${cfg.user} = {
          # `../home`, not `../../home`: this file sits one level below the
          # flake root (profiles/core.nix), so two levels up is /nix/store.
          #   error: path '/nix/store/home' does not exist
          imports = [ ../home ];
          # `desktop` is the single flag home/ needs to decide whether it is
          # managing a desktop or a shell on a server. mkDefault so that
          # profiles/desktop.nix setting it to true is not a second definition
          # of the same attribute — the module system treats two plain
          # definitions of one option as a conflict.
          astra.desktop.enable = lib.mkDefault cfg.desktop.enable;
          astra.userName = cfg.user;
        };
      };
    };
  };
}