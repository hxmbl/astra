{
  description = "astra — one flake, every machine I own";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Zen is the default browser: a Firefox fork we can build ourselves rather
    # than a binary we have to download from a vendor CDN.
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Cursor, only ever reached through `astra.desktop.vendorTools`.
    cursor = {
      url = "github:tomsch/cursor-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
      zen-browser,
      cursor,
      ...
    }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      legacy = nixpkgs.legacyPackages.${system};

      # Every host is a directory with a configuration.nix in it. Adding a
      # machine is one line here plus one file on disk; nothing else in this
      # file changes and CI reads the same list.
      hosts = {
        laptop = ./hosts/laptop;
        vm-nano = ./hosts/vm/nano;
        vm-mini = ./hosts/vm/mini;
        vm-full = ./hosts/vm/full;
        server-full = ./hosts/server/server-full;
        server-core = ./hosts/server/server-core;
        astra-home = ./hosts/astra-home;
      };

      # Passing the whole input set as specialArgs means any module can reach
      # zen-browser/cursor without flake.nix growing per-host specialArgs.
      mkHost =
        path:
        {
          nixpkgs,
          home-manager,
          ...
        }:
        lib.nixosSystem {
          inherit system;
          specialArgs = inputs // {
            astraFlake = self;
            astraInputs = inputs;
          };
          modules = [
            "${path}/configuration.nix"
            home-manager.nixosModules.home-manager
          ];
        };
    in
    {
      nixosConfigurations = lib.mapAttrs (_: mkHost) hosts;

      packages.${system} = {
        astra-info = (import ./lib/astra-info.nix { inherit nixpkgs system; }).package;
        astra-boot = import ./lib/astra-boot.nix { inherit nixpkgs system; };
      };

      # `nix fmt` in the repo formats everything with alejandra.
      formatter = legacy.alejandra;

      # A deliberately tiny shell: alejandra and nil are the only tools that
      # need to be newer than whatever the machine already has installed.
      devShells.${system}.default = legacy.mkShell {
        name = "astra";
        packages = [
          legacy.alejandra
          legacy.nil
          legacy.nixfmt-rfc-style
        ];
      };
    };
}