# astra

The abstract "Operating System." Everything. One "insecure" place.
<sub>(Yes its just NixOS with stuff)</sub>

## what

A NixOS flake that describes every machine I own: a laptop, a house, two
servers and some VMs for testing changes I do not want to try on real
hardware. One repo, one source of truth, zero excuses.

## why

Because reinstalling is a skill issue. And because "it worked yesterday" should
be something a machine can prove on its own, without me in the room.

## the shape of it

```
astra/
├── flake.nix           every host is one line in a directory listing
├── profiles/
│   ├── base.nix        the root: declares the astra.* options, sets up the account
│   ├── core.nix        dev toolchain, docker, tailnet, home-manager
│   └── desktop.nix     KDE Plasma 6, Ghostty, Zed
├── modules/
│   ├── astra/          cross-cutting: ssh, secrets, home automation
│   ├── boot/           ab.nix, snapshots.nix, bin/astra-boot
│   ├── desktop/        plasma.nix, greetd.nix
│   └── services/       caddy, searxng, dashdot, rustdesk
├── home/               home-manager: common.nix + desktop.nix
├── hosts/<machine>/configuration.nix
├── lib/                small things shared between the flake and the modules
└── DECISIONS.md        why things are the way they are, and what else was possible
```

A host imports one profile and a couple of modules. That is the whole contract:

| want to change | edit this |
|---|---|
| username, groups, hostname | `profiles/base.nix` + the host |
| what every machine has | `profiles/base.nix` — `astra.packages` |
| what a workstation adds | `profiles/core.nix` |
| what a desktop adds | `profiles/desktop.nix` |
| packages on one machine | the host — `astra.packages` |
| *removing* a package | the host — `astra.dropPackages = [ pkgs.thing ]` |
| a service | a new file in `modules/services/` |
| terminal, shell, prompt, git | `home/common.nix` |
| browser policy, Zed, Plasma look | `home/desktop.nix` |
| what counts as "this generation works" | `modules/boot/ab.nix` — `astra.ab.checks` |
| the secrets directory | `modules/astra/secrets.nix` |

## machines

| host | profile | notes |
|---|---|---|
| laptop | desktop | systemd-boot, A/B boot, recovery, snapshots off (ext4) |
| astra-home | core + home | Home Assistant, MQTT, no cloud, never reboots itself |
| server-full | core | caddy ingress, searxng, dashdot, rustdesk |
| server-core | base | ssh and nothing else |
| vm-nano | base | throwaway, for testing the flake itself |
| vm-mini | core | dev toolchain, no display |
| vm-full | desktop | KDE in a VM; a fair test of the desktop, not of rollback |

## quick start

```bash
# from a NixOS live environment or an existing install
bash <(curl -s https://raw.githubusercontent.com/Hxmbl/astra/main/install.sh) laptop
```

or by hand:

```bash
git clone https://github.com/Hxmbl/astra.git && cd astra
sudo nixos-rebuild switch --flake .#vm-nano
```

For the laptop, `install.sh` generates and imports `hardware-configuration.nix`
for you, then tells you to run `nixos-install`.

## log in

default user `user`, default password `nixos`. Run `passwd` and then delete
`astra.initialPassword` from the host.

## the A/B boot thing, in one paragraph

Every rebuild marks the generation it activated as **on trial**. It boots once.
Health checks (small shell scripts you can read, in `/etc/astra/health.d`) run
every twenty seconds; a generation that stays healthy for five minutes becomes
**stable** and the boot menu is rewritten to default to it. One that fails three
times in a row gets skipped and the machine reboots itself into the last
generation that worked. The boot menu lists the last five generations, labelled.

```bash
astra-info                # what stack is this machine running
sudo astra-boot status    # which generation is stable, which is on trial, health log
sudo astra-boot rollback  # go back to the last known-good generation
sudo astra-boot recover   # interactive recovery menu
sudo astra-boot health    # run every check once, change nothing
```

Three things make this different from `nixos-rebuild switch --rollback`:

- it happens by itself, without anybody logging in and typing
- it is based on health rather than on "was the last switch recent"
- the *previous good* generation is guaranteed to be in the boot menu, which is
  not true of the entries systemd-boot's generator writes (it only knows about
  generations that were in the build closure)

Recovery, from the login screen: press **Tab** in tuigreet for a root shell on
tty1, or pick `NixOS - Rescue system` from the boot menu. And if the boot goes
wrong enough that the initrd cannot mount `/`, the kernel asks for a maintenance
shell instead of going black.

Servers get the health checks but never the automatic reboot: a headless box that
bounces itself because DNS was slow is worse than one that logged it.

## secrets

The flake knows *where* a secret is, never what it is. Anything in a Nix
expression is world-readable in `/nix/store`, including "secrets".

```nix
astra.secrets.generate = [{ name = "searxng-secret"; key = "SEARXNG_SECRET"; }];
```

generates `/var/lib/astra/secrets/searxng-secret.env` on activation if it is not
there yet, and a service reads it with `environmentFiles`. For the rest, point
sops/agenix/a systemd credential at the same directory.

## astra home

`astra-home` is the same flake pointed at a house: a local Home Assistant, a
local MQTT broker, ESPHome for writing your own firmware, and no account
anywhere. It is reachable over the tailnet without opening a port. See
`modules/astra/home.nix`.

## formatting and checking

```bash
nix fmt                      # alejandra
python3 .ci/nix-balance.py   # bracket/string structure of every .nix file
bash .ci/astra-boot-test.sh  # the A/B state machine, against a fake store
python3 .ci/nix-conflicts.py # attributes claimed by more than one file
```

None of these need nix, and all of them run in a second or two. They exist
because this repo gets edited without being evaluated:

- `nix-balance.py` catches stray braces and unterminated strings. It is not a
  parser and knows nothing about module options.
- `astra-boot-test.sh` drives the real `astra-boot` through switch → boot →
  trial → promote and through failure → rollback, with a fake `/nix` store. It
  found five real bugs when it was written, including a `local` that shadowed
  the failure counter and meant the machine would never actually roll back.
- `nix-conflicts.py` is noisy and reports paths more than one file assigns. Most
  are lists and attrsets, which merge; the ones that matter are the ones where
  two modules write the same option with different values, which is a hard eval
  error.

## status

Everything here was written in one sitting and none of it has been evaluated,
let alone booted. See `MORNING.md` for exactly which parts to distrust first.