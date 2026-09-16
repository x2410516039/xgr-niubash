#!/usr/bin/env bash
# Three-way interleaved benchmark: A=master-build B=fastpath-build C=installed
A=/d/project/git-clone/niubash-master-baseline/target/release/niu.exe
B=/d/project/git-clone/niubash/perf/niu-fastpath.exe
C=/c/Users/xianguanrong/AppData/Local/Programs/Niubash/niu.exe

one() { # bin cmd...
  local bin="$1"; shift
  local s e
  s=$(date +%s%N); "$bin" "$@" >/dev/null 2>&1; e=$(date +%s%N)
  echo $(( (e-s)/1000000 ))
}
stat20() { # bin cmd... -> avg/med/min over 20 runs
  local bin="$1"; shift
  local vals=() i s e
  "$bin" true >/dev/null 2>&1
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    s=$(date +%s%N); "$bin" "$@" >/dev/null 2>&1; e=$(date +%s%N)
    vals+=($(( (e-s)/1000000 )))
  done
  printf '%s\n' "${vals[@]}" | sort -n | awk '{t+=$1} END{printf "avg=%.0f med=%.0f min=%.0f max=%.0f", t/NR, $10, $1, $20}'
}

echo "=== interleaved rounds (ms): A=master-build B=fastpath C=installed ==="
for cmd in "true" "echo hello" "seq 1 5"; do
  echo "### niu -c '$cmd'"
  for r in 1 2 3 4 5; do
    printf '  r%s  A:%s  B:%s  C:%s\n' "$r" "$(one "$A" -c "$cmd")" "$(one "$B" -c "$cmd")" "$(one "$C" -c "$cmd")"
  done
  printf '  20-run  A(%s)  B(%s)  C(%s)\n' "$(stat20 "$A" -c "$cmd")" "$(stat20 "$B" -c "$cmd")" "$(stat20 "$C" -c "$cmd")"
  echo
done
echo "### niu -C true"
for r in 1 2 3 4 5; do
  printf '  r%s  A:%s  B:%s  C:%s\n' "$r" "$(one "$A" -C true)" "$(one "$B" -C true)" "$(one "$C" -C true)"
done
printf '  20-run  A(%s)  B(%s)  C(%s)\n' "$(stat20 "$A" -C true)" "$(stat20 "$B" -C true)" "$(stat20 "$C" -C true)"
