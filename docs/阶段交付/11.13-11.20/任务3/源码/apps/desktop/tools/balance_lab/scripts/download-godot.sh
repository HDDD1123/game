#!/usr/bin/env bash
# 分段并发下载 Godot 4.6.3 win64（GitHub API 资产重定向出的签名 URL 支持 Range）
set -u
DIR=/d/tools/godot
mkdir -p "$DIR/parts"
cd "$DIR" || exit 1

AID=425559552
URL=$(curl -sI --max-time 20 -H "Accept: application/octet-stream" \
  "https://api.github.com/repos/godotengine/godot/releases/assets/$AID" \
  | tr -d '\r' | awk 'tolower($1)=="location:"{print $2}')
if [ -z "${URL:-}" ]; then echo "no redirect URL"; exit 2; fi
TOTAL=$(curl -sI --max-time 20 "$URL" | tr -d '\r' | awk 'tolower($1)=="content-length:"{print $2}' | tail -1)
if [ -z "${TOTAL:-}" ]; then echo "no content-length"; exit 3; fi
echo "total=$TOTAL"

N=8
CHUNK=$(( (TOTAL + N - 1) / N ))
for i in $(seq 0 $((N-1))); do
  START=$(( i * CHUNK ))
  END=$(( START + CHUNK - 1 ))
  [ "$END" -ge "$TOTAL" ] && END=$((TOTAL - 1))
  (
    for attempt in 1 2 3; do
      curl -s --max-time 900 -r "$START-$END" -o "parts/part_$i" "$URL" && \
        [ "$(stat -c%s "parts/part_$i" 2>/dev/null)" = "$((END-START+1))" ] && break
      sleep 2
    done
  ) &
done
wait

cat parts/part_* > godot.zip
SIZE=$(stat -c%s godot.zip)
echo "downloaded=$SIZE expected=$TOTAL"
[ "$SIZE" = "$TOTAL" ] && echo OK || echo MISMATCH
