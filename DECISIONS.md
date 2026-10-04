# DECISIONS

Written 2026-10-05, in one sitting, without evaluating or booting anything.
Each entry is a fork I actually had to choose at, what I picked, and what I
passed on. Every one of these is cheap to overrule — they are listed roughly in
the order I would overrule them myself.

---

## 1. The profile hierarchy gets an option surface

**Chosen:** `profiles/base.nix` declares the whole `astra.*` option set, once, at
the root. Profiles and hosts then *contribute* to it instead of writing
`environment.systemPackages` directly.

```nix
astra.packages      # listOf package — concatenates down the hierarchy
astra.dropPackages  # listOf package — concatenates, subtracted at the end
environment.systemPackages = lib.subtractLists cfg.dropPackages cfg.packages
```

**Passed on:** keeping the old shape, where base/core/desktop each assign
`environment.systemPackages` and rely on Nix's list-merge to concatenate. It
works today; it is just invisible. You cannot answer "why is `rofi` on this
machine" without reading three files and knowing that order does not matter.

**Why:** one place to look, and one supported way to remove something
(`astra.dropPackages`) instead of `lib.mkForce` gymnastics or remembering which
module set the option last. A profile uses a plain assignment, a host that must
beat a profile uses `mkForce`, and the difference is legible.

**Cost:** a real one. `mkForce` on a non-mergeable option produces an error that
does not name the file to look at, and there are now two names (`astra.packages`
and `environment.systemPackages`) instead of one. If this annoys you, reverting
is a mechanical change to `base.nix` only — nothing else references the
attribute except the one line that installs it.

---

## 2. A/B is a *policy* over generations, not a second copy of the OS

**Chosen:** two named slots — `stable` (newest generation proven healthy) and
`testing` (newest generation, unproven) — living in `/var/lib/astra/state`, plus
a health check that decides between them. NixOS generations remain the only
place software versions live. There is no second root filesystem, no second
`/nix`, no partition layout change.

**Passed on:**

- **snapper-boot / snapper-rollback.** The standard Linux answer. It is
  well-trodden and it handles `/etc` and `/home`. It also brings a daemon, a
  timed snapshot schedule, a paccept, and a second thing that can break your
  boot. It wants btrfs with a specific subvolume layout, which the laptop does
  not have (ext4). Adopting it means either converting the laptop or having two
  different recovery stories.
- **True A/B root slots** (`/dev/nvme0n1p2` ↔ `p3`, one boot entry each).
  This is what Android and systemd-os do. It is genuinely more robust — you can
  format one slot while running the other — and it is also a partition-migration
  project, an installer rewrite, and a second 30 GB to keep in sync. Wrong size
  of change for a week I am not watching the machine.
- **Just `nixos-rebuild switch --rollback`,** wrapped in an alias. Free, and it
  is what `astra-boot rollback` ends up doing when you invoke it by hand. It
  does not help when you are *not* there, which is the entire premise.

**Why:** the thing generations genuinely cannot do is *tell you that the thing
you just booted is broken and switch back by itself*. That is a policy problem,
and policy is a script. Everything else generations already do.

**The interesting constraint I found:** systemd-boot's generator only writes
entries for generations that were in the build closure — which is precisely
*not* the previous good one when you are chasing a bad build. So the rollback
target is frequently missing from the menu. `astra-boot` writes its own entries
(`astra-<n>.conf`, titles like `Astra n=42 stable`) pointing at store paths it
resolves at runtime. See DECISION 4.

---

## 3. The default boot entry is the *stable* generation

**Chosen:** after every switch, the new generation becomes `testing` and is
booted once (we point the default at it so a rebuild behaves the way you
expect). If it survives `promoteAfter` seconds of health, it is promoted to
`stable` and stays the default. If it fails `failures` times running, it is
marked `(failed)` in the menu and the default is set back to `stable`, then the
machine reboots.

**Passed on:** keeping `testing` as the default until someone promotes it by
hand. That is the "be very careful" option and it is the safer one — but it
means `nixos-rebuild switch` followed by a reboot does not boot what you just
built, which is a surprise people have strong opinions about, and it means the
new generation is *never* exercised unless you remember.

