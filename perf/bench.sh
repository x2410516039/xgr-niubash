#!/usr/bin/env bash
# Latency benchmark for `niu -c` style one-shot invocations.
# usage: bench.sh <label> <niu-path> [rounds]
# Measures wall-clock ms per invocation for a fixed command set; prints
# avg / median / min per command as TSV.

set -u
LABEL="$1"; NIU="$2"; ROUNDS="${3:-30}"

# Warm OS caches and binary pages.
"$NIU" -c "true" >/dev/null 2>&1

bench_cmd() { # $1=cmd-for-niu  $2=desc
  local cmd="$1" desc="$2"
  local vals=() s e v
  for _ in $(seq 1 "$ROUNDS"); do
    s=$(date +%s%N)
    "$NIU" $cmd >/dev/null 2>&1
    e=$(date +%s%N)
    vals+=($(( (e - s) / 1000000 )))
  done
  local sorted total=0 n=0
  sorted=($(printf '%s\n' "${vals[@]}" | sort -n))
  for v in "${vals[@]}"; do total=$((total+v)); n=$((n+1)); done
  local mid=$(( n / 2 ))
  printf '%s\t%s\t%s\t%s\t%s\n' "$desc" "$((total/n))" "${sorted[$mid]}" "${sorted[0]}" "${vals[*]}"
}

echo -e "command\tavg_ms\tmedian_ms\tmin_ms\truns"
bench_cmd '-c true'                      'niu -c true (minimal)'
bench_cmd '-c echo hello'                'niu -c echo hello'
bench_cmd '-c seq 1 5 | tail -2'         'niu -c pipe (seq|tail)'
bench_cmd '-c git --version'             'niu -c git --version (external)'
bench_cmd '--encoded-command ZWNobyBoZWxsbw==' 'niu --encoded-command (echo hello)'
bench_cmd '-C true'                      'niu -C true (repl-command)'
