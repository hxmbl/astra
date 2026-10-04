# MORNING

Branch `overnight/2026-10-04`, branched from `main` at `5a678e7`. Eleven
commits, each self-contained enough to cherry-pick or revert on its own.

**Nothing was built, evaluated, or booted.** No `nix` on the machine this was
written on. Everything below was written by reading, plus three checkers I wrote
to catch the mistakes that reading does not catch. One of them found five real
bugs in the A/B logic; the others found three eval errors. That is the honest
calibration of how much to trust the rest.

Read `DECISIONS.md` alongside this. It has the forks and the alternatives, and
several of them are one-line reversions if you disagree.

---

## 1. What I actually built

### The profile hierarchy (`profiles/`)

`base.nix` now **declares the entire `astra.*` option surface**, once, at the
root: `user`, `userGroups`, `initialPassword`, `packages`, `dropPackages`,
`desktop.enable`, `timeZone`, `dns.servers`, `nixGcDays`, `ssh.*`, `secrets.*`.
`core.nix` and `desktop.nix` contribute to it rather than writing
`environment.systemPackages` themselves, so "why is this package on this
machine" is answerable from one file and removals happen in one place
(`astra.dropPackages`).

Also in base: the login account, `en_US.UTF-8` locale (with the
`LC_COLLATE` fix that silences the glibc 2.40 warning), Nix settings plus
automatic GC at 45 days, `nix-ld`, fstrim, journald capped at 14 days, logind
lid/power-key policy, Quad9-first DNS, and `/etc/astra/profile` so a machine can
always say what it is.

New host files are ~15 lines each. The account, its groups, its shell and its
home-manager entry all derive from `astra.user`.

**Fixed along the way:** `helix`, `htop` etc. were previously accumulated by
relying on list-merge order across five modules; there is now one accumulator.

### Hyprland → KDE

`profiles/desktop.nix` + `modules/desktop/plasma.nix` +
`modules/desktop/greetd.nix`. Plasma 6, Wayland, `hardware.graphics.enable`,
`xdg-desktop-portal` with the gtk and plasma backends, UPower, udisks2, libinput
tap-to-click, Noto + one JetBrains Mono Nerd Font (Ghostty's config asks for it
by name).

Kept: **greetd + tuigreet**, Ghostty, Zed, Tailscale.
Removed: `hyprland`, `hyprlock`, `rofi-wayland`, `hyprland.conf`,
`hyprlock.conf`. Plasma's own kscreenlocker replaces hyprlock and locks after
ten idle minutes.

**Vendor IDEs are now opt-in**: `astra.desktop.vendorTools` (default **false**)
holds VS Code, Cursor, Android Studio and JetBrains Toolbox. Zed plus Zen plus
Firefox is the default desktop. Zen and Firefox are both kept — Zen as the
source-build browser, nixpkgs' Firefox as the fallback for the day a site
breaks.

`home/` is split into `common.nix` (shell, git, starship, tmux, zoxide, direnv,
aliases) and `desktop.nix` (Ghostty, browser policies, Zed settings, Plasma
kcfg). Hand-written files where a hand-written file is safe: Zed ignores
unknown settings keys, so a mis-named HM option can never break the eval.

### A/B boot (`modules/boot/`)

This is the part I spent the most time on.

**`modules/boot/bin/astra-boot`** — the whole policy, one readable file, ~640
lines. Two slots over Nix generations: `stable` (newest generation proven
healthy) and `testing` (newest, unproven). Every switch writes
`pending=<gen>`; the next boot promotes it to `testing` and points the boot
default at it. Health checks are `sh` files in `/etc/astra/health.d`. Healthy
for `promoteAfter` seconds → promoted, menu rewritten. `failures` times running
→ marked `(failed)`, default set back to stable, reboot.

It also writes **its own** systemd-boot entries (`astra-<n>.conf`, titled
`Astra n=42 stable` / `(testing)` / `(failed)`), because the entries
systemd-boot's generator writes only cover generations that were in the build
closure — which is precisely not the previous good one when you are chasing a
bad build.

Commands: `status`, `generations`, `arm`, `health`, `guard`, `promote`,
`rollback`, `entries`, `recover` (interactive menu), `snapshot`, `snapshots`,
`restore-plan`. Everything the tool can do, you can do by hand with the same
command.