**Why:** this is the Mac behaviour in the shape I think the user asked for. You
upgrade, it works, you never think about it. If it does not work, you did not
have to be there: one reboot, back to a working machine, and the log says why.
Default timeout is five minutes, which is long enough to catch "the display
manager never came up" and short enough that a promote does not need babysitting.

**Cost:** on the very first boot after a switch there is a window where the
machine reboots by itself. If that is unacceptable, set `astra.ab.reboot =
false` and it becomes a recommendation in the log instead of an action.

---

## 4. We write our own boot entries

**Chosen:** `astra-boot entries` enumerates `/nix/var/nix/profiles/system-*-link`
and writes one `loader/entries/astra-<n>.conf` per generation, then
`bootctl set-default` on the stable one. Kernel cmdlines are *recorded* per
generation the first time that generation boots, and cached, because a
generation from three reboots ago never had an entry to copy one from.

**Passed on:** relying on the `nixos-*.conf` entries NixOS generates. Zero code.
Fails exactly when you need it — the generator's list is a build-time closure,
so the previous good generation is often not there, and it has no concept of
"stable" versus "testing".

**Also passed on:** `bootctl list --json | jq` and rewriting one of NixOS's own
entries. Saves two filenames, loses the ability to have both an `astra-` and an
unmodified `nixos-` view of the menu, which is a useful escape hatch if astra's
logic ever guesses wrong: pick the NixOS entry.

**Cost:** two sets of entries in the menu, and if the two disagree (they will
disagree right after a `nixos-rebuild` until the next `astra-boot entries` runs)
the default may point at one of them. The activation hook keeps them in step on
every switch.

---

## 5. Health checks are shell files, not Nix

**Chosen:** `astra.ab.checks` is a list of `{ name, script }`, rendered to
`/etc/astra/health.d/*.check`, run with `sh`, exit 0 means healthy, printed text
becomes the log line. Adding a check to a host is appending two strings.

**Passed on:** checking health from Nix — `systemd.services.<x>.wantedBy` lists,
`assertions`, or one big `ExecStart` of Nix-built shell. All of them put the
*policy* back into the store, where you need a rebuild to change it, and all of
them make "is this machine healthy right now" a question about the running
system that a script can answer.

**Cost:** the checks are `sh` files generated by Nix, so you can read them but
you cannot drop one in by hand and have it survive the next rebuild — it is not
`environment.etc`-style symlinked, it is a literal file. A check that should
survive belongs in this repo; a check you are debugging goes in `/tmp` and you
run `astra-boot health` by hand.

---

## 6. Servers get the checks but never the automatic reboot

**Chosen:** `astra.ab.reboot = false` on `server-core`, `server-full` and
`astra-home`. `systemd-boot` hosts still get the full menu treatment.

**Why:** a headless box that reboots itself because a health check failed has
turned a five-minute problem into an outage, and the person who could fix it is
asleep. A laptop in your hands can roll back without you noticing; a server in
an attic cannot. Both get the log.

---

## 7. A kernel panic reboots after ten seconds

**Chosen:** `boot.kernel.panic = 10`, `boot.panicOnOops = false`.
`astra.ab.haltOnPanic = true` flips it to `panic = 0`, which hangs on the panic
screen so you can pick another entry from the boot menu.

**Why this is uncomfortable:** a panicking kernel on a laptop with the default
loops. You sit at the boot menu, press escape, pick `Astra n=<previous>`, and it
is fine — but it needs a keypress. Nothing here counts boot attempts, because
counting them correctly means writing an EFI variable from the initrd before
the root filesystem is mounted, which is a lot of machinery for a case that the
boot menu already handles. `haltOnPanic` is the answer for anyone who wants the
no-loop behaviour.

---

## 8. Snapshots are opt-in, btrfs-only, and hand-rolled

**Chosen:** `astra.ab.snapshot.enable` (default **off**). When on: `btrfs
subvolume snapshot` of `/` before every rebuild, ten kept, and — the part
everyone forgets — an `nix-store --add-root` GC root pinning the *previous*
generation's closure, because `/nix` is a separate subvolume and is not in the
snapshot. Without it the garbage collector is free to delete the kernel the
snapshot needs in order to boot.

**Passed on:** snapper (see DECISION 2) and `timeshift`. Both are more complete
than this. This is sixty lines of shell you can read, it has no daemon, and its
failure mode is a `mount` command from the rescue system.

