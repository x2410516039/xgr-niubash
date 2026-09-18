#!/usr/bin/env bash
# Per-stage startup trace comparison: run NIU_TRACE_STARTUP N times per binary,
# take the per-stage minimum (least load-contaminated).
A=/d/project/git-clone/niubash/perf/niu-master.exe
B=/d/project/git-clone/niubash/perf/niu-fastpath.exe
C=/c/Users/xianguanrong/AppData/Local/Programs/Niubash/niu.exe

trace_min() { # bin rounds -> TSV stage\tmin_total\tmin_delta
  local bin="$1" n="$2"
  local tmp="/tmp/niu_trace_$.txt"
  : >"$tmp"
  local i
  for i in $(seq 1 "$n"); do
    NIU_TRACE_STARTUP=1 "$bin" -c "echo hello" 2>&1 >/dev/null \
      | sed 's/NIU_TRACE_STARTUP: *//; s/ms *(delta */\t/; s/ *) */\t/; s/  */\t/g' >>"$tmp"
  done
  awk -F'\t' '{ gsub(/^ +| +$/,"",$1); gsub(/^ +| +$/,"",$2); gsub(/^ +| +$/,"",$3);
    if (!($1 in mint) || $2+0 < mint[$1]) { mint[$1]=$2+0; mind[$1]=$3+0 } }
  END { for (k in mint) printf "%s\t%.1f\t%.2f\n", k, mint[k], mind[k] }' "$tmp" | sort -t$'\t' -k2 -n
  rm -f "$tmp"
}

echo "== per-stage minimum of 5 runs (total_ms, delta_ms) =="
for b in A B C; do
  eval 'bin=$'"$b"
  echo "--- $b"
  trace_min "$bin" 5 | awk -F'\t' -v OFS='\t' '{printf "  %-32s %8.1f %8.2f\n", $1, $2, $3}'
done
