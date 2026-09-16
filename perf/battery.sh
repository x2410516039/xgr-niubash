#!/usr/bin/env bash
# Behavior-parity battery: run the same command list through two niu binaries
# and diff stdout/stderr/exit-code.
# usage: battery.sh <baseline-niu> <candidate-niu> <workdir>

OLD="$1"; NEW="$2"; WORK="$3"
mkdir -p "$WORK"
rm -f "$WORK"/old_* "$WORK"/new_* 2>/dev/null

run_case() {
  bin="$1"; tag="$2"; id="$3"; cmd="$4"
  {
    out=$("$bin" -c "$cmd" 2>&1)
    rc=$?
    printf '%s\n--exit=%s\n' "$out" "$rc"
  } >"$WORK/${tag}_${id}" 2>&1
}

CMDS=(
  'echo hello'
  'echo "a b" '"'"'c d'"'"''
  'printf "%s\n" one two three'
  'seq 1 5 | tail -2'
  'x=5; echo $((x*7))'
  'for i in 1 2 3; do echo -n "$i,"; done; echo'
  'if true; then echo yes; else echo no; fi'
  'cd /tmp && pwd'
  'false; echo rc=$?'
  'echo err-line 1>&2'
  'trap "echo trapped-exit" EXIT; echo body'
  's=$(echo sub); echo $s'
  'echo hi > /tmp/niu_battery_redirect; cat /tmp/niu_battery_redirect'
  'git --version'
  'echo $BASH_EXECUTION_STRING'
  'FOO=bar; echo ${FOO:-baz} ${MISSING:-dflt}'
  'case abc in a*) echo match;; *) echo nomatch;; esac'
  'fn() { echo fn-$1; }; fn test'
  'pwd'
  'echo $0'
  'cat <<EOF
line1
line2
EOF'
  'unset FOO; [ -z "${FOO+x}" ] && echo unset-ok'
  'seq 1 3 | while read n; do echo "n=$n"; done'
  'echo {1..3}'
  '[[ "abc" == a* ]] && echo glob-ok'
  'exit 7'
  'command -v ls'
  'alias gphase'
  'history | tail -3'
)

n=${#CMDS[@]}
for i in $(seq 0 $((n-1))); do
  id=$(printf 'c%02d' "$i")
  run_case "$OLD" old "$id" "${CMDS[$i]}"
  run_case "$NEW" new "$id" "${CMDS[$i]}"
done

fail=0
for i in $(seq 0 $((n-1))); do
  id=$(printf 'c%02d' "$i")
  if ! diff -u "$WORK/old_$id" "$WORK/new_$id" >"$WORK/diff_$id" 2>&1; then
    echo "=== DIFF case $id: ${CMDS[$i]}"
    cat "$WORK/diff_$id"
    fail=$((fail+1))
  fi
done
echo "battery: $n cases, $fail diffs"
exit "$fail"
