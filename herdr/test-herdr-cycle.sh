#!/usr/bin/env bash
# E2E tests for herdr-cycle.sh.
#
# Runs the script against a stubbed `herdr` (stateful, so session list/attach/
# stop/delete mutate a JSON file) and a deterministic `fzf` stub that returns
# one preselected line per invocation from a seq file (empty line = user
# aborted with ESC/Ctrl+C, "FIRST" = first candidate on stdin).
#
# Usage:  bash herdr/test-herdr-cycle.sh   (or ./herdr/test-herdr-cycle.sh)
# Exit:   0 = all scenarios passed, 1 = one or more failed.
# The temp workspace is created under $(mktemp -d) and removed on exit.

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-cycle.sh"
WORK="$(mktemp -d)"
export HERDR_TEST_DIR="$WORK"
trap 'rm -rf "$HERDR_TEST_DIR"' EXIT

bash -n "$SCRIPT" || { echo "SYNTAX FAIL: $SCRIPT"; exit 1; }

pass=0
fail=0

mkdir -p "$HERDR_TEST_DIR/bin"
export PATH="$HERDR_TEST_DIR/bin:$PATH"

# --- stub herdr: logs every call; list reads state.json; attach creates if
# --- missing; stop marks stopped; delete removes the session.
cat > "$HERDR_TEST_DIR/bin/herdr" <<'STUB'
#!/usr/bin/env bash
echo "herdr $*" >> "$HERDR_TEST_DIR/calls.log"
case "$1 $2" in
  "session list") cat "$HERDR_TEST_DIR/state.json" ;;
  "session attach")
    if ! grep -q "\"name\":\"$3\"" "$HERDR_TEST_DIR/state.json"; then
      python3 -c "import json;p='$HERDR_TEST_DIR/state.json';d=json.load(open(p));d['sessions'].append({'default':False,'name':'$3','running':True,'session_dir':'/tmp/$3','socket_path':'/tmp/$3.sock'});json.dump(d,open(p,'w'))"
    fi ;;
  "session stop")
    python3 -c "import json;p='$HERDR_TEST_DIR/state.json';d=json.load(open(p));
for s in d['sessions']:
    if s['name']=='$3': s['running']=False
json.dump(d,open(p,'w'))" ;;
  "session delete")
    python3 -c "import json;p='$HERDR_TEST_DIR/state.json';d=json.load(open(p));d['sessions']=[s for s in d['sessions'] if s['name']!='$3'];json.dump(d,open(p,'w'))" ;;
esac
STUB
chmod +x "$HERDR_TEST_DIR/bin/herdr"

# --- stub fzf: consumes one line from seq.txt per call (always advances, even
# --- for empty lines = aborts, mirroring real fzf consuming the keypress).
cat > "$HERDR_TEST_DIR/bin/fzf" <<'FZF'
#!/usr/bin/env bash
IFS= read -r line < "$HERDR_TEST_DIR/seq.txt" || line=""
sed -i '1d' "$HERDR_TEST_DIR/seq.txt" 2>/dev/null || true
if [ "$line" = "FIRST" ]; then line=$(head -n1); fi
printf '%s\n' "$line"
FZF
chmod +x "$HERDR_TEST_DIR/bin/fzf"

# --- helpers ----------------------------------------------------------------

mkstate() { # entries as "name:true|false"; writes state.json (default sys + entries)
  python3 - "$@" <<'PY'
import json, os, sys
p = os.path.join(os.environ["HERDR_TEST_DIR"], "state.json")
default = {"default": True, "name": "default", "running": True, "session_dir": "/tmp", "socket_path": "/tmp/d.sock"}
entries = []
for e in sys.argv[1:]:
    name, running = e.rsplit(":", 1)
    entries.append({"default": False, "name": name, "running": running == "true",
                    "session_dir": f"/tmp/{name}", "socket_path": f"/tmp/{name}.sock"})
json.dump({"sessions": [default] + entries}, open(p, "w"))
PY
}

