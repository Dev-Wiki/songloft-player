#!/usr/bin/env bash
# 在模拟器里驱动 miot 插件设置页，取四处 UI 的几何证据（宿主侧离线比对）：
#   A) 语音页「外部搜索源」两列表单行是否渲染（songloft-org/songloft-plugin-miot#79）
#   B) 定时页 SlSelect 下拉面板是否落在触发器下方（同上 #80）
#   C) 设备页登录二维码 <img> 的实际尺寸（同上 #80）
#   D) toast 宽度是否为 0（.toast 曾用 CSS min()，WebF 下等价 max-width:0）
# 每步都 screencap + uiautomator dump；判定一律看 dump 里的 bounds，不靠目视截图。
set -uo pipefail

SERIAL="${ANDROID_SERIAL:-emulator:5555}"
PACKAGE="${APP_PACKAGE:-com.songloft.songloft_flutter}"
SERVER_PORT="${SERVER_PORT:-58396}"
SERVER_HOST="${SERVER_HOST:-host.docker.internal}"
OUT=/out

if [ -n "${ADBKEY:-}" ]; then
  mkdir -p /root/.android
  printf '%s\n' "$ADBKEY" >/root/.android/adbkey
  chmod 600 /root/.android/adbkey
fi

# 单发 `adb connect` 会和模拟器的 adbd 起来的时机赛跑；必须像 runner/run-android-test.sh
# 那样重试到 get-state 真的变成 device，否则 wait-for-device 会永久挂住。
echo "[runner] waiting for emulator $SERIAL"
adb connect "$SERIAL" >/dev/null || true
for _ in $(seq 1 90); do
  adb -s "$SERIAL" get-state 2>/dev/null | grep -q '^device$' && break
  adb connect "$SERIAL" >/dev/null 2>&1 || true
  sleep 2
done
adb -s "$SERIAL" wait-for-device
for _ in $(seq 1 90); do
  [ "$(adb -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break
  sleep 2
done
[ "$(adb -s "$SERIAL" shell getprop sys.boot_completed | tr -d '\r')" = 1 ]

echo "[runner] deterministic display"
adb -s "$SERIAL" shell settings put global window_animation_scale 0
adb -s "$SERIAL" shell settings put global transition_animation_scale 0
adb -s "$SERIAL" shell settings put global animator_duration_scale 0
adb -s "$SERIAL" shell settings put system screen_off_timeout 1800000
adb -s "$SERIAL" shell settings put system system_locales zh-CN || true

socat "TCP-LISTEN:${SERVER_PORT},bind=127.0.0.1,reuseaddr,fork" "TCP:${SERVER_HOST}:${SERVER_PORT}" &
forward_pid=$!
trap 'kill "$forward_pid" 2>/dev/null || true' EXIT
adb -s "$SERIAL" reverse "tcp:${SERVER_PORT}" "tcp:${SERVER_PORT}"

shot() { # shot <name>
  adb -s "$SERIAL" exec-out screencap -p >"$OUT/$1.png" 2>/dev/null || true
  adb -s "$SERIAL" shell uiautomator dump "/sdcard/$1.xml" >/dev/null 2>&1 || true
  adb -s "$SERIAL" exec-out cat "/sdcard/$1.xml" >"$OUT/$1.xml" 2>/dev/null || true
  echo "[runner] captured $1"
}
wait_for_text() { python3 /opt/webf-android-runner/ui.py "$SERIAL" wait "$1" --timeout "${2:-30}"; }
click_text() { python3 /opt/webf-android-runner/ui.py "$SERIAL" click "$1"; }
# 滚动到目标真正完整可见再点（折叠线上的薄片点了不生效，见 tapnode.py 注释）
tap_node() { python3 /opt/runner-miot/tapnode.py "$SERIAL" "$1" "${2:-60}" "${3:-10}"; }
edit_field() {
  python3 /opt/webf-android-runner/ui.py "$SERIAL" click-nth android.widget.EditText --index "$1"
  sleep 1
  adb -s "$SERIAL" shell input text "$2"
}

echo "[runner] installing APK"
adb -s "$SERIAL" install -r -g "$OUT/songloft-x86_64-release.apk" >"$OUT/install.log" 2>&1
adb -s "$SERIAL" shell pm clear "$PACKAGE" >/dev/null
adb -s "$SERIAL" shell monkey -p "$PACKAGE" 1 >"$OUT/launch.log" 2>&1

echo "[runner] logging in"
python3 /opt/webf-android-runner/ui.py "$SERIAL" wait-count android.widget.EditText --count 3 --timeout 60
edit_field 0 admin
edit_field 1 admin
edit_field 2 "http://localhost:${SERVER_PORT}"
adb -s "$SERIAL" shell input keyevent 111
sleep 1
python3 - "$SERIAL" <<'PY'
import sys, subprocess, re, xml.etree.ElementTree as ET
serial = sys.argv[1]
subprocess.run(["adb","-s",serial,"shell","uiautomator","dump","/sdcard/lg.xml"],stdout=subprocess.DEVNULL)
raw = subprocess.check_output(["adb","-s",serial,"exec-out","cat","/sdcard/lg.xml"])
try: root = ET.fromstring(raw)
except ET.ParseError: sys.exit(0)
def bounds(n):
    m=re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.attrib.get("bounds",""))
    return tuple(map(int,m.groups())) if m else None
boxes=[(bounds(n), n.attrib.get("content-desc","")) for n in root.iter("node")
       if n.attrib.get("checkable")=="true" and bounds(n)]
target=None
for b,d in boxes:
    if any(k in d.lower() for k in ("agree","terms","privacy")): target=b; break
if target is None and boxes:
    boxes.sort(key=lambda x: x[0][2]-x[0][0]); target=boxes[0][0]
