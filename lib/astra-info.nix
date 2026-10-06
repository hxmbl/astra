# lib/astra-info.nix — the one place the `astra-info` script is defined.
#
# It is built twice on purpose: once into the NixOS system (so `astra-info`
# works on every machine) and once as a flake package (so
# `nix run github:hxmbl/astra#astra-info` works on a machine that has not
# installed astra yet, which is exactly the machine you want it on).
{pkgs}: let
  script = pkgs.writeShellScript "astra-info" ''
    set -uo pipefail

    # shellcheck disable=SC1091
    if [ -r /etc/astra/profile ]; then . /etc/astra/profile; fi

    host="${host:-unknown}"
    profiles="${profiles:-unknown}"
    user="${user:-unknown}"
    version="${astraVersion:-unknown}"
    desktop="${desktop:-false}"

    echo "astra $version"
    echo "  host      $host"
    echo "  profiles  $profiles"
    echo "  user      $user"
    echo "  desktop   $desktop"
    echo "  nixpkgs   ${nixpkgs:-?} (${nixpkgsRev:-?})"
    echo "  system    $(uname -srm)"
    echo

    if command -v astra-boot >/dev/null 2>&1 && [ "$(id -u)" = 0 ]; then
      astra-boot status || true
    else
      echo "boot: run 'sudo astra-boot status' for generation and health state"
    fi
  '';
in {
  inherit script;
  package = pkgs.writeShellScriptBin "astra-info" script;
}
