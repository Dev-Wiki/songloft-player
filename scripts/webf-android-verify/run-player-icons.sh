#!/usr/bin/env bash
# 驱动 run-player-icons.sh：起临时后端 + 传 miot 插件 + 跑模拟器验证播放器控件渲染。
# SHOT_TAG=before|after 区分修复前后的截图。
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OUT="$HERE/out/player-icons"
REPO_ROOT=$(cd "$HERE/../../.." && pwd)
MIOT_ROOT="$REPO_ROOT/jsplugins-src/songloft-plugin-miot"
SERVER_PORT="${SERVER_PORT:-58395}"
SHOT_TAG="${SHOT_TAG:-before}"
# SLOW_FONT=<秒> 时在设备与后端之间插一个只拖慢 .otf 的透传代理，复现字体迟到竞态。
SLOW_FONT="${SLOW_FONT:-}"
COMPOSE=(docker compose -f "$HERE/compose.yaml")
server_pid=''

[ -e /dev/kvm ] || { echo "[player-icons] /dev/kvm required" >&2; exit 1; }
[ -f "$HERE/out/songloft-x86_64-release.apk" ] || {
  echo "[player-icons] APK not found. Run run.sh first." >&2; exit 1; }
[ -f "$MIOT_ROOT/dist/miot.jsplugin.zip" ] || {
  echo "[player-icons] miot.jsplugin.zip not found. Run 'npm run build' in $MIOT_ROOT" >&2; exit 1; }

mkdir -p "$OUT"
cp "$MIOT_ROOT/dist/miot.jsplugin.zip" "$OUT/miot.jsplugin.zip"
cp "$HERE/out/songloft-x86_64-release.apk" "$OUT/songloft-x86_64-release.apk"

export ADBKEY=$(<"$HOME/.android/adbkey")
export SERVER_PORT

cleanup() {
  if [ "${KEEP_RUNNING:-}" != 1 ]; then
    [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null && wait "$server_pid" 2>/dev/null || true
    "${COMPOSE[@]}" down --remove-orphans >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

RUNTIME_DIR="$OUT/runtime"
rm -rf "$RUNTIME_DIR/data"
mkdir -p "$RUNTIME_DIR/data" "$RUNTIME_DIR/music"

echo "[player-icons] building temp server"
(cd "$REPO_ROOT" && go build -tags 'dev lite' -o "$RUNTIME_DIR/songloft-server" .)
"$RUNTIME_DIR/songloft-server" \
  -port "$SERVER_PORT" \
  -db "$RUNTIME_DIR/data/songloft.db" \
  -music "$RUNTIME_DIR/music" \
  >"$OUT/server.log" 2>&1 &
server_pid=$!
for _ in $(seq 1 60); do
  curl -fsS "http://127.0.0.1:${SERVER_PORT}/api/v1/health" >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS "http://127.0.0.1:${SERVER_PORT}/api/v1/health" >/dev/null

echo "[player-icons] starting emulator"
"${COMPOSE[@]}" up -d emulator

echo "[player-icons] uploading miot plugin"
token=$(curl -fsS "http://127.0.0.1:${SERVER_PORT}/api/v1/auth/login" \
  -H 'Content-Type: application/json' \
  --data '{"username":"admin","password":"admin"}' | jq -r '.access_token')
curl -fsS "http://127.0.0.1:${SERVER_PORT}/api/v1/jsplugins/upload" \
  -H "Authorization: Bearer ${token}" \
  -F "file=@${OUT}/miot.jsplugin.zip" >"$OUT/plugin-upload.json"
curl -fsS "http://127.0.0.1:${SERVER_PORT}/api/v1/jsplugins/" \
  -H "Authorization: Bearer ${token}" >"$OUT/plugins.json"
plugin_id=$(jq -r '.plugins[] | select(.entry_path == "miot") | .id' "$OUT/plugins.json")
[ -n "$plugin_id" ] && [ "$plugin_id" != null ] || {
  echo "[player-icons] plugin upload failed" >&2; cat "$OUT/plugin-upload.json" >&2; exit 1; }

curl -fsS -X PUT "http://127.0.0.1:${SERVER_PORT}/api/v1/settings/tab-config" \
  -H "Authorization: Bearer ${token}" -H 'Content-Type: application/json' \
  --data "$(jq -n --argjson id "$plugin_id" \
    '{show_library: true, show_playlists: true,
      plugin_tabs: [{plugin_id: $id, entry_path: "miot", name: "智能音箱"}]}')" \
  >"$OUT/tab-config.json"

echo "[player-icons] running verification (tag=$SHOT_TAG)"
"${COMPOSE[@]}" run --rm --no-deps --entrypoint bash \
  -e SERVER_PORT="$SERVER_PORT" -e ADBKEY="$ADBKEY" -e SHOT_TAG="$SHOT_TAG" -e SLOW_FONT="$SLOW_FONT" \
  -v "$OUT:/out" -v "$HERE/runner-miot:/opt/runner-miot:ro" \
  test-runner /opt/runner-miot/run-player-icons.sh

echo "[player-icons] done. Screenshots in $OUT/"
