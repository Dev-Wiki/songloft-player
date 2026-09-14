import 'dart:io';

/// 探测本机在局域网内可被外部设备访问的 IPv4 地址。
///
/// 用于 Bundle 本地模式下把投屏等需要离开本机的 URL 的 host（`127.0.0.1`）
/// 替换成真正可路由的局域网地址——回环地址只在本机进程间有效，DLNA 渲染器
/// （如小爱音箱）拿到 127.0.0.1 只会请求到它自己。
class LanAddress {
  /// 返回一个私有地址段（10.x / 172.16-31.x / 192.168.x）的 IPv4 地址，
  /// 找不到时返回 null（调用方应原样兜底，而不是抛错中断投屏）。
  static Future<String?> resolve() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (_isPrivate(addr.address)) return addr.address;
        }
      }
    } catch (_) {
      // 部分平台/沙盒环境下枚举网卡可能失败，交由调用方兜底。
    }
    return null;
  }

  static bool _isPrivate(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final octets = parts.map(int.tryParse).toList();
    if (octets.any((o) => o == null)) return false;
    final a = octets[0]!, b = octets[1]!;
    if (a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    return false;
  }
}
