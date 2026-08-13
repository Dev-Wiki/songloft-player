#!/usr/bin/env bash
# miot 插件播放器控件渲染验证 runner（在 test-runner 容器内执行）
# 覆盖：① 底部播放器条三个控制按钮图标 ② 全屏播放器音量弹出层
set -euo pipefail

OUT=/out
SERIAL="${ANDROID_SERIAL:-emulator:5555}"
PACKAGE="${APP_PACKAGE:-com.songloft.songloft_flutter}"
SERVER_HOST="${SERVER_HOST:-host.docker.internal}"
SERVER_PORT="${SERVER_PORT:-58394}"
TAG="${SHOT_TAG:-before}"
mkdir -p "$OUT"

if [ -n "${ADBKEY:-}" ]; then
  mkdir -p /root/.android
  printf '%s\n' "$ADBKEY" >/root/.android/adbkey
  chmod 600 /root/.android/adbkey
fi

echo "[icons] waiting for emulator $SERIAL"
adb connect "$SERIAL" >/dev/null || true
for _ in $(seq 1 90); do
  adb -s "$SERIAL" get-state 2>/dev/null | grep -q '^device$' && break
  adb connect "$SERIAL" >/dev/null 2>&1 || true
  sleep 2
done
adb -s "$SERIAL" wait-for-device
for _ in $(seq 1 180); do
  [ "$(adb -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break
  sleep 2
done
# 这条断言不能省：等待循环超时后会直接落下来，紧接着的 `settings put` 在半启动的
# 系统上失败，`set -e` 让整个脚本在一片空输出里退出，极难归因。冷启的模拟器偶尔
# 会超过 3 分钟（tmpfs /data 每次都是全新的），所以上面给到 360s。
if [ "$(adb -s "$SERIAL" shell getprop sys.boot_completed | tr -d '\r')" != 1 ]; then
  echo "[icons] emulator did not finish booting" >&2
  exit 1
fi

adb -s "$SERIAL" shell settings put global window_animation_scale 0
adb -s "$SERIAL" shell settings put global transition_animation_scale 0
adb -s "$SERIAL" shell settings put global animator_duration_scale 0
adb -s "$SERIAL" shell settings put system screen_off_timeout 1800000
adb -s "$SERIAL" shell wm size 1080x2400

# SLOW_FONT=<秒>：设备 → 慢字体代理(127.0.0.1:PORT) → socat(PORT+1) → 宿主后端。
# 只有 .otf 请求被 sleep，用来复现「字体比首屏布局晚到」的 WebF 竞态。
SOCAT_PORT="$SERVER_PORT"
proxy_pid=''
if [ -n "${SLOW_FONT:-}" ]; then SOCAT_PORT=$((SERVER_PORT + 1)); fi
socat "TCP-LISTEN:${SOCAT_PORT},bind=127.0.0.1,reuseaddr,fork" "TCP:${SERVER_HOST}:${SERVER_PORT}" &
forward_pid=$!
if [ -n "${SLOW_FONT:-}" ]; then
  python3 /opt/runner-miot/slow-font-proxy.py "$SERVER_PORT" "$SOCAT_PORT" "$SLOW_FONT" \
    >"$OUT/slow-font-$TAG.log" 2>&1 &
  proxy_pid=$!
  sleep 1
fi
# 不能写成 kill "$forward_pid" "$proxy_pid" —— 没开慢字体代理时 proxy_pid 是空串，
# kill 会收到一个空参数并报错。
trap 'for pid in $forward_pid $proxy_pid; do kill "$pid" 2>/dev/null || true; done' EXIT
adb -s "$SERIAL" reverse "tcp:${SERVER_PORT}" "tcp:${SERVER_PORT}"

echo "[icons] installing APK"
adb -s "$SERIAL" install -r -g "$OUT/songloft-x86_64-release.apk" >"$OUT/install-$TAG.log" 2>&1
adb -s "$SERIAL" shell pm clear "$PACKAGE" >/dev/null
adb -s "$SERIAL" shell monkey -p "$PACKAGE" 1 >"$OUT/launch-$TAG.log" 2>&1

UI=/opt/webf-android-runner/ui.py
wait_for_text() { python3 "$UI" "$SERIAL" wait "$1" --timeout "${2:-30}"; }
click_text() { python3 "$UI" "$SERIAL" click "$1"; }
edit_field() {
  python3 "$UI" "$SERIAL" click-nth android.widget.EditText --index "$1"
  sleep 1
  adb -s "$SERIAL" shell input text "$2"
}
shot() { adb -s "$SERIAL" exec-out screencap -p >"$OUT/$1"; echo "[icons] captured $1"; }
dumpui() {
  adb -s "$SERIAL" shell uiautomator dump "/sdcard/$1.xml" >/dev/null 2>&1 || true
  adb -s "$SERIAL" exec-out cat "/sdcard/$1.xml" >"$OUT/$1.xml" 2>/dev/null || true
}

echo "[icons] logging in"
python3 "$UI" "$SERIAL" wait-count android.widget.EditText --count 3 --timeout 60
edit_field 0 admin
edit_field 1 admin
edit_field 2 "http://localhost:${SERVER_PORT}"
adb -s "$SERIAL" shell input keyevent 111
sleep 1
python3 - "$SERIAL" <<'PY'
import sys, subprocess, re, xml.etree.ElementTree as ET
serial = sys.argv[1]
subprocess.run(["adb","-s",serial,"shell","uiautomator","dump","/sdcard/lg.xml"],
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
raw = subprocess.check_output(["adb","-s",serial,"exec-out","cat","/sdcard/lg.xml"])
try: root = ET.fromstring(raw)
except ET.ParseError: sys.exit(0)
def bounds(n):
    m = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.attrib.get("bounds",""))
    return tuple(map(int, m.groups())) if m else None
boxes = [(bounds(n), n.attrib.get("content-desc",""))
         for n in root.iter("node") if n.attrib.get("checkable") == "true"]
boxes = [b for b in boxes if b[0]]
target = next((b for b, d in boxes if any(k in d.lower() for k in ("agree","terms","privacy"))), None)
if target is None and boxes:
    boxes.sort(key=lambda x: x[0][2] - x[0][0])
    target = boxes[0][0]
if target:
    l, t, r, bb = target
    subprocess.run(["adb","-s",serial,"shell","input","tap",str((l+r)//2),str((t+bb)//2)])
PY
sleep 1
click_text '^(登录|Log in)$'

if wait_for_text '^(稍后|Later)$' 25; then click_text '^(稍后|Later)$'; sleep 2; fi

echo "[icons] opening miot tab"
wait_for_text '智能音箱' 45
click_text '智能音箱'
# 首屏连拍：字体迟到竞态只在最初几秒可见，settle 之后的截图会掩盖它
for i in 1 2 3 4; do
  sleep 2
  shot "icons-$TAG-boot$i.png"
done
sleep 3

# ① 底部播放器条（mock 设备已注入，player-bar 应可见）
shot "icons-$TAG-bar.png"
dumpui "icons-$TAG-bar"

# 裁出播放器条区域放大，便于肉眼核对三个控制按钮
python3 - "$OUT/icons-$TAG-bar.png" "$OUT/icons-$TAG-bar-crop.png" <<'PYEOF'
import sys
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert('RGB')
w, h = im.size
# 播放器条位于底部导航栏之上
box = (0, max(0, h - 600), w, max(0, h - 280))
crop = im.crop(box)
crop.resize((crop.width * 2, crop.height * 2), Image.NEAREST).save(dst)
print('cropped', box)
PYEOF

# ② 全屏播放器：点播放条左侧信息区展开
echo "[icons] opening fullscreen player"
click_text '测试歌曲标题' || adb -s "$SERIAL" shell input tap 300 1960
sleep 6
shot "icons-$TAG-full.png"
dumpui "icons-$TAG-full"

# ③ 全屏播放器音量弹出层
echo "[icons] opening volume popup"
click_text '^音量$' || true
sleep 3
shot "icons-$TAG-volume.png"
dumpui "icons-$TAG-volume"

# ④ 关掉音量层与播放器，回主页（对应 issue 里「图标又正常了」）
echo "[icons] closing popup + player"
adb -s "$SERIAL" shell input keyevent 4
sleep 2
adb -s "$SERIAL" shell input keyevent 4
sleep 4
shot "icons-$TAG-back-main.png"
dumpui "icons-$TAG-back-main"

# ⑤ 再次打开播放器（对应 issue 里「图标都不见了」）
echo "[icons] reopening fullscreen player"
click_text '测试歌曲标题' || adb -s "$SERIAL" shell input tap 300 1960
sleep 6
shot "icons-$TAG-full2.png"
dumpui "icons-$TAG-full2"

adb -s "$SERIAL" logcat -d >"$OUT/icons-$TAG-logcat.txt" 2>/dev/null || true
echo "[icons] done"
ls -la "$OUT"/icons-"$TAG"-*.png
