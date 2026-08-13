#!/usr/bin/env python3
"""把字体请求人为拖慢的透传代理，用来复现 WebF 的 @font-face 迟到竞态。

用法：slow-font-proxy.py <listen_port> <upstream_port> [delay_seconds]

只对路径以 .otf / .ttf / .woff / .woff2 结尾的请求 sleep，其余原样透传。
真实环境（远程 HTTPS 服务器）里字体就是这样比首屏布局晚到的。

**必须逐条请求检查**：WebF 走 Dio，连接 keep-alive 复用，字体往往是同一条 TCP
连接上的第 N 个请求。只看首行会永远漏掉它（第一版就是这么漏的，代理全程零命中）。
"""
import re
import socket
import socketserver
import sys
import threading
import time

LISTEN = int(sys.argv[1])
UPSTREAM = int(sys.argv[2])
DELAY = float(sys.argv[3]) if len(sys.argv) > 3 else 1.5
FONT_SUFFIXES = ('.otf', '.ttf', '.woff', '.woff2')
REQUEST_LINE = re.compile(rb'(GET|HEAD|POST|PUT|DELETE|OPTIONS) (\S+) HTTP/1\.[01]\r\n')
# 跨包拼接保留的尾巴长度，要大于任何一条请求行
OVERLAP = 2048


def is_font(path: bytes) -> bool:
    return path.split(b'?')[0].decode('latin-1').lower().endswith(FONT_SUFFIXES)


def pump_client(src, dst):
    """客户端 → 上游：边转发边逐条识别请求行，命中字体就先睡再转发。

    留 OVERLAP 字节的尾巴是为了让跨包切断的请求行也能被拼回来匹配上；但那段尾巴
    下一轮会被重新扫一遍，所以必须用绝对偏移记住「已经处理到哪」，否则同一条请求
    会被 sleep 两次，把人为延迟悄悄翻倍。
    """
    overlap = b''
    # 已消费字节数（不含 overlap），用来把 finditer 的相对位置换算成绝对位置
    base = 0
    handled_until = 0
    try:
        while True:
            chunk = src.recv(65536)
            if not chunk:
                break
            scan = overlap + chunk
            for match in REQUEST_LINE.finditer(scan):
                start = base + match.start()
                if start < handled_until:
                    continue
                handled_until = base + match.end()
                if is_font(match.group(2)):
                    print(f'[slow-font] delaying {match.group(2).decode("latin-1")}'
                          f' by {DELAY}s', flush=True)
                    time.sleep(DELAY)
            keep = min(OVERLAP, len(scan))
            base += len(scan) - keep
            overlap = scan[len(scan) - keep:] if keep else b''
            dst.sendall(chunk)
    except OSError:
        pass
    finally:
        try:
            dst.shutdown(socket.SHUT_WR)
        except OSError:
            pass


def pump(src, dst):
    try:
        while True:
            chunk = src.recv(65536)
            if not chunk:
                break
            dst.sendall(chunk)
    except OSError:
        pass
    finally:
        try:
            dst.shutdown(socket.SHUT_WR)
        except OSError:
            pass


class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        try:
            upstream = socket.create_connection(('127.0.0.1', UPSTREAM))
        except OSError as exc:
            print(f'[slow-font] upstream connect failed: {exc}', flush=True)
            return
        thread = threading.Thread(target=pump_client, args=(self.request, upstream), daemon=True)
        thread.start()
        pump(upstream, self.request)
        thread.join(timeout=5)
        upstream.close()


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == '__main__':
    print(f'[slow-font] 127.0.0.1:{LISTEN} -> 127.0.0.1:{UPSTREAM}, delay={DELAY}s', flush=True)
    Server(('127.0.0.1', LISTEN), Handler).serve_forever()