**`modules/boot/ab.nix`** — the wiring: `/etc/astra/boot.conf`, four default
health checks (store present, root filesystem rw, required units active, boot
menu writable), `astra-boot-arm` (before the display manager), a passive
`astra-health` pass, and an `astra-boot-guard` timer. Servers get
`reboot = false`.

**`modules/boot/snapshots.nix`** — optional, btrfs-only, off by default.
Snapshots `/` before each rebuild and pins the previous generation's closure
with `nix-store --add-root`, which is the line people forget: `/nix` is a
separate subvolume, so without a GC root the collector deletes the kernel the
snapshot needs to boot. Asserts rather than pretending on ext4.

**Recovery, three ways:** the boot menu itself; **Tab at the tuigreet login
screen** for a root shell on tty1 or a plain console login; and
`boot.rescueSystem` (NixOS's own) with `astra-boot restore-plan` printing the
steps. Plus `boot.initrd.systemd.ask-console` on the laptop, so a failed root
mount gets you a shell instead of a black screen.

### Astra Home

New host `hosts/astra-home` + `modules/astra/home.nix`: local Home Assistant
(`defaultConfig`, no cloud integration, set up through its own UI), a local MQTT
broker, ESPHome for writing your own firmware, Zigbee2MQTT off by default until a
coordinator exists, and the dashboard published over **Tailscale** instead of a
port forward. `astra.ab.reboot = false`.

### Smaller things

- `modules/astra/secrets.nix` — secrets directory outside the store, with
  on-demand generation of `KEY=value` files, consumed by services via
  `environmentFiles`.
- `modules/services/{caddy,dashdot,searxng,rustdesk}.nix` — one ingress per
  machine; container ports are loopback-only; caddy vhosts work with no DNS at
  all via `/etc/hosts` entries. **Fixed the broken searxng volume** (it pointed
  at a relative `./searxng` that did not exist).
- SSH hardened in one place; servers are key-only.
- `flake.nix` collapsed from seven copy-pasted blocks to a directory listing;
  new `packages.astra-info` / `packages.astra-boot`, a formatter and a devshell.
- `install.sh` knows about `astra-home` and prints what the machine you just
  built can do. `audit.txt` deleted — it was a stale snapshot including a
  `hosts/desktop/` directory that does not exist.
- `README.md` rewritten. `DECISIONS.md` written.

---

## 2. What is unverified, ranked by where I expect breakage

Nothing was evaluated. In rough order of how likely I think each is to stop you:

### Will very likely fail on first eval

1. **Home Assistant option names.** `services.home-assistant.config.defaultConfig`
   and `config.lufia` in `modules/astra/home.nix`. The `config` submodule has
   dozens of keys and I picked two. A wrong key is a hard eval error that names
   the option, so it should be a quick fix — but `astra-home` will not build
   until it is right.
2. **Mosquitto option names.** `services.mosquitto.{enable,port,dataDir,allowAnonymous,configFile}`
   in `modules/astra/home.nix`. Same shape of risk.
3. **`xdg-desktop-portal.extraPortals = [ "gtk" "plasma" ]`** in
   `modules/desktop/plasma.nix`. If the Plasma portal binary is not where the
   portal looks, screen sharing and the file dialog break. It does not stop the
   build; it stops the desktop being pleasant.
4. **`services.libinput.tap-to-click`** and **`hardware.graphics.enable32Bit`** —
   near-certain to exist, but I did not check the exact spelling.
5. **`services.desktopManager.plasma6.polkitAgent.enable`** and
   **`xserver.enable`**. I am confident about both; a wrong guess is a build
   error.

The pattern: every unverified item is an *option name I could not check without
nixpkgs in front of me*. Each one is a one-line deletion or rename, and each one
names itself in the error.

### Will probably need adjusting at boot

6. **The greetd session files.** `type = "tty"` is set in both `[command]` and
   `[default]` because I could not verify which section current greetd reads.
   And I had to add `XDG_DATA_DIRS=/etc/xdg:...` to the greetd unit myself,
   because nothing on NixOS puts `/etc/xdg` on that list — without it the
   recovery sessions are silently never found. **Press Tab at the login screen
   and check** before you rely on this.
7. **The kernel cmdline in generated boot entries.** astra records the cmdline
   the first time a generation boots and caches it in
   `/var/lib/astra/cmdline/<n>`; for a generation that has never booted, it
   falls back to `ASTRA_DEFAULT_CMDLINE` (derived from `boot.kernelParams`).
   The first-ever `astra-boot entries` therefore writes entries with the
   fallback cmdline. They work, but the real one only appears after that
   generation has booted once.
8. **`esp_mount` finds the ESP by partition-type GUID with `lsblk`.** If `lsblk`
   is not in a unit's `PATH` (I set `path =` on all three units, so it should
   be) it will fail and log "no EFI system partition found" rather than
   silently doing the wrong thing.
9. **Container networking on server-full.** searxng and its valkey use
   `--network host` precisely because I could not verify that
   `virtualisation.oci-containers` resolves `dependsOn` as a network
   relationship. If host networking fights you, a compose file is the fix.
10. **`SEARXNG_BIND_ADDRESS` / `SEARXNG_PORT`.** I believe upstream honours
    these; if not, searxng binds 0.0.0.0 on the host and the loopback-only claim
    in DECISIONS.md is false.
11. **The laptop's `hardware-configuration.nix` flow.** `install.sh` still does
    the two `sed`s on `hosts/laptop/configuration.nix`. I changed that file's
    shape (the placeholder is still there, the import comment is still there),
    but the sed range `/# PLACEHOLDER/,/^[[:space:]]*};/d` is now the kind of
    thing that silently eats the wrong lines. **Check the diff after running it
    once.** A `git diff` on the laptop host after `install.sh` is the test.
12. **Timezone.** `astra.timeZone` defaults to UTC and I did not guess yours. The
    laptop will show UTC until you set it.
13. **Home Manager's `home.username`.** I used `lib.mkDefault` so it cannot
    conflict with home-manager's own derivation. If home-manager does *not* set
    it, the eval fails with "`home.username` has no value" — one line to fix.

### Verified, or as close as I could get without a machine

- **The A/B state machine is tested.** `.ci/astra-boot-test.sh` fakes the Nix
  store, `/run/current-system`, the ESP, `bootctl` and `systemctl`, and drives
  the real script through switch → boot → trial → promote and through failure →
  rollback, plus the GC'd-kernel and manual-rollback paths. 27 assertions, all
  passing. It found five real bugs while I wrote it (see below).
- **All `.nix` files are bracket- and string-balanced**, checked by a script I
  validated against the pre-change files.
- **Every shell script parses** (`bash -n`), including `install.sh`.
- The three eval errors the conflict finder caught are fixed:
  `astra.desktop` declared as a bool while `astra.desktop.vendorTools` was
  declared under it; `services.logind.extraConfig` set by two modules; and
  `astra.desktop.enable` set by both `core.nix` and `desktop.nix`.

### The five bugs the state-machine test found

Worth knowing because they are the shape of thing that does not show up until
3am:

1. `cmd_guard` declared `local failures`, shadowing the count that `state_load`
   had just put in a variable of that name. The counter reset every run, so the
   failure threshold was **never reached** and a machine would never have rolled
   back — the exact bug the whole feature exists to prevent.
2. `state_set` wrote the state file but left the in-memory variables stale, so
   a promoted generation was labelled with the *previous* stable one's title and
   the boot default was set to a string that did not exist in the menu.
3. With nothing promoted yet, rollback fell back to "the newest generation" —
   which on a first boot is the one that just failed. It now excludes the
   current and already-failed generations.
4. A manual rollback from the stable generation searched for "a different
   generation" instead of an older one, so a machine pinned to an old generation
   rolled *forward*.
5. `set_default_entry` trusted `bootctl` to fail when the target's kernel had
   been garbage collected, and its fallback did not become stable — so the
   machine would keep trying to roll back into a dead generation.

---

## 3. Decisions, and the alternatives

Full detail in `DECISIONS.md`. The ones most likely to get an argument:

- **A/B is a policy over generations, not a second copy of the OS.** No second
  `/nix`, no partition migration, works on ext4. Passed on snapper-boot (needs
  btrfs, brings a daemon and a second thing that can break your boot) and true
  A/B root slots (more robust, much bigger change).
