import ActivityKit
import WidgetKit
import SwiftUI

struct SongloftLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SongloftMusicAttributes.self) { context in
            // 锁屏 Banner 视图
            LockScreenBannerView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded 视图
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "music.note")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text(context.attributes.songTitle)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(context.state.lyricLine.isEmpty ? context.attributes.artist : context.state.lyricLine)
                            .font(.body)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .foregroundColor(.primary)
                        if !context.state.nextLyricLine.isEmpty {
                            Text(context.state.nextLyricLine)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.progress)
                        .tint(.blue)
                        .padding(.horizontal, 8)
                }
            } compactLeading: {
                Image(systemName: "music.note")
                    .foregroundColor(.blue)
            } compactTrailing: {
                Text(context.state.lyricLine.isEmpty ? context.attributes.songTitle : context.state.lyricLine)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(maxWidth: 100)
            } minimal: {
                Image(systemName: "music.note")
                    .foregroundColor(.blue)
            }
        }
    }
}

/// 锁屏 Banner 视图
struct LockScreenBannerView: View {
    let context: ActivityViewContext<SongloftMusicAttributes>

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "music.note")
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.songTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(context.attributes.artist)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                    .foregroundColor(.secondary)
            }

            if !context.state.lyricLine.isEmpty {
                Text(context.state.lyricLine)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            ProgressView(value: context.state.progress)
                .tint(.blue)
        }
        .padding(16)
    }
}
