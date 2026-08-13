#!/usr/bin/env python3
"""按 content-desc 正则找节点并点它的中心；节点被折叠/裁切时先滚动再重试。

WebF 页面的视口只到宿主底部导航栏为止（1080x2400 上约 y<1612），落在折叠线上的
按钮在 uiautomator 里会是个高度只有十几 px 的薄片 —— 直接点它不会触发任何事件，
而 dump 里明明有这段文字，很容易误判成「点了没反应」。所以这里强制要求节点高度
达到 min-height 才认为可点。
"""
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

BOUNDS = re.compile(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]")


def dump(serial: str):
    subprocess.run(["adb", "-s", serial, "shell", "uiautomator", "dump", "/sdcard/_tn.xml"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    raw = subprocess.run(["adb", "-s", serial, "exec-out", "cat", "/sdcard/_tn.xml"],
                         stdout=subprocess.PIPE).stdout
    try:
        return ET.fromstring(raw)
    except ET.ParseError:
        return None


def find(root, pattern: str):
    rx = re.compile(pattern)
    hits = []
    for n in root.iter("node"):
        m = BOUNDS.fullmatch(n.attrib.get("bounds", ""))
        if not m:
            continue
        desc = n.attrib.get("content-desc", "") or n.attrib.get("text", "")
        if not rx.search(desc):
            continue
        l, t, r, b = map(int, m.groups())
        hits.append((l, t, r, b, desc))
    # 同一个控件会有 Button + 内层 View 多条同名节点，取面积最大的那条最稳
    hits.sort(key=lambda h: (h[2] - h[0]) * (h[3] - h[1]), reverse=True)
    return hits


def main() -> int:
    argv = [a for a in sys.argv[1:] if a != "--no-tap"]
    no_tap = "--no-tap" in sys.argv
    serial, pattern = argv[0], argv[1]
    min_h = int(argv[2]) if len(argv) > 2 else 60
    max_swipes = int(argv[3]) if len(argv) > 3 else 10
    # WebF 页面视口的上下边界（状态栏 / 宿主底部导航栏）。节点必须整体落在里面，
    # 否则就是折叠线上的薄片，点了不生效。文字节点的自然高度只有 55px，所以判定
    # 用「上下边界 + 最小高度」两条，不能只看高度。
    top_limit, bottom_limit = 180, 1600
    for attempt in range(max_swipes + 1):
        root = dump(serial)
        if root is not None:
            hits = find(root, pattern)
            visible = [h for h in hits
                       if (h[3] - h[1]) >= min_h and h[1] >= top_limit and h[3] <= bottom_limit]
            if visible:
                l, t, r, b, desc = visible[0]
                x, y = (l + r) // 2, (t + b) // 2
                if no_tap:
                    print(f"reached '{desc}' at ({x},{y}) size={r-l}x{b-t} after {attempt} swipes")
                    return 0
                subprocess.run(["adb", "-s", serial, "shell", "input", "tap", str(x), str(y)])
                print(f"tapped '{desc}' at ({x},{y}) size={r-l}x{b-t} after {attempt} swipes")
                return 0
            if hits:
                l, t, r, b, _ = hits[0]
                print(f"  '{pattern}' present but clipped ({r-l}x{b-t} @{t}); scrolling")
        if attempt < max_swipes:
            subprocess.run(["adb", "-s", serial, "shell", "input", "swipe", "540", "1400", "540", "1000", "250"])
            time.sleep(1.5)
    print(f"NOT FOUND (or never fully visible): {pattern}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
