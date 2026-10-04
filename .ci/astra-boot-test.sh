#!/usr/bin/env bash
# Exercise the astra-boot state machine against a fake Nix store.
#
# This is the one part of astra where a logic bug is silent until the moment it
# matters (a machine rebooting itself into the wrong thing), so it is worth
# being able to check in two seconds on any machine, without nix and without
# root.
#
# It fakes: /nix/var/nix/profiles, /run/current-system, the ESP, bootctl,
# systemctl, mountpoint. It does not fake: the logic.
#
# Usage: .ci/astra-boot-test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
TOOL="$HERE/../modules/boot/bin/astra-boot"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok() {
  pass=$((pass + 1))
  echo "  ok    $1"
}
no() {
  fail=$((fail + 1))
  echo "  FAIL  $1"
  [ -n "${2:-}" ] && echo "        $2"
}
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected [$3], got [$2]"; fi
}
assert_contains() {
  case "$2" in
    *"$3"*) ok "$1" ;;
    *) no "$1" "[$2] does not contain [$3]" ;;
  esac
}

# ---------------------------------------------------------------- fake world --
PROFILES=$TMP/nix/var/nix/profiles
STATE=$TMP/var/lib/astra
ETC=$TMP/etc/astra
ESP=$TMP/boot
RUN=$TMP/run
STUB=$TMP/stub
mkdir -p "$PROFILES" "$STATE" "$ETC/health.d" "$ESP/loader/entries" "$RUN" "$STUB"

# generations 1..5, each a directory with kernel and initrd
for n in 1 2 3 4 5; do
  mkdir -p "$PROFILES/system-$n-link/kernel" "$PROFILES/system-$n-link/initrd"
done

# Pretend generation 5 is what booted.
ln -sfn "$PROFILES/system-5-link" "$RUN/current-system"
printf 'fake cmdline quiet splash\n' >"$STATE/cmdline-5"

cat >"$ETC/boot.conf" <<EOF
ASTRA_KEEP=5
ASTRA_INTERVAL=1
ASTRA_FAILURES=2
ASTRA_PROMOTE_AFTER=0
ASTRA_REBOOT=1
ASTRA_ESP=$ESP
ASTRA_DEFAULT_CMDLINE=(fake quiet)
EOF

# a passing and a switchable failing check
cat >"$ETC/health.d/10-store.check" <<'EOF'
echo "store ok"
EOF
cat >"$ETC/health.d/20-flaky.check" <<'EOF'
[ -e "$FLAKY_MARKER" ] && { echo "the thing that is broken is broken"; exit 1; }
echo "flaky ok"
EOF

# --- stubs. These are the only things the tool shells out to.
cat >"$STUB/bootctl" <<EOF
#!/usr/bin/env bash
echo "bootctl \$*" >> "$TMP/bootctl.log"
exit 0
EOF
cat >"$STUB/timeout" <<'EOF'
#!/usr/bin/env bash
# Stands in for coreutils timeout: drop the duration, run the command.
shift
exec "$@"
EOF
cat >"$STUB/mountpoint" <<'EOF'
#!/usr/bin/env bash
[ "$2" = "-q" ] && exit 0
exit 0
EOF
cat >"$STUB/systemctl" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  is-active) exit "${STUB_UNIT_STATE:-0}" ;;
  reboot) echo "reboot" >>"$ASTRA_TEST_REBOOT_LOG" ;;
esac
exit 0
EOF
chmod +x "$STUB"/*

export PATH="$STUB:$PATH"
export ASTRA_PROFILES="$PROFILES"
export ASTRA_STATE_DIR="$STATE"
export ASTRA_LIB_DIR="$ETC"
export ASTRA_CURRENT_SYSTEM="$RUN/current-system"
export FLAKY_MARKER="$TMP/nope"
# Lets the root-only commands (promote, rollback, entries) run as a normal user.
export ASTRA_TESTING=1
# Read by the systemctl stub. Exported rather than interpolated into the stub
# script, because an unquoted heredoc would expand $1 at write time.
export ASTRA_TEST_REBOOT_LOG="$TMP/reboot.log"

ab() {
  bash "$TOOL" "$@" 2>>"$TMP/stderr.log"
}
reset_world() {
  : >"$TMP/bootctl.log"
  : >"$TMP/reboot.log"
  rm -f "$STATE/state"
  rm -f "$ESP/loader/entries"/*.conf
}

echo "astra-boot state machine"

# ---------------------------------------------------------------- 1. promote --
echo
echo "a switch, then a boot, then a healthy machine"
reset_world
ln -sfn "$PROFILES/system-4-link" "$RUN/current-system"
printf 'real cmdline quiet splash\n' >"$STATE/cmdline-4"
ln -sfn "$PROFILES/system-4-link" "$STATE/current-4"

ab pending
assert_eq "pending marks the generation we just switched to" \
  "$(grep -c '^pending=4$' "$STATE/state")" "1"

ab arm
assert_contains "arm puts the new generation on trial" "$(cat "$STATE/state")" "testing=4"
assert_contains "and boots it next time (default points at the trial)" \
  "$(cat "$TMP/bootctl.log")" "set-default Astra n=4 (testing)"
assert_eq "a boot entry was written for it" \
  "$(ls "$ESP/loader/entries" | grep -c 'astra-4.conf')" "1"
assert_eq "the entry names the real kernel" \
  "$(grep -c "linux .*system-4-link/kernel" "$ESP/loader/entries/astra-4.conf")" "1"

ab health >/dev/null
ab guard # first pass starts the promotion timer
ab guard # second pass finds it has been healthy long enough
assert_contains "a healthy trial is promoted" "$(cat "$STATE/state")" "stable=4"
assert_contains "the boot default follows" \
  "$(cat "$TMP/bootctl.log")" "set-default Astra n=4 stable"
assert_contains "promotion is counted" "$(cat "$STATE/state")" "promotions=1"
assert_eq "no reboot happened" "$(wc -l <"$TMP/reboot.log" | tr -d ' ')" "0"

# --------------------------------------------------------------- 2. rollback --
echo
echo "a machine that is on trial and will not come up"
reset_world
ln -sfn "$PROFILES/system-5-link" "$RUN/current-system"
printf 'fake cmdline\n' >"$STATE/cmdline-5"
ab pending >/dev/null
ab arm >/dev/null
assert_contains "generation 5 is on trial" "$(cat "$STATE/state")" "testing=5"

# now the failing check starts failing, twice (ASTRA_FAILURES=2)
touch "$FLAKY_MARKER"
ab guard >/dev/null
assert_eq "one failure is not enough" "$(wc -l <"$TMP/reboot.log" | tr -d ' ')" "0"
assert_contains "but it is counted" "$(cat "$STATE/state")" "failures=1"

ab guard >/dev/null
assert_eq "the second failure rolls back" "$(wc -l <"$TMP/reboot.log" | tr -d ' ')" "1"
assert_contains "the default goes back to the good generation" \
  "$(cat "$TMP/bootctl.log")" "set-default Astra n=4 stable"
assert_contains "the generation we left is marked failed in the menu" \
  "$(cat "$ESP/loader/entries/astra-5.conf")" "Astra n=5 (failed)"
assert_contains "and the trial is over" "$(cat "$STATE/state")" "testing="

# a machine sitting on the stable generation has nothing to do
reset_world
ln -sfn "$PROFILES/system-4-link" "$RUN/current-system"
printf 'real cmdline\n' >"$STATE/cmdline-4"
ab arm >/dev/null
ab promote 4 >/dev/null
touch "$FLAKY_MARKER"
ab guard >/dev/null
assert_contains "the stable generation is marked stable" "$(cat "$STATE/state")" "stable=4"
ab guard >/dev/null
ab guard >/dev/null
assert_eq "and the guard leaves it alone, however many times it runs" \
  "$(wc -l <"$TMP/reboot.log" | tr -d ' ')" "0"

# ------------------------------------------------- 3. manual rollback steps --
echo
echo "a manual rollback from the good generation"
reset_world
ln -sfn "$PROFILES/system-4-link" "$RUN/current-system"
printf 'c\n' >"$STATE/cmdline-4"
printf 'c\n' >"$STATE/cmdline-3"
ab promote 4 >/dev/null
ab rollback >/dev/null
assert_contains "steps back to the previous good generation" \
  "$(cat "$TMP/bootctl.log")" "set-default Astra n=3 stable"
assert_eq "and reboots into it" "$(wc -l <"$TMP/reboot.log" | tr -d ' ')" "1"

# ------------------------------------------------------ 4. missing generations --
echo
echo "generations the garbage collector took"
reset_world
rm -rf "$PROFILES/system-2-link"
ln -sfn "$PROFILES/system-3-link" "$RUN/current-system"
printf 'c\n' >"$STATE/cmdline-3"
ab promote 3 >/dev/null
assert_eq "no entry is written for a generation with no kernel" \
  "$(ls "$ESP/loader/entries" | grep -c 'astra-2.conf')" "0"

# the default must still be settable when the stable generation is gone
reset_world
ln -sfn "$PROFILES/system-4-link" "$RUN/current-system"
printf 'c\n' >"$STATE/cmdline-4"
ab promote 4 >/dev/null
rm -rf "$PROFILES/system-4-link"
ln -sfn "$PROFILES/system-5-link" "$RUN/current-system"
ab arm >/dev/null
assert_contains "falls back to a generation that exists" \
  "$(cat "$TMP/bootctl.log")" "set-default Astra n=5 stable"

# ------------------------------------------------------------- 5. the plumbing --
echo
echo "plumbing"
reset_world
ln -sfn "$PROFILES/system-3-link" "$RUN/current-system"
ab generations >/dev/null 2>&1
out=$(ab generations)
case "$out" in
  *system-3-link*) ok "generations lists what is in the store" ;;
  *) no "generations lists what is in the store" "[$out]" ;;
esac
out=$(ab status)
case "$out" in
  *"running"*"3"*) ok "status names the running generation" ;;
  *) no "status names the running generation" "$(printf '%s' "$out" | head -4)" ;;
esac
ab restore-plan 4 >/dev/null 2>&1
assert_eq "restore-plan without a snapshot is an error" "$?" "1"
ab nonsense-command >/dev/null 2>&1
assert_eq "an unknown command exits non-zero" "$?" "1"
ab usage | grep -q restore-plan && ok "usage lists every command" || no "usage lists every command"

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]