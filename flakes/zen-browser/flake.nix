{
  description = "zen-browser — standalone flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    zen-browser,
  }: let
    system = "x86_64-linux";
  in {
    packages.${system}.default = zen-browser.packages.${system}.default;

    # for `nix run` / `nix shell` standalone
    apps.${system}.default = {
      type = "app";
      program = "${zen-browser.packages.${system}.default}/bin/zen";
    };
  };
}
