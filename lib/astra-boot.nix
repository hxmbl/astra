# lib/astra-boot.nix — expose the boot/recovery tool as a flake package.
#
# Why bother: the moment you most want `astra-boot` is a machine that will not
# finish booting, or a rescue shell, where the version installed in the system
# profile is the one that might be broken. Being able to run it straight from the
# flake (`nix run github:hxmbl/astra#astra-boot status`) means the tooling can
# be fixed independently of the machine it is diagnosing.
{ pkgs }:
let
  path = ../modules/boot/bin/astra-boot;
in
pkgs.writeShellScriptBin "astra-boot" (builtins.readFile path)