#!/usr/bin/env bash
# 续传缺失分片并组装 Godot 包
set -u
DIR=/d/tools/godot
cd "$DIR" || exit 1
AID=425559552
URL=$(curl -sI --max-time 20 -H "Accept: application/octet-stream" \
  "https://api.github.com/repos/godotengine/godot/releases/assets/$AID" \
  | tr -d '\r' | awk 'tolower($1)=="location:"{print $2}')
[ -z "${URL:-}" ] && { echo "no url"; exit 2; }
TOTAL=79844616
N=8
CHUNK=$(( (TOTAL + N - 1) / N ))
for i in $(seq 0 $((N-1))); do
  START=$(( i * CHUNK )); END=$(( START + CHUNK - 1 ))
  [ "$END" -ge "$TOTAL" ] && END=$((TOTAL - 1))
  WANT=$(( END - START + 1 ))
  HAVE=$(stat -c%s "parts/part_$i" 2>/dev/null || echo 0)
  if [ "$HAVE" -lt "$WANT" ]; then
    echo "resume part_$i: $HAVE -> $WANT"
    curl -s --max-time 900 -r "$((START+HAVE))-$END" "https://api.github.com/repos/godotengine/godot/releases/assets/$AID" -L >> "parts/part_$i" || true
    HAVE=$(stat -c%s "parts/part_$i")
    echo "  now $HAVE"
  fi
done
cat parts/part_0 parts/part_1 parts/part_2 parts/part_3 parts/part_4 parts/part_5 parts/part_6 parts/part_7 > godot.zip
SIZE=$(stat -c%s godot.zip)
echo "assembled=$SIZE expected=$TOTAL"
[ "$SIZE" = "$TOTAL" ] && echo OK || echo MISMATCH