**The laptop stays ext4**, so snapshots are off there and the assertion in
`snapshots.nix` will refuse to enable them. Converting the laptop to btrfs is a
separate, deliberate piece of work — do it as its own commit, with its own
rollback plan, which is somewhat ironic.

---

## 9. Recovery is three separate doors, not one

**Chosen, all three:**

1. The **boot menu** lists the last five generations, labelled, stable
   preselected. This is the door you use most and it needs no thought.
2. **tuigreet → Tab** offers a root shell on tty1 (`astra-recover`) and a plain
   console login as your user (`astra-shell`). Both work with no display, no
   Plasma, and no `/nix` in good shape.
3. **`NixOS - Rescue system`** from systemd-boot (`boot.rescueSystem.enable`),
   which is a systemd in an initrd with the store but not your root filesystem.
   `astra-boot restore-plan <snap>` prints exactly what to do in there.

**Passed on:** SDDM's recovery entry (we are not using SDDM), and a
"boot into the previous generation" entry that grub could implement and
systemd-boot cannot.

**Uncertainty I want to flag:** I wrote the greetd session files with `type =
"tty"` in *both* the `[command]` and `[default]` sections, because I could not
verify where current greetd expects it. Unknown keys are ignored by greetd's
config parser, so setting both should be harmless, but **press Tab at the login
screen and check** before relying on it.

---

## 10. One ingress per machine; container ports go away

**Chosen:** `modules/services/caddy.nix` owns ports 80 and 443 and nothing else
listens for HTTP. Every service registers `{ name, upstream }` and gets
`http://<name>.<domain>`, plus an `/etc/hosts` entry so it works with no DNS at
all. Containers bind `127.0.0.1:` or are invisible.

**What this changed on server-full:** `searxng` on 8080, `dashdot` on 3001 and
`valkey` on 6379 were in `networking.firewall.allowedTCPPorts`, i.e. open to the
LAN with no authentication. They are now loopback-only behind Caddy.
**RustDesk is the exception** and keeps 21115–21118 open, because it is a raw
relay protocol, not HTTP.

**Risk to weigh:** if you were reaching searxng on `:8080` from a phone or a
bookmark, that URL is dead now and it is `http://searx.astra.local`. The
`/etc/hosts` entries are on the *server*, not on whatever was using those URLs —
so something on your laptop may need a matching hosts entry or a bookmark change.

---

## 11. searxng's containers use host networking

**Chosen:** `--network host` for searxng and its valkey, talking over
`127.0.0.1`, with `SEARXNG_BIND_ADDRESS=127.0.0.1`.

**Passed on:** a private docker network with per-container DNS aliases, which is
the textbook answer and the one a compose file makes trivial. Expressing it
through `virtualisation.oci-containers` needs `dependsOn` to be understood as a
network relationship, which I am not confident enough about unverified — and the
previous config had exactly that pattern and a broken volume mount, so it was
never working.

**Cost:** the containers share the host network namespace, so they can reach host
ports. Both bind loopback only, so it is not a meaningful exposure; but it is a
real reduction in isolation and it is a compromise, not a principle.

**Also fixed:** the old searxng volume was `[ "./searxng:/etc/searxng:rw" ]` — a
relative path, a directory that did not exist, and no `settings.yml`. It is now
`/var/lib/searxng`, created by tmpfiles, so editing it is `sudoedit`.

---

## 12. Secrets live outside the store, and sops-nix is not in the tree

**Chosen:** `modules/astra/secrets.nix` — a root-only directory
(`/var/lib/astra/secrets`), an activation script that generates missing
`<name>.env` files with `openssl rand -hex`, and services that read them with
`environmentFiles`.

**Passed on:** `sops-nix` or `agenix`. Both are better answers and I could not
use either: **adding a flake input means updating `flake.lock`, which needs
network access and a `nix flake lock` run, and I could do neither.** So this is
the best available seam, not the best answer. The directory is chosen so that
when you add sops-nix later, you point it at the same path and delete one
module.

**Consequence worth internalising:** `astra.secrets.generate` values end up
*referenced* from the Nix store but the *values* live only on disk. If you lose
the disk, you generate new ones, and every client that had the old value needs
reconfiguring. That is the correct default for a service-to-service token and
the wrong one for anything that loses data when rotated (searxng's secret is
borderline).

---

## 13. Astra Home configures Home Assistant through its own UI

