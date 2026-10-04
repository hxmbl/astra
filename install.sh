#!/usr/bin/env bash
# astra installer. Clones the repo, optionally generates a hardware config,
# then rebuilds the host you picked.
set -euo pipefail

# --- colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${CYAN}::${NC} $*"; }
ok() { echo -e "${GREEN}::${NC} $*"; }
warn() { echo -e "${YELLOW}::${NC} $*"; }
err() { echo -e "${RED}::${NC} $*" >&2; }

# --- hosts (parallel arrays, bash 3 compat) ---
# Keep this in sync with the `hosts` attrset in flake.nix. A host that is in
# one and not the other is a bad morning.
HOST_NAMES=(
  laptop
  vm-nano
  vm-mini
  vm-full
  server-full
  server-core
  astra-home
)
HOST_DESCS=(
  "laptop (desktop + A/B boot)"
  "minimal VM (base profile)"
  "medium VM (core profile)"
  "full VM (desktop profile)"
  "server with containers + caddy"
  "minimal server"
  "home automation controller"
)

REPO="https://github.com/Hxmbl/astra.git"
DEST="${ASTRA_DEST:-$HOME/astra}"

# --- helpers ---
get_desc() {
  local name="$1" i
  for i in "${!HOST_NAMES[@]}"; do
    if [ "${HOST_NAMES[$i]}" = "$name" ]; then
      echo "${HOST_DESCS[$i]}"
      return
    fi
  done
}

is_valid_host() {
  local name="$1" h
  for h in "${HOST_NAMES[@]}"; do
    [ "$h" = "$name" ] && return 0
  done
  return 1
}

# --- menu ---
pick_host() {
  echo -e "\n${BOLD}astra${NC} — which host?\n"
  local i
  for i in "${!HOST_NAMES[@]}"; do
    echo -e "  ${CYAN}$((i + 1))${NC} ${BOLD}${HOST_NAMES[$i]}${NC} — ${HOST_DESCS[$i]}"
  done
  echo ""
  read -rp "pick [1-${#HOST_NAMES[@]}]: " choice
  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#HOST_NAMES[@]}" ]; then
    HOST="${HOST_NAMES[$((choice - 1))]}"
  else
    err "invalid choice"
    exit 1
  fi
}

show_hosts() {
  echo "available hosts:"
  local i
  for i in "${!HOST_NAMES[@]}"; do
    printf '  %-14s %s\n' "${HOST_NAMES[$i]}" "${HOST_DESCS[$i]}"
  done
}

# --- arg parsing ---
HOST="${1:-}"

if [ -z "$HOST" ]; then
  pick_host
elif [ "$HOST" = "--help" ] || [ "$HOST" = "-h" ]; then
  echo "usage: install.sh [hostname]"
  echo ""
  show_hosts
  exit 0
fi

if ! is_valid_host "$HOST"; then
  err "unknown host: $HOST"
  echo ""
  show_hosts
  exit 1
fi

# --- checks ---
if ! command -v nix &>/dev/null; then
  err "nix not found. install it first:"
  echo "  sh <(curl -L https://nixos.org/nix/install) --daemon"
  exit 1
fi

if ! command -v git &>/dev/null; then
  err "git not found. install it first:"
  echo "  nix-env -iA nixpkgs.git"
  exit 1
fi

# --- clone ---
if [ ! -d "$DEST" ]; then
  info "cloning astra..."
  git clone "$REPO" "$DEST"
else
  info "astra already cloned at $DEST"
  cd "$DEST"
  info "pulling latest..."
  git pull --ff-only || warn "pull failed — using existing version"
fi

cd "$DEST"

# --- confirm ---
DESC="$(get_desc "$HOST")"
echo ""
echo -e "  host:    ${BOLD}$HOST${NC}"
echo -e "  profile: ${BOLD}$DESC${NC}"
echo -e "  repo:    ${DEST}"
echo ""
read -rp "  proceed? [Y/n] " confirm
if [[ "${confirm,,}" == "n" ]] || [[ "${confirm,,}" == "no" ]]; then
  info "aborted."
  exit 0
fi

# --- hardware config ---
# Only the laptop has a placeholder filesystem entry; the others either boot
# from a disk image or get edited by hand. Regenerating hardware-configuration.nix
# is the one part of this script that touches your repo, so it says so.
if [ "$HOST" = "laptop" ]; then
  info "generating hardware config from this machine..."
  nixos-generate-config --show-hardware-config >hosts/laptop/hardware-configuration.nix

  cfg=hosts/laptop/configuration.nix
  sed -i.bak 's|# ./hardware-configuration.nix|./hardware-configuration.nix|' "$cfg"
  # Drop the placeholder root filesystem; hardware-configuration.nix owns it now.
  sed -i.bak '/# PLACEHOLDER/,/^[[:space:]]*};/d' "$cfg"
  rm -f "$cfg.bak"

  ok "hardware config generated and imported"
  warn "remember to install the bootloader for the first boot:"
  echo "  sudo nixos-install --flake .#laptop"
fi

# --- rebuild ---
info "rebuilding ${HOST}..."
sudo nixos-rebuild switch --flake ".#$HOST"

# --- what you just built, and where to look at it ---
echo ""
ok "astra is live. welcome home."
echo ""
echo "  what you just got:"
echo "    astra-info              what stack this machine is running"
case "$HOST" in
  laptop)
    echo "    sudo astra-boot status  which generation is stable, which is on trial"
    echo "    sudo astra-boot rollback"
    echo "                          go back to the last known-good generation"
    echo "    sudo astra-boot recover interactive recovery menu"
    ;;
  server-* | astra-home)
    echo "    sudo astra-boot status  health log; this box never reboots itself"
    echo "    journalctl -u astra-health -f"
    ;;
esac
echo ""
echo "  log in: ${BOLD}user${NC} / ${BOLD}nixos${NC} (change it with 'passwd')"