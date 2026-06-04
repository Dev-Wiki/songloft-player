import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/lyric_cache_service.dart';
import '../../../../core/utils/url_helper.dart';
import '../../domain/lyric_parser.dart';
import 'player_provider.dart';

/// 歌词状态
class LyricState {
  final List<LyricLine> lyrics;
  final int currentIndex;
  final bool isLoading;
  final bool loadFailed;
  final String? rawLyricText;

  const LyricState({
    this.lyrics = const [],
    this.currentIndex = -1,
    this.isLoading = false,
    this.loadFailed = false,
    this.rawLyricText,
  });

  String get currentLyricText {
    if (currentIndex < 0 || currentIndex >= lyrics.length) return '';
    return lyrics[currentIndex].text;
  }

  String get nextLyricText {
    final next = currentIndex + 1;
    if (next < 0 || next >= lyrics.length) return '';
    return lyrics[next].text;
  }

  bool get hasLyrics => lyrics.isNotEmpty;

  LyricState copyWith({
    List<LyricLine>? lyrics,
    int? currentIndex,
    bool? isLoading,
    bool? loadFailed,
    String? rawLyricText,
    bool clearRawLyricText = false,
  }) {
    return LyricState(
      lyrics: lyrics ?? this.lyrics,
      currentIndex: currentIndex ?? this.currentIndex,
      isLoading: isLoading ?? this.isLoading,
      loadFailed: loadFailed ?? this.loadFailed,
      rawLyricText:
          clearRawLyricText ? null : (rawLyricText ?? this.rawLyricText),
    );
  }
}

/// 歌词状态 Provider
///
/// 监听当前歌曲变化自动加载歌词，监听播放进度自动追踪当前行。
/// 仅在歌词行变化时通知下游，避免高频更新。
final lyricStateProvider = NotifierProvider<LyricNotifier, LyricState>(
  LyricNotifier.new,
);

class LyricNotifier extends Notifier<LyricState> {
  String? _lastLoadedUrl;
  StreamSubscription<dynamic>? _playerSub;

  @override
  LyricState build() {
    ref.listen(playerStateProvider.select((s) => s.currentSong?.lyricUrl), (
      prev,
      next,
    ) {
      if (prev != next) _loadLyrics(next);
    });

    ref.listen(playerStateProvider.select((s) => s.currentTime), (prev, next) {
      _updateCurrentLine(next);
    });

    ref.onDispose(() {
      _playerSub?.cancel();
    });

    final lyricUrl = ref.read(playerStateProvider).currentSong?.lyricUrl;
    if (lyricUrl != null && lyricUrl.isNotEmpty) {
      Future.microtask(() => _loadLyrics(lyricUrl));
    }

    return const LyricState();
  }

  void _updateCurrentLine(Duration position) {
    if (state.lyrics.isEmpty) return;
    final newIndex = LyricParser.findCurrentLine(state.lyrics, position);
    if (newIndex != state.currentIndex) {
      state = state.copyWith(currentIndex: newIndex);
    }
  }

  Future<void> _loadLyrics(String? lyricUrl) async {
    if (lyricUrl == null || lyricUrl.isEmpty) {
      _lastLoadedUrl = null;
      state = const LyricState();
      return;
    }

    if (_lastLoadedUrl == lyricUrl && state.hasLyrics) return;

    state = state.copyWith(
      isLoading: true,
      loadFailed: false,
      lyrics: [],
      currentIndex: -1,
    );

    final cached = await LyricCacheService().get(lyricUrl);
    if (cached != null) {
      _lastLoadedUrl = lyricUrl;
      final lyrics = LyricParser.parse(cached);
      final position = ref.read(playerStateProvider).currentTime;
      final index = LyricParser.findCurrentLine(lyrics, position);
      state = LyricState(
        lyrics: lyrics,
        currentIndex: index,
        rawLyricText: cached,
      );
      return;
    }

    try {
      final fullUrl = UrlHelper.buildLyricUrl(lyricUrl);
      final response = await Dio().get<Map<String, dynamic>>(fullUrl);

      String lyricText = '';
      final body = response.data;
      if (body is Map<String, dynamic>) {
        final main = body['lyric'];
        if (main is String) lyricText = main;
      }

      _lastLoadedUrl = lyricUrl;
      final lyrics = LyricParser.parse(lyricText);
      final position = ref.read(playerStateProvider).currentTime;
      final index = LyricParser.findCurrentLine(lyrics, position);
      state = LyricState(
        lyrics: lyrics,
        currentIndex: index,
        rawLyricText: lyricText,
      );

      if (lyricText.isNotEmpty) {
        await LyricCacheService().put(lyricUrl, lyricText);
      }
    } catch (e) {
      debugPrint('[LyricProvider] Failed to load lyric: $e');
      state = state.copyWith(isLoading: false, loadFailed: true);
    }
  }

  /// 强制重新加载歌词（歌词调整后调用）
  void invalidate() {
    _lastLoadedUrl = null;
    final lyricUrl = ref.read(playerStateProvider).currentSong?.lyricUrl;
    _loadLyrics(lyricUrl);
  }
}

/// 便捷 Provider：当前歌词行文本
final currentLyricTextProvider = Provider<String>((ref) {
  return ref.watch(lyricStateProvider).currentLyricText;
});

/// 便捷 Provider：下一行歌词文本
final nextLyricTextProvider = Provider<String>((ref) {
  return ref.watch(lyricStateProvider).nextLyricText;
});
