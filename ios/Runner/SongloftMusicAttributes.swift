#if canImport(ActivityKit)
import ActivityKit

/// Live Activity 数据模型
struct SongloftMusicAttributes: ActivityAttributes {
    /// 动态内容（随播放实时变化）
    public struct ContentState: Codable, Hashable {
        var lyricLine: String
        var nextLyricLine: String
        var isPlaying: Bool
        var progress: Double
    }

    /// 静态内容（Activity 创建时设定）
    var songTitle: String
    var artist: String
}
#endif
