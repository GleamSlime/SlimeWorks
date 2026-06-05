part of 'music_player_viewmodel.dart';

/// 远程节点音乐数据访问扩展
extension MusicPlayerVmRemote on MusicPlayerViewModel {
  /// 从远程节点获取播放列表
  Future<void> loadRemotePlaylists(String nodeId) async {
    isRemoteLoading.value = true;
    try {
      final response = await _nodeService.callNodeAction(
        nodeId: nodeId,
        action: 'music_list_playlists',
        params: {},
      );
      final dataList = response['data'] ?? response;
      if (dataList is List) {
        final remotePlaylists = dataList.map((p) {
          final map = p as Map<String, dynamic>;
          return music_api.Playlist(
            id: 'remote-music:${map['id']}',
            name: '[远程] ${map['name']}',
            coverPath: map['cover_path'] as String?,
            itemCount: BigInt.from(int.tryParse(map['item_count']?.toString() ?? '0') ?? 0),
            createdAt: (map['created_at'] as num?)?.toInt() ?? 0,
            updatedAt: (map['updated_at'] as num?)?.toInt() ?? 0,
            isDefault: map['is_default'] as bool? ?? false,
          );
        }).toList();
        playlists.addAll(remotePlaylists);
      }
    } catch (e) {
      _logger.info('[播放器] 从远程节点获取播放列表失败: $e');
    } finally {
      isRemoteLoading.value = false;
    }
  }

  /// 从远程节点获取播放列表内音乐
  Future<void> loadRemotePlaylistItems(String nodeId, String playlistId) async {
    isRemoteLoading.value = true;
    try {
      final response = await _nodeService.callNodeAction(
        nodeId: nodeId,
        action: 'music_get_playlist_items',
        params: {'playlist_id': playlistId},
      );
      final dataList = response['data'] ?? response;
      if (dataList is List) {
        final remoteItems = dataList.map((i) {
          final map = i as Map<String, dynamic>;
          return music_api.MusicItem(
            id: 'remote-music:${map['id']}',
            playlistId: 'remote-music:${map['playlist_id']}',
            title: map['title'] as String? ?? '',
            artist: map['artist'] as String?,
            album: map['album'] as String?,
            filePath: map['file_path'] as String? ?? '',
            durationMs: map['duration_ms'] == null
                ? null
                : BigInt.from(int.tryParse(map['duration_ms'].toString()) ?? 0),
            trackNumber: map['track_number'] as int?,
            discNumber: map['disc_number'] as int?,
            year: map['year'] as int?,
            genre: map['genre'] as String?,
            coverPath: map['cover_path'] as String?,
            fileSize: BigInt.from(int.tryParse(map['file_size']?.toString() ?? '0') ?? 0),
            modifiedAt: (map['modified_at'] as num?)?.toInt() ?? 0,
            order: map['order'] as int? ?? 0,
            isFavorite: map['is_favorite'] as bool? ?? false,
          );
        }).toList();
        currentItems.addAll(remoteItems);
      }
    } catch (e) {
      _logger.info('[播放器] 从远程节点获取音乐列表失败: $e');
    } finally {
      isRemoteLoading.value = false;
    }
  }

  /// 是否为远程播放列表
  bool isRemotePlaylist(String? playlistId) {
    return playlistId != null && playlistId.startsWith('remote-music:');
  }
}