reset() { rm -f "$HERDR_TEST_DIR/calls.log" "$HERDR_TEST_DIR/seq.txt"; : > "$HERDR_TEST_DIR/calls.log"; }

setup() { reset; mkstate "${@:3}"; printf '%s' "$1" > "$HERDR_TEST_DIR/seq.txt"; }

check() { # $1 name $2 expected-non-list-calls $3 expected-exit
  bash "$SCRIPT" </dev/null
  code=$?
  diff <(grep -v "session list" "$HERDR_TEST_DIR/calls.log" | grep .) <(printf "%s\n" "$2" | grep .) >/dev/null && c=ok || c=DIFF
  [ "$code" = "$3" ] && e=ok || e="got $code"
  echo "  [ $1 ] exit: $e | calls: $c"
  grep -v "session list" "$HERDR_TEST_DIR/calls.log" | sed 's/^/      /'
  [ "$c" = ok ] && [ "$e" = ok ] && pass=$((pass+1)) || fail=$((fail+1))
}

A='2025-08-09-10-00-00-001'; B='2025-08-09-10-00-00-002'; C='2025-08-09-10-00-00-003'
TS='[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{3}'

# --- scenarios --------------------------------------------------------------

# T1: only default -> create-now; herdr-exit -> stop+delete -> close (no menu)
setup '' ''
bash "$SCRIPT" </dev/null
code=$?
grep -qE "^herdr session attach $TS$" "$HERDR_TEST_DIR/calls.log" && a=ok || a=BAD
grep -qE "^herdr session stop $TS$"   "$HERDR_TEST_DIR/calls.log" && s=ok || s=BAD
grep -qE "^herdr session delete $TS$" "$HERDR_TEST_DIR/calls.log" && d=ok || d=BAD
[ "$code" = 0 ] && e=ok || e=$code
{ [ "$a" = ok ] && [ "$s" = ok ] && [ "$d" = ok ] && [ "$e" = ok ] && echo "  [ T1 create-now -> cleanup -> close ] OK" && pass=$((pass+1)) || { echo "  [ T1 ] FAIL exit=$e attach=$a stop=$s delete=$d"; fail=$((fail+1)); }; }

# T2: delete running stops first; one left -> close
setup "Delete session (2)
$A (running)
" '' "$A:true" "$B:false"
check T2 "herdr session stop $A
herdr session delete $A" 0

# T3: attach single session -> herdr exits -> cleanup -> no sessions left -> close
setup "Attach to session (1)
$A (stopped)
" '' "$A:false"
check T3 "herdr session attach $A
herdr session stop $A
herdr session delete $A" 0

# T4: attach with a leftover -> cleanup -> menu returns -> abort -> close
setup "Attach to session (2)
$A (stopped)

" '' "$A:false" "$B:true"
check T4 "herdr session attach $A
herdr session stop $A
herdr session delete $A" 0

# T5: ctrl+c in delete picker -> main menu; abort on menu -> close
setup "Delete session (1)

" '' "$A:true"
check T5 '' 0

# T6: delete stopped -> no stop call
setup "Delete session (1)
$A (stopped)
" '' "$A:false"
check T6 "herdr session delete $A" 0

# T7: STAY in delete picker: 3 -> delete A, then B -> close (C kept)
setup "Delete session (3)
$A (running)
$B (stopped)
" '' "$A:true" "$B:false" "$C:false"
check T7 "herdr session stop $A
herdr session delete $A
herdr session delete $B" 0

# T8: abort mid-delete -> main menu -> delete last single one -> close
setup "Delete session (2)

Delete session (1)
$A (stopped)
" '' "$A:false" "$B:true"
check T8 "herdr session delete $A" 0