- **The boot default is the stable generation**, and a new generation is booted
  once under test. This means a machine can reboot itself once after a rebuild.
  `astra.ab.reboot = false` turns that into a log line instead.
- **We write our own boot entries.** Necessary for the rollback target to be in
  the menu at all. Cost: two sets of entries, and NixOS's own are still there as
  an escape hatch.
- **Health checks are `sh` files, not Nix.** Cost: you cannot drop one in by
  hand and have it survive the next rebuild.
- **Servers never self-reboot.** A headless box that bounces itself because
  DNS was slow is worse than one that logged it.
- **Host networking for the searxng containers.** A real reduction in isolation,
  chosen because I could not verify the alternative.
- **Home Assistant is configured through its own UI**, not from Nix. Reversible
  in a few lines, but it is a one-way door.
- **sops-nix/agenix are not in the tree** — adding a flake input needs
  `nix flake lock`, which needs network access. Every new tool therefore comes
  from nixpkgs. The secrets module is the seam to replace when you can run
  `nix flake lock`.
- **Vendor IDEs off by default**, Quad9 first for DNS, Tailscale client-only,
  `git` deliberately has no `safe.directory = "*"`.

---

## 4. Started but not finished

- **Btrfs snapshots for the laptop.** Written, off by default, and the laptop is
  still ext4 so the assertion refuses to enable it. Converting the laptop is a
  separate commit with its own rollback plan.
- **`bootctl` boot-counting.** A kernel that panics before userspace reboots into
  the same broken generation, because nothing counts attempts. `boot.panic = 10`
  (the default here) plus the boot menu is the mitigation; `haltOnPanic = true`
  gives you a hang-instead-of-loop. Doing it properly means writing an EFI
  variable from the initrd before `/` is mounted, which I judged too much
  machinery for the case the boot menu already covers.
- **Backups.** `restic` is on server-full; there is no job, schedule or target.
  `/home` is the only thing here that would genuinely hurt to lose and nothing
  touches it. This is a gap, not a decision.
- **Battery charge thresholds.** Plasma/UPower will not stop charging at 80% on
  their own; needs TLP (fights the nixpkgs power stack) or a vendor WMI call.
  Machine-specific, so it belongs in the laptop host once you tell me the model.
- **KDE keybindings.** I did not write `kglobalshortcutrc` because I was not
  confident about the tab-separated format. Plasma's defaults cover brightness
  and volume through PowerDevil, so the only real gap is "lock screen" on a
  shortcut.
- **Formatting.** alejandra is the formatter and `nix fmt` works, but I did not
  reformat files I did not touch, so the repo is a mix.
- **CI.** `check.yml` stays disabled. I added `lint.yml`, which runs the three
  nix-free checks — that is new, and one `rm` if you would rather have none.

## 5. Things I was unsure about, stated precisely

- **`services.home-assistant` and `services.mosquitto` option names.** The two
  places I am least confident, and both are on the new host only.
- **The greetd session-file dialect**, and whether `XDG_DATA_DIRS` is really the
  missing piece. I am confident about the diagnosis, less about the fix.
- **Whether `virtualisation.oci-containers` gives containers DNS names for each
  other.** I sidestepped it rather than find out, which is why host networking
  is there.
- **`xdg-desktop-portal.extraPortals = [ "gtk" "plasma" ]`** — whether the Plasma
  portal binary ships where the portal expects it.
- **Plasma 6's `polkitAgent` / `xserver` sub-options.** Confident, unverified.
- **Everything about how KDE actually looks.** I removed every hand-tuned
  Hyprland setting and replaced it with four small kcfg files and a font. If
  the result is ugly, that is the file to edit: `home/desktop.nix`.
- **`services.nix-ld`** on a machine that does not need it is harmless, but I
  did not check it against Plasma for interference. It is one line.

## 6. Suggested order for the morning

1. `nix flake check` / `nix eval .#nixosConfigurations.vm-nano.config.system.build.toplevel.drvPath`
   — cheapest host, catches the option-name errors in the base layer.
2. Then `vm-full` and `laptop` — the desktop options.
3. Then `server-full`, `server-core`, `astra-home` — the service modules, where
   the HA and mosquitto guesses live.
4. `bash .ci/astra-boot-test.sh` is already green; keep it that way. If you
   change the boot logic, run it before you run it on the laptop.