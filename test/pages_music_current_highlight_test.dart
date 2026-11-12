// P2-3 + P3-5：播放器「当前曲目」判据。
//
// 旧判据是 currentIndex.value == currentItems.indexOf(item)。
// 列表渲染的是 filteredItems（搜索过滤后的子集），两个列表长度/顺序都可能不同：
// 找不到条目时 indexOf 返回 -1，若此时 currentIndex 也恰好是 -1，
// 比较成立 → 整屏每一行都被点亮。
//
// 新判据按 id 比：currentItems[currentIndex]?.id == row.id。
import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/pages/music_player/music_player_screen.dart';
import 'package:slime_works/src/rust/api/music_player.dart' as music_api;

music_api.MusicItem song(String id) => music_api.MusicItem(
  id: id,
  playlistId: 'p1',
  title: id,
  filePath: '/tmp/$id.mp3',
  fileSize: BigInt.from(1),
  modifiedAt: 0,
  order: 0,
  isFavorite: false,
  hasCue: false,
);

void main() {
  final queue = <music_api.MusicItem>[song('a'), song('b'), song('c')];

  group('currentMusicItemId', () {
    test('正常下标取对应 id', () {
      expect(currentMusicItemId(0, queue), 'a');
      expect(currentMusicItemId(2, queue), 'c');
    });

    test('无选中（-1）返回 null：不能被当成"匹配到第 -1 条"', () {
      expect(currentMusicItemId(-1, queue), isNull);
    });

    test('越界返回 null（切列表/删歌后 currentIndex 可能超出新长度）', () {
      expect(currentMusicItemId(3, queue), isNull);
      expect(currentMusicItemId(99, queue), isNull);
      expect(currentMusicItemId(0, const <music_api.MusicItem>[]), isNull);
    });
  });

  group('高亮判定（按 id 而非 indexOf 下标）', () {
    bool isCurrent(int index, List<music_api.MusicItem> items, String rowId) {
      final id = currentMusicItemId(index, items);
      return id != null && id == rowId;
    }

    test('搜索态：过滤后的列表里每行按自己的 id 判高亮', () {
      // 用户在搜索，列表只剩 c，而队列仍是 a/b/c 且正在放 b
      final filtered = <music_api.MusicItem>[song('c')];
      expect(isCurrent(1, queue, filtered[0].id), isFalse);
      expect(isCurrent(1, queue, 'b'), isTrue);
    });

    test('全空态不会把所有行误判成当前曲目（旧判据的 -1 == -1 陷阱）', () {
      // currentIndex 与 indexOf 同时为 -1 时，旧判据会把任意行判成当前曲目
      for (final it in queue) {
        final oldStyle = !queue.contains(song('zzz'));
        expect(oldStyle, isTrue, reason: '这就是旧判据的误判来源');
        expect(isCurrent(-1, queue, it.id), isFalse, reason: '新判据必须为 false');
      }
    });

    test('切歌后高亮随 id 迁移', () {
      expect(isCurrent(0, queue, 'a'), isTrue);
      expect(isCurrent(0, queue, 'b'), isFalse);
      expect(isCurrent(1, queue, 'a'), isFalse);
      expect(isCurrent(1, queue, 'b'), isTrue);
    });
  });
}