# T9: legacy herdr_* / unrelated sessions ARE listed (only default excluded)
setup "Delete session (3)
legacy_herdr_xxx (running)
" '' "$A:false" legacy_herdr_xxx:true unrelated:false
check T9 "herdr session stop legacy_herdr_xxx
herdr session delete legacy_herdr_xxx" 0

# T10: New session from menu with a leftover -> cleanup fresh one -> menu -> abort -> close
setup 'New session

' '' "$A:false"
bash "$SCRIPT" </dev/null
code=$?
grep -qE "^herdr session attach $TS$" "$HERDR_TEST_DIR/calls.log" && a=ok || a=BAD
grep -qE "^herdr session stop $TS$"   "$HERDR_TEST_DIR/calls.log" && s=ok || s=BAD
grep -qE "^herdr session delete $TS$" "$HERDR_TEST_DIR/calls.log" && d=ok || d=BAD
grep -q "$A" "$HERDR_TEST_DIR/calls.log" && a_unused=BAD || a_unused=ok # leftover untouched
[ "$code" = 0 ] && e=ok || e=$code
{ [ "$a" = ok ] && [ "$s" = ok ] && [ "$d" = ok ] && [ "$a_unused" = ok ] && [ "$e" = ok ] && echo "  [ T10 new-session-from-menu -> cleanup -> menu ] OK" && pass=$((pass+1)) || { echo "  [ T10 ] FAIL exit=$e attach=$a stop=$s delete=$d leftover=$a_unused"; fail=$((fail+1)); }; }

# T11: New session with name (typed via stdin) -> attach <name>-<ts> ->
# cleanup -> menu -> abort -> close
setup 'New session with name
' '' "$A:false"
printf 'work\n' > "$HERDR_TEST_DIR/name-in.txt"
bash "$SCRIPT" < "$HERDR_TEST_DIR/name-in.txt"
code=$?
grep -qE "^herdr session attach work-$TS$" "$HERDR_TEST_DIR/calls.log" && a=ok || a=BAD
grep -qE "^herdr session stop work-$TS$"   "$HERDR_TEST_DIR/calls.log" && s=ok || s=BAD
grep -qE "^herdr session delete work-$TS$" "$HERDR_TEST_DIR/calls.log" && d=ok || d=BAD
grep -q "$A" "$HERDR_TEST_DIR/calls.log" && a_unused=BAD || a_unused=ok # leftover untouched
[ "$code" = 0 ] && e=ok || e=$code
{ [ "$a" = ok ] && [ "$s" = ok ] && [ "$d" = ok ] && [ "$a_unused" = ok ] && [ "$e" = ok ] && echo "  [ T11 named session -> cleanup -> menu ] OK" && pass=$((pass+1)) || { echo "  [ T11 ] FAIL exit=$e attach=$a stop=$s delete=$d leftover=$a_unused"; fail=$((fail+1)); }; }

# T12: invalid name is rejected -> re-asked -> valid name used; no stray calls
setup 'New session with name
' '' "$A:false"
printf 'bad name!\nok\n' > "$HERDR_TEST_DIR/name-in.txt"
bash "$SCRIPT" < "$HERDR_TEST_DIR/name-in.txt"
code=$?
grep -qE "^herdr session attach ok-$TS$" "$HERDR_TEST_DIR/calls.log" && a=ok || a=BAD
grep -q "bad" "$HERDR_TEST_DIR/calls.log" && n=BAD || n=ok
[ "$code" = 0 ] && e=ok || e=$code
{ [ "$a" = ok ] && [ "$n" = ok ] && [ "$e" = ok ] && echo "  [ T12 invalid name retried ] OK" && pass=$((pass+1)) || { echo "  [ T12 ] FAIL exit=$e attach=$a no_bad=$n"; fail=$((fail+1)); }; }

# T13: aborted at the name prompt (EOF) -> back to main menu -> abort -> close, no calls
setup 'New session with name

' '' "$A:false"
check T13 '' 0

echo
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && exit 0 || exit 1