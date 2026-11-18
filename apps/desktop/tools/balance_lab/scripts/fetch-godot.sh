#!/usr/bin/env bash
# 稳定 URL + 断点续传循环下载 Godot（gh-proxy），直到大小吻合
set -u
DIR=/d/tools/godot
cd "$DIR" || exit 1
TOTAL=79844616
URL="https://gh-proxy.com/https://github.com/godotengine/godot/releases/download/4.6.3-stable/Godot_v4.6.3-stable_win64.exe.zip"
rm -f godot.zip
for attempt in $(seq 1 200); do
  HAVE=$(stat -c%s godot.zip 2>/dev/null || echo 0)
  if [ "$HAVE" -ge "$TOTAL" ]; then break; fi
  curl -sL --max-time 600 -C - -o godot.zip "$URL" >/dev/null 2>&1
  NOW=$(stat -c%s godot.zip 2>/dev/null || echo 0)
  echo "attempt=$attempt have=$HAVE now=$NOW / $TOTAL"
  if [ "$NOW" -ge "$TOTAL" ]; then break; fi
  if [ "$NOW" -le "$HAVE" ]; then sleep 5; else sleep 1; fi
done
SIZE=$(stat -c%s godot.zip 2>/dev/null || echo 0)
if [ "$SIZE" = "$TOTAL" ]; then echo "DOWNLOAD_OK size=$SIZE"; else echo "DOWNLOAD_INCOMPLETE size=$SIZE"; fi