**Chosen:** `services.home-assistant.config.defaultConfig` and nothing else. The
first visit to the dashboard is the setup. Nix provides the machine, the broker
and the tailnet route; the app configures itself.

**Passed on:** generating HA's `configuration.yaml`, `automations.yaml`,
`secrets.yaml` and a pile of `!include` from Nix. It is what "everything in one
repo" argues for, and it is a daily fight: HA rewrites its own config on some
upgrades, the UI silently drops YAML it does not understand, and every rebuild
clobbers anything done by hand. The option exists if you disagree — add lines to
`config` — but it is a one-way door.

**Dropped deliberately:** `config.wakeOnLan`, because I was not confident about
the option's exact name in nixpkgs' HA submodule and a wrong key breaks the
whole desktop eval. `defaultConfig` and `lufia` I am confident about.

**Also dropped:** local DNS-level adblocking (pihole/blocky), Frigate, Node-RED.
All three are reasonable and all three are "you now maintain another service".
Groundwork means the house has a controller and a broker, not that it has
opinions about your lightbulbs.

---

## 14. Vendor IDEs are opt-in

**Chosen:** `astra.desktop.vendorTools` (default **false**). VS Code, Cursor,
Android Studio and JetBrains Toolbox move out of the default desktop. The editor
is Zed.

**Why not just delete them:** they are four lines away and you may genuinely want
them on the laptop. The flag says "I know what this costs" instead of "we
removed your tools".

**Zen and Firefox are both kept.** Zen is the default browser because it is
source-available and buildable; `firefox` from nixpkgs is the boring fallback
for the day a site breaks in Zen.

---

## 15. Browser privacy policies, and where they actually live

**Chosen:** one `policies.json` at `~/.config/astra/browser-policies.json`, and a
home-manager activation step that symlinks it into every browser profile
directory it finds. Telemetry, Firefox Studies, accounts, Pocket, search
suggestions, tracking protection, HTTPS-only, DoH and Firefox Sync all off.

**The trap:** my first version wrote `~/.config/zen/policies.json`, which looks
right and is read by nothing. Firefox-derived browsers read `policies.json`
*inside a profile directory*, whose name is random
(`~/.zen/x7f2k.default-release`). The symlink step is the fix.

**Also dropped:** `programs.firefox.policies`. Home Manager has such an option
and I believe its fields are `{ enable, value }`, but I could not check, and one
wrong field name breaks the eval for every desktop host.

---

## 16. DNS, Tailscale, and the other small privacy calls

- **Quad9 first, then Cloudflare.** Both resolve without building a profile of
  you; Google's is gone. `astra.dns.servers` if you disagree. A self-hosted
  resolver is the real answer and is a separate project.
- **Tailscale is `useRoutingFeatures = "client"`** — no exit node, no subnet
  router, no DNS takeover, and `--accept-dns=false`. A host that needs to route
  for the tailnet has to say so out loud.
- **`services.nix-ld`** is on, so unpatched binaries (vendor Electron apps
  mostly) find their libraries. It is the difference between "it installed" and
  "it launched".
- **journald keeps 14 days**, which is enough to debug last week's boot failure.
- **`git` has no `safe.directory = "*"`.** It disables a real protection. The
  README tells you to add it for one path if you want it.
- **No new flake inputs.** `nixpkgs`, `home-manager`, `zen-browser` and `cursor`
  are what we have, because `flake.lock` cannot be updated from here. Every new
  tool in this repo comes from nixpkgs.

---

## 17. Things I decided not to build

- **Change detection for data.** `/home` is the only thing that actually hurts to
  lose and nothing here touches it. `restic` is installed on server-full; there
  is no backup *job* yet, only the package. That is a gap, not a decision.
- **Btrfs for the laptop.** See DECISION 8.
- **Battery charge thresholds.** Plasma and UPower will not stop charging at 80%
  on their own. That needs TLP (which fights the nixpkgs power stack) or a
  vendor-specific WMI call, and it is machine-specific enough that it belongs in
  the laptop host when you tell me the model.
- **A second, `astra-*`-independent recovery ISO.** NixOS's own rescue system is
  good enough and rebuilding it from this repo would be a project.
- **Formatting everything with alejandra.** It is the formatter now and
  `nix fmt` works; I did not reformat the files I did not touch, so the repo is
  a mix until someone runs it.