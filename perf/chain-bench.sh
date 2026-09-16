#!/usr/bin/env bash
# Measure per-invocation overhead: native Git Bash vs niubash chain (hook + niu).
GB="/c/Program Files/Git/bin/bash.exe"
NIU="/c/Users/xianguanrong/AppData/Local/Programs/Niubash/niu.exe"
HOOK="/c/Users/xianguanrong/.zcode/hooks/niubash-hook.exe"
JSON='{"session_id":"bench","tool_name":"Bash","tool_input":{"command":"echo hello"}}'
RUNFILE_DIR="$TMPDIR/niubash-hook"
[ -d "$RUNFILE_DIR" ] || RUNFILE_DIR="/tmp/niubash-hook"

t15() { # args: command to time x15 -> prints raw ms list
  local s e vals=() i
  for i in $(seq 1 15); do
    s=$(date +%s%N); "$@" >/dev/null 2>&1; e=$(date +%s%N)
    vals+=($(( (e-s)/1000000 )))
  done
  echo "${vals[*]}"
}
stats() { # stdin: ms list
  printf '%s\n' "$@" | tr ' ' '\n' | sort -n | awk '{t+=$1; a[NR]=$1} END{printf "avg=%d med=%d min=%d max=%d", t/NR, a[int((NR+1)/2)], a[1], a[NR]}'
}

echo "== 1. native Git Bash -c 'echo hello' (hook-free reference) =="
r=$(t15 "$GB" -c "echo hello"); echo "  raw: $r"; echo "  $(stats $r)"

echo "== 2. niu engine only: niu -c 'echo hello' =="
r=$(t15 "$NIU" -c "echo hello"); echo "  raw: $r"; echo "  $(stats $r)"

echo "== 3. hook stage1 only: JSON rewrite via stdin =="
r=$(t15 "$HOOK" <<<"$JSON"); echo "  raw: $r"; echo "  $(stats $r)"

echo "== 4. hook stage2 (runfile full chain): exe reads cmd file + spawns niu =="
r=""
for i in $(seq 1 15); do
  f="$RUNFILE_DIR/bench-$RANDOM$RANDOM.txt"
  printf 'echo hello' >"$f"
  s=$(date +%s%N); "$HOOK" runfile "$f" >/dev/null 2>&1; e=$(date +%s%N)
  r="$r $(( (e-s)/1000000 ))"
done
echo "  raw:$r"; echo "  $(stats $r)"

echo "== 5. realistic chain, grep command =="
GrepCMD='grep -c niubash /c/Users/xianguanrong/.zcode/hooks/niubash-hook.cs'
r=$(t15 "$GB" -c "$GrepCMD"); echo "  native : $(stats $r)"
r=""
for i in $(seq 1 15); do
  f="$RUNFILE_DIR/bench-$RANDOM$RANDOM.txt"
  printf '%s' "$GrepCMD" >"$f"
  s=$(date +%s%N); "$HOOK" runfile "$f" >/dev/null 2>&1; e=$(date +%s%N)
  r="$r $(( (e-s)/1000000 ))"
done
echo "  chain raw:$r"
echo "  chain  : $(stats $r)"

echo "== 6. hook stage1 with grep command (for chain total) =="
JSONG="{\"session_id\":\"bench\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$GrepCMD\"}}"
r=$(t15 "$HOOK" <<<"$JSONG"); echo "  $(stats $r)"
