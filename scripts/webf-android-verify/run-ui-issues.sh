#!/usr/bin/env bash
# miot 插件的「设置页 UI 取证」跑法：盯二维码 <img>、SlSelect 下拉面板落点、
# 语音页两列表单行、toast 宽度这四处，每步都 screencap + uiautomator dump，
# 几何数据留到宿主侧离线比对。参考案例 songloft-org/songloft-plugin-miot#79 / #80。
#
# 复用 run.sh 已构建的 APK 与 compose 里的模拟器；需要先在 miot 插件目录跑过
# `npm run build`。产物落在 out/ui-issues/。
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OUT="$HERE/out/ui-issues"
REPO_ROOT=$(cd "$HERE/../../.." && pwd)
MIOT_ROOT="$REPO_ROOT/jsplugins-src/songloft-plugin-miot"
SERVER_PORT="${SERVER_PORT:-58396}"
COMPOSE=(docker compose -f "$HERE/compose.yaml")
server_pid=''

[ -e /dev/kvm ] || { echo "[ui-issues] /dev/kvm required" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "[ui-issues] Docker unavailable" >&2; exit 1; }
[ -f "$HERE/out/songloft-x86_64-release.apk" ] || {
  echo "[ui-issues] APK not found. Run run.sh first to build it." >&2; exit 1
}
[ -f "$MIOT_ROOT/dist/miot.jsplugin.zip" ] || {
  echo "[ui-issues] miot.jsplugin.zip not found. Run 'npm run build' in $MIOT_ROOT" >&2; exit 1
}

rm -rf "$OUT"; mkdir -p "$OUT"
cp "$MIOT_ROOT/dist/miot.jsplugin.zip" "$OUT/"
cp "$HERE/out/songloft-x86_64-release.apk" "$OUT/"

export ADBKEY=$(<"$HOME/.android/adbkey")
export SERVER_PORT

cleanup() {
  if [ "${KEEP_RUNNING:-}" != 1 ]; then
    [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null && wait "$server_pid" 2>/dev/null || true
    "${COMPOSE[@]}" down --remove-orphans >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

RUNTIME="$OUT/runtime"; mkdir -p "$RUNTIME/data" "$RUNTIME/music"
if (echo >/dev/tcp/127.0.0.1/"$SERVER_PORT") 2>/dev/null; then
  echo "[ui-issues] port $SERVER_PORT in use" >&2; exit 1
fi

echo "[ui-issues] building temp server"
(cd "$REPO_ROOT" && go build -tags 'dev lite' -o "$RUNTIME/songloft-server" .)
"$RUNTIME/songloft-server" -port "$SERVER_PORT" \
  -db "$RUNTIME/data/songloft.db" -music "$RUNTIME/music" \
  >"$OUT/server.log" 2>&1 &
server_pid=$!
for _ in $(seq 1 60); do
  curl -fsS "http://127.0.0.1:${SERVER_PORT}/api/v1/health" >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS "http://127.0.0.1:${SERVER_PORT}/api/v1/health" >/dev/null

token=$(curl -fsS "http://127.0.0.1:${SERVER_PORT}/api/v1/auth/login" \
  -H 'Content-Type: application/json' \
  --data '{"username":"admin","password":"admin"}' | jq -r '.access_token')
AUTH=(-H "Authorization: Bearer ${token}")

# 下拉面板的取证要求选项数把面板顶到 320px 上限（>=8 项），否则触发不了翻转/让位分支。
echo "[ui-issues] seeding 12 playlists"
for i in $(seq 1 12); do
  curl -sS "http://127.0.0.1:${SERVER_PORT}/api/v1/playlists" "${AUTH[@]}" \
    -H 'Content-Type: application/json' \
    --data "$(jq -n --arg n "测试歌单 $i" '{name: $n, type: "normal"}')" \
    -o /dev/null -w '%{http_code} ' || true
done; echo

echo "[ui-issues] starting emulator"
"${COMPOSE[@]}" up -d emulator

echo "[ui-issues] uploading miot plugin"
curl -fsS "http://127.0.0.1:${SERVER_PORT}/api/v1/jsplugins/upload" "${AUTH[@]}" \
  -F "file=@${OUT}/miot.jsplugin.zip" >"$OUT/plugin-upload.json"
curl -fsS "http://127.0.0.1:${SERVER_PORT}/api/v1/jsplugins/" "${AUTH[@]}" >"$OUT/plugins.json"
plugin_id=$(jq -r '.plugins[] | select(.entry_path == "miot") | .id' "$OUT/plugins.json")
[ -n "$plugin_id" ] && [ "$plugin_id" != null ] || {
  echo "[ui-issues] plugin not installed" >&2; cat "$OUT/plugin-upload.json" >&2; exit 1
}

curl -fsS -X PUT "http://127.0.0.1:${SERVER_PORT}/api/v1/settings/tab-config" "${AUTH[@]}" \
  -H 'Content-Type: application/json' \
  --data "$(jq -n --argjson id "$plugin_id" \
    '{show_library: true, show_playlists: true,
      plugin_tabs: [{plugin_id: $id, entry_path: "miot", name: "智能音箱"}]}')" >"$OUT/tab-config.json"

# 插件的 /playlists 在 server_host 未配置或为回环时返回空列表（只带一句提示，不报错），
# 那样「歌单」下拉一个选项都没有、B 段取不到证。这里只要求非回环，不要求真的可达。
LAN_IP="${LAN_IP:-$(ip -4 addr show scope global 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)}"
LAN_IP="${LAN_IP:-192.168.0.1}"
echo "[ui-issues] configuring plugin server_host=http://${LAN_IP}:${SERVER_PORT}"
curl -fsS -X POST "http://127.0.0.1:${SERVER_PORT}/api/v1/jsplugin/miot/config" "${AUTH[@]}" \
  -H 'Content-Type: application/json' \
  --data "$(jq -n --arg h "http://${LAN_IP}:${SERVER_PORT}" '{server_host: $h}')" \
  >"$OUT/plugin-config.json" || true
curl -fsS "http://127.0.0.1:${SERVER_PORT}/api/v1/jsplugin/miot/playlists" "${AUTH[@]}" \
  >"$OUT/plugin-playlists.json" || true
jq -r '.data | length' "$OUT/plugin-playlists.json" 2>/dev/null | xargs echo "[ui-issues] plugin sees playlists:"

echo "[ui-issues] running runner"
"${COMPOSE[@]}" run --rm --no-deps --entrypoint bash \
  -e SERVER_PORT="$SERVER_PORT" -e ADBKEY="$ADBKEY" \
  -v "$OUT:/out" -v "$HERE/runner-miot:/opt/runner-miot:ro" \
  test-runner /opt/runner-miot/run-ui-issues.sh

echo "[ui-issues] done → $OUT"
