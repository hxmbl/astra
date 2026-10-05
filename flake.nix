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

      # Every host is one line, pointing straight at its configuration.nix. Adding a
      # machine is one line here plus one file on disk; nothing else in this
      # file changes and CI reads the same list.
      #
      # These are paths, not strings, and that matters: a module reached as a
      # string is parsed with no base directory, so every relative `imports`
      # inside it (./base.nix, ./core.nix) resolves from / and evaluation dies
      # with 'path /profiles/base.nix does not exist'. Interpolating a path into
      # a string ("${path}/configuration.nix") does exactly that. Naming the
      # file directly keeps the context.
      hosts = {
        laptop = ./hosts/laptop/configuration.nix;
        vm-nano = ./hosts/vm/nano/configuration.nix;
        vm-mini = ./hosts/vm/mini/configuration.nix;
        vm-full = ./hosts/vm/full/configuration.nix;
        server-full = ./hosts/server/server-full/configuration.nix;
        server-core = ./hosts/server/server-core/configuration.nix;
        astra-home = ./hosts/astra-home/configuration.nix;
      };

      # Passing the whole input set as specialArgs means any module can reach
      # zen-browser/cursor without flake.nix growing per-host specialArgs.
      #
      # One argument only. The flake inputs are already bound by the outer
      # `outputs` function, so a second parameter would leave every host as an
      # unapplied function: `nixosConfigurations.<name>` evaluates to a lambda
      # rather than a system, and nothing in the flake is usable.
      mkHost =
        host:
        lib.nixosSystem {
          inherit system;
          specialArgs = inputs // {
            astraFlake = self;
            astraInputs = inputs;
          };
          modules = [
            host
            home-manager.nixosModules.home-manager
          ];
        };
    in
    {
      nixosConfigurations = lib.mapAttrs (_: mkHost) hosts;

      packages.${system} = {
        astra-info = (import ./lib/astra-info.nix {
          # The function takes `pkgs`, not `nixpkgs` (lib/astra-info.nix:7), the
          # same signature lib/astra-boot.nix uses. profiles/base.nix passes
          # `inherit pkgs` correctly; only this call site was wrong.
          pkgs = legacy;
        }).package;
        astra-boot = import ./lib/astra-boot.nix {
          # No `inherit system` any more: the helper only ever needed pkgs
          # (lib/astra-boot.nix:8), and Nix errors on an unused named argument.
          pkgs = legacy;
        };
      };

      # `nix fmt` in the repo formats everything with alejandra.
      #
      # Per-system, not the flat `formatter = ...`: nix 2.35's `nix fmt` looks
      # for formatter.<system> and reports
      #   error: flake does not provide attribute 'formatter.x86_64-linux'
      # for the flat form. It also makes `nix flake check` able to check it.
      formatter.${system} = legacy.alejandra;

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