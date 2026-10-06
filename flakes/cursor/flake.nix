{
  description = "cursor — standalone flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    cursor = {
      url = "github:tomsch/cursor-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    cursor,
  }: let
    system = "x86_64-linux";
  in {
    packages.${system}.default = cursor.packages.${system}.default;

    apps.${system}.default = {
      type = "app";
      program = "${cursor.packages.${system}.default}/bin/cursor";
    };
  };
}
