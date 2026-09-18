#!/usr/bin/env bash
# niubash vs native Git Bash end-to-end latency, interleaved rounds.
# Usage: perf/bench-vs-bash.sh [rounds]   (default 20)
# Paths are machine-specific; edit below when switching machines.
set -u

ROUNDS=${1:-20}
A=/c/Progra~1/Git/bin/bash.exe                 # native Git Bash 5.3 (cygwin)
B=/d/project/git-clone/niubash/target/release/niu.exe   # this build
C=/c/Users/xianguanrong/AppData/Local/Programs/Niubash/niu.exe # installed v1.1.2

CMDS=(
  'true'
  'echo hello'
  'echo hello | grep -c hello'
  'for i in 1 2 3 4 5; do echo $i; done'
)

# warm-up
"$A" -c 'true' >/dev/null 2>&1
"$B" -c 'true' >/dev/null 2>&1
"$C" -c 'true' >/dev/null 2>&1

for cmd in "${CMDS[@]}"; do
  AV=(); BV=(); CV=()
  for ((r=0; r<ROUNDS; r++)); do
    t0=$(date +%s%N); "$A" -c "$cmd" >/dev/null 2>&1; t1=$(date +%s%N); AV+=( $(( (t1-t0)/1000 )) )
    t0=$(date +%s%N); "$B" -c "$cmd" >/dev/null 2>&1; t1=$(date +%s%N); BV+=( $(( (t1-t0)/1000 )) )
    t0=$(date +%s%N); "$C" -c "$cmd" >/dev/null 2>&1; t1=$(date +%s%N); CV+=( $(( (t1-t0)/1000 )) )
  done
  stats() { # min avg (us)
    local arr=("$@") min=999999999 sum=0
    for v in "${arr[@]}"; do (( v < min )) && min=$v; (( sum+=v )); done
    echo "$min $(( sum / ${#arr[@]} ))"
  }
  read -r A_MIN A_AVG <<< "$(stats "${AV[@]}")"
  read -r B_MIN B_AVG <<< "$(stats "${BV[@]}")"
  read -r C_MIN C_AVG <<< "$(stats "${CV[@]}")"
  printf '%-42s | gitbash min %5s.%03sms avg %5sms | niu(min) min %5s.%03sms avg %5sms | installed min %sms avg %sms\n' \
    "$cmd" \
    "$(( A_MIN/1000 ))" "$(( A_MIN%1000 ))" "$(( A_AVG/1000 ))" \
    "$(( B_MIN/1000 ))" "$(( B_MIN%1000 ))" "$(( B_AVG/1000 ))" \
    "$(( C_MIN/1000 ))" "$(( C_AVG/1000 ))"
done
