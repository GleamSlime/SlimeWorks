library;

/// PicACG 观看记录 ViewModel
///
/// 历史记录通过 Rust FFI 接口存取（基于 redb 本地数据库），
/// 比 SharedPreferences 更高效可靠，支持清除单条和全部

import 'dart:convert';

import 'package:get/get.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/src/rust/api/picacg.dart' as rust;

/// 单条观看记录数据
class PicAcgHistoryItem {
  final String comicId;
  final String comicTitle;
  final String thumbUrl;
  final int epsOrder;
  final String epsTitle;
  final int tick; // Unix 时间戳（秒）

  const PicAcgHistoryItem({
    required this.comicId,
    required this.comicTitle,
    required this.thumbUrl,
    required this.epsOrder,
    required this.epsTitle,
    required this.tick,
  });

  factory PicAcgHistoryItem.fromJson(Map<String, dynamic> json) => PicAcgHistoryItem(
    comicId: json['comicId'] as String? ?? '',
    comicTitle: json['comicTitle'] as String? ?? '',
    thumbUrl: json['thumbUrl'] as String? ?? '',
    epsOrder: json['epsOrder'] as int? ?? 1,
    epsTitle: json['epsTitle'] as String? ?? '',
    tick: json['tick'] as int? ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'comicId': comicId,
    'comicTitle': comicTitle,
    'thumbUrl': thumbUrl,
    'epsOrder': epsOrder,
    'epsTitle': epsTitle,
    'tick': tick,
  };
}

/// 观看记录最大保留条数
const int _kHistoryMaxCount = 200;

/// 观看记录 ViewModel
class PicAcgHistoryViewModel extends BaseViewModel {
  /// 当前所有观看记录（按时间倒序）
  final RxList<PicAcgHistoryItem> items = <PicAcgHistoryItem>[].obs;

  @override
  Future<void> onInit() async {
    super.onInit();
    await loadHistory();
  }

  /// 从 Rust 本地数据库加载历史记录
  Future<void> loadHistory() async {
    setLoading(true);
    try {
      final raw = rust.picacgLoadHistory();
      if (raw.isEmpty) {
        items.clear();
        clearError();
        return;
      }
      final list = jsonDecode(raw) as List<dynamic>;
      items.assignAll(list.map((e) => PicAcgHistoryItem.fromJson(e as Map<String, dynamic>)));
      clearError();
    } catch (e) {
      logger.error('加载观看记录失败: $e');
      setError('加载失败');
    } finally {
      setLoading(false);
    }
  }

  /// 删除单条记录
  Future<void> removeItem(String comicId) async {
    try {
      items.removeWhere((e) => e.comicId == comicId);
      await _persist();
    } catch (e) {
      logger.error('删除观看记录失败: $e');
    }
  }

  /// 清空全部记录
  Future<void> clearAll() async {
    try {
      items.clear();
      rust.picacgClearHistory();
    } catch (e) {
      logger.error('清空观看记录失败: $e');
    }
  }

  /// 将当前记录列表持久化到 Rust 数据库
  Future<void> _persist() async {
    final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
    rust.picacgSaveHistoryRaw(json: encoded);
  }

  // ==================== 静态工具方法（供 ReaderViewModel 调用） ====================

  /// 保存一条观看记录（调用方无需实例化 ViewModel）
  static Future<void> saveRecord({
    required String comicId,
    required String comicTitle,
    required String thumbUrl,
    required int epsOrder,
    required String epsTitle,
  }) async {
    try {
      final raw = rust.picacgLoadHistory();

      List<PicAcgHistoryItem> list = [];
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        list = decoded.map((e) => PicAcgHistoryItem.fromJson(e as Map<String, dynamic>)).toList();
      }

      /// 去重（同 comicId 的记录移除旧的）
      list.removeWhere((e) => e.comicId == comicId);

      final item = PicAcgHistoryItem(
        comicId: comicId,
        comicTitle: comicTitle,
        thumbUrl: thumbUrl,
        epsOrder: epsOrder,
        epsTitle: epsTitle,
        tick: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      /// 插入到最前
      list.insert(0, item);

      /// 超出上限时截断
      if (list.length > _kHistoryMaxCount) {
        list = list.sublist(0, _kHistoryMaxCount);
      }

      final encoded = jsonEncode(list.map((e) => e.toJson()).toList());
      rust.picacgSaveHistoryRaw(json: encoded);
      logger.info('保存观看记录成功: $comicTitle 第${epsOrder}话');
    } catch (e) {
      logger.error('保存观看记录失败: $e');
    }
  }
}
