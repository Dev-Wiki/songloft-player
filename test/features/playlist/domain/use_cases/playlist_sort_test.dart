import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/playlist/domain/use_cases/playlist_sort.dart';
import 'package:songloft_flutter/features/playlist/domain/playlist.dart';

Playlist _playlist(int id, String name) => Playlist(
  id: id,
  type: 'normal',
  name: name,
  createdAt: DateTime(2024, 1, 1),
  updatedAt: DateTime(2024, 1, 1),
);

void main() {
  group('extractLeadingNumber', () {
    test('extracts number from beginning', () {
      expect(extractLeadingNumber('03. 歌名'), 3);
    });

    test('returns null when no number present', () {
      expect(extractLeadingNumber('歌名'), null);
    });

    test('extracts number followed by letters', () {
      expect(extractLeadingNumber('12abc'), 12);
    });

    test('extracts first number when multiple present', () {
      expect(extractLeadingNumber('01. Track 02'), 1);
    });

    test('handles number in the middle', () {
      expect(extractLeadingNumber('干得漂亮 | 01 好意被辜负'), 1);
    });

    test('returns null for empty string', () {
      expect(extractLeadingNumber(''), null);
    });
  });

  group('PlaylistSort', () {
    late PlaylistSort sorter;

    setUp(() {
      sorter = PlaylistSort();
    });

    group('sortPlaylistsByName', () {
      test('sorts ascending', () {
        final playlists = [
          _playlist(1, 'Rock'),
          _playlist(2, 'Jazz'),
          _playlist(3, 'Pop'),
        ];

        final result = sorter.sortPlaylistsByName(playlists);

        expect(result, [2, 3, 1]); // Jazz, Pop, Rock
      });

      test('sorts descending', () {
        final playlists = [
          _playlist(1, 'Jazz'),
          _playlist(2, 'Rock'),
          _playlist(3, 'Pop'),
        ];

        final result = sorter.sortPlaylistsByName(playlists, ascending: false);

        expect(result, [2, 3, 1]); // Rock, Pop, Jazz
      });

      test('returns null when already sorted', () {
        final playlists = [
          _playlist(1, 'Apple'),
          _playlist(2, 'Banana'),
          _playlist(3, 'Cherry'),
        ];

        final result = sorter.sortPlaylistsByName(playlists);

        expect(result, isNull);
      });

      test('case insensitive', () {
        final playlists = [_playlist(1, 'banana'), _playlist(2, 'Apple')];

        final result = sorter.sortPlaylistsByName(playlists);

        expect(result, [2, 1]);
      });
    });

    group('sortPlaylistsByNumberPrefix', () {
      test('sorts by number prefix', () {
        final playlists = [
          _playlist(1, '03. Third'),
          _playlist(2, '01. First'),
          _playlist(3, '02. Second'),
        ];

        final result = sorter.sortPlaylistsByNumberPrefix(playlists);

        expect(result, [2, 3, 1]);
      });

      test('playlists with numbers before those without', () {
        final playlists = [
          _playlist(1, 'No Number'),
          _playlist(2, '01. Has Number'),
        ];

        final result = sorter.sortPlaylistsByNumberPrefix(playlists);

        expect(result, [2, 1]);
      });

      test('returns null when already sorted', () {
        final playlists = [
          _playlist(1, '01. First'),
          _playlist(2, '02. Second'),
          _playlist(3, 'Zebra'),
        ];

        final result = sorter.sortPlaylistsByNumberPrefix(playlists);

        expect(result, isNull);
      });
    });

    group('custom compareStrings', () {
      test('custom comparator is used for sortPlaylistsByName', () {
        // 按字符串长度排序
        final lengthSorter = PlaylistSort(
          compareStrings: (a, b) => a.length.compareTo(b.length),
        );

        final playlists = [
          _playlist(1, 'Long Name Here'),
          _playlist(2, 'Hi'),
          _playlist(3, 'Medium'),
        ];

        // 按长度：Hi(2), Medium(6), Long Name Here(14)
        final result = lengthSorter.sortPlaylistsByName(playlists);

        expect(result, [2, 3, 1]);
      });

      test('pinyin comparator works with mixed Chinese and English', () {
        final pinyinMap = {'我': 'wo', '的': 'de', '歌': 'ge'};

        String toPinyin(String s) {
          final buffer = StringBuffer();
          for (var i = 0; i < s.length; i++) {
            final char = s[i];
            buffer.write(pinyinMap[char] ?? char);
          }
          return buffer.toString();
        }

        final pinyinSorter = PlaylistSort(
          compareStrings:
              (a, b) => toPinyin(
                a,
              ).toLowerCase().compareTo(toPinyin(b).toLowerCase()),
        );

        final playlists = [
          _playlist(1, '我的歌'), // wodege
          _playlist(2, 'Apple'), // apple
          _playlist(3, '歌'), // ge
        ];

        // 拼音序：Apple(apple) < 歌(ge) < 我的歌(wodege)
        final result = pinyinSorter.sortPlaylistsByName(playlists);

        expect(result, [2, 3, 1]);
      });
    });
  });
}