if target:
    l,t,r,bb=target
    subprocess.run(["adb","-s",serial,"shell","input","tap",str((l+r)//2),str((t+bb)//2)])
PY
sleep 1
click_text '^(登录|Log in)$'
if wait_for_text '^(稍后|Later)$' 25; then click_text '^(稍后|Later)$'; sleep 2; fi

echo "[runner] opening miot tab"
wait_for_text '智能音箱' 45
click_text '智能音箱'
sleep 10
shot 00-main

echo "[runner] opening plugin settings"
adb -s "$SERIAL" shell input tap 1010 100
sleep 4
shot 01-settings-root

# ---------- A) issue 79：语音页「外部搜索源」的名称/地址输入框 ----------
echo "[runner] === A) VoiceSettings external sources ==="
wait_for_text '^语音$' 25 || true
if tap_node '^语音$' 40 3; then
  sleep 6
  shot 10-voice-top
  # 用 --no-tap 模式滚到「添加搜索源」完整可见为止。固定步长的滑动不行：一次滑
  # 1200px 会整段跳过这个区块（实测直接滚到了后面的 AI 配置）。
  python3 /opt/runner-miot/tapnode.py "$SERIAL" '^添加搜索源$' 40 24 --no-tap || true
  shot 11-voice-sources
  adb -s "$SERIAL" shell input swipe 540 1400 540 1150 250; sleep 2
  shot 12-voice-sources-2
else
  echo "[runner] SKIP A: 语音 not found"
fi
adb -s "$SERIAL" shell input keyevent 4; sleep 3
shot 13-after-voice-back

# ---------- B) issue 80#2：定时页下拉面板翻转 ----------
echo "[runner] === B) ScheduleSettings dropdown placement ==="
adb -s "$SERIAL" shell input tap 1010 100; sleep 3
wait_for_text '^定时$' 25 || true
if tap_node '^定时$' 40 3; then
  sleep 5
  shot 20-schedule-top
  if click_text '^新建任务$'; then
    sleep 3
    shot 21-editor-open
    # resetEditor() 默认 action=play_playlist，「歌单」下拉本来就在，无需先改动作。
    # 表单整段在折叠线以下，tap_node 会自己滚到可见为止。
    if tap_node '^选择歌单$' 40 12; then
      sleep 3
      shot 22-playlist-panel-OPEN
      # E) 在面板内部滚动：面板本体若自己是滚动容器，WebF 会把它的 scrollTop 计入
      #    fixed 的绘制补偿，面板会整体往下跑（songloft-org/songloft#397）。
      #    判定 = 22 与 25 两份 dump 里，面板选项的 top 应保持一致（内容滚了、盒子没动）。
      adb -s "$SERIAL" shell input swipe 540 1300 540 1100 400; sleep 3
      shot 25-panel-after-inner-scroll
      adb -s "$SERIAL" shell input keyevent 4; sleep 2
      shot 23-panel-closed
    else
      echo "[runner] SKIP B: playlist select trigger not found"
    fi
    # 把触发器顶到更靠下的位置再开一次，看是否更严重
    adb -s "$SERIAL" shell input swipe 540 1400 540 1150 250; sleep 2
    if tap_node '^选择歌单$' 40 2; then
      sleep 3
      shot 24-playlist-panel-OPEN-lower
    fi
  fi
else
  echo "[runner] SKIP B: 定时 not found"
fi
adb -s "$SERIAL" shell input keyevent 4; sleep 2
adb -s "$SERIAL" shell input keyevent 4; sleep 3
shot 26-after-schedule-back

# ---------- C) issue 80#1：设备页二维码 ----------
echo "[runner] === C) DeviceSettings QR code ==="
adb -s "$SERIAL" shell input tap 1010 100; sleep 3
wait_for_text '^设备$' 25 || true
if tap_node '^设备$' 40 3; then
  sleep 5
  shot 30-device-top
  shot 31-qr-before
  if tap_node '^获取二维码$' 40 10; then
    sleep 12
    shot 32-qr-after
    sleep 12
    shot 33-qr-after-late
    # 二维码 <img> 在 WebF 里塌成 0 时截图上什么都看不到，所以把它滚到视野中间再拍一张
    adb -s "$SERIAL" shell input swipe 540 1400 540 1000 250; sleep 2
    shot 34-qr-scrolled
  else
    echo "[runner] SKIP C: 获取二维码 not tappable"
  fi
else
  echo "[runner] SKIP C: 设备 not found"
fi

# ---------- D) toast 是否零宽（.toast max-width: min() 同源修复） ----------
echo "[runner] === D) toast width ==="
if tap_node '^自动填充$' 40 8; then
  # notify 只显示 3.2s，dump 要紧跟着做
  adb -s "$SERIAL" shell uiautomator dump /sdcard/40-toast.xml >/dev/null 2>&1 || true
  adb -s "$SERIAL" exec-out cat /sdcard/40-toast.xml >"$OUT/40-toast.xml" 2>/dev/null || true
  adb -s "$SERIAL" exec-out screencap -p >"$OUT/40-toast.png" 2>/dev/null || true
  echo "[runner] captured 40-toast"
else
  echo "[runner] SKIP D: 自动填充 not tappable"
fi

# 插件页的 console.log 会以 `flutter : [plugin][console] ...` 形式进 logcat；
# 临时往前端塞探针查布局时直接读这个文件。
adb -s "$SERIAL" logcat -d 2>/dev/null | grep -a "\[plugin\]\[console\]" >"$OUT/page-console.txt" || true
echo "[runner] collecting logcat"
adb -s "$SERIAL" logcat -d >"$OUT/logcat.txt" 2>/dev/null || true
echo "[runner] ===== DONE ====="
