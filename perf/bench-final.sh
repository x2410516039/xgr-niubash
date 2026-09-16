#!/usr/bin/env bash
# Final A/B e2e comparison: 20 interleaved rounds each, report raw + stats.
A=/d/project/git-clone/niubash-master-baseline/target/release/niu.exe
B=/d/project/git-clone/niubash/perf/niu-fastpath.exe
AV=(); BV=()
"$A" -c true >/dev/null 2>&1; "$B" -c true >/dev/null 2>&1
for i in $(seq 1 20); do
  s=$(date +%s%N); "$A" -c "echo hello" >/dev/null 2>&1; e=$(date +%s%N); AV+=($(( (e-s)/1000000 )))
  s=$(date +%s%N); "$B" -c "echo hello" >/dev/null 2>&1; e=$(date +%s%N); BV+=($(( (e-s)/1000000 )))
done
echo "A master-build : ${AV[*]}"
echo "B fastpath     : ${BV[*]}"
printf '%s\n' "${AV[@]}" | sort -n | awk '{t+=$1; a[NR]=$1} END{printf "A: avg=%.0f med=%.0f min=%.0f\n", t/NR, a[10], a[1]}'
printf '%s\n' "${BV[@]}" | sort -n | awk '{t+=$1; a[NR]=$1} END{printf "B: avg=%.0f med=%.0f min=%.0f\n", t/NR, a[10], a[1]}'
# encoded-command on B, 10 rounds
EV=()
for i in $(seq 1 10); do
  s=$(date +%s%N); "$B" --encoded-command ZWNobyBoZWxsbw== >/dev/null 2>&1; e=$(date +%s%N); EV+=($(( (e-s)/1000000 )))
done
echo "B encoded-cmd  : ${EV[*]}"
printf '%s\n' "${EV[@]}" | sort -n | awk '{t+=$1; a[NR]=$1} END{printf "B-enc: avg=%.0f med=%.0f min=%.0f\n", t/NR, a[5], a[1]}'
