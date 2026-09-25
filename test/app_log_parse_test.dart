// 应用日志 ViewModel 解析/过滤逻辑单测。
//
// 设计约束（不触发 FFI / 不读真实日志文件 / 不需要 RustLib.init）：
// - _parseLine / _normalizeLevel / _applyFilter 均为私有环节，
//   但 loadLogs 的公开管线是 "Loggers.allLogs(内存) → _parseLine → 排序 →
//   _applyFilter → entries"，因此用 Loggers().log(..., time:) 注入确定性
//   原始行即可端到端驱动解析逻辑；Rust 侧 getLogDir（FRB 未初始化）抛错
//   被吞、返回空列表，不影响断言。
// - Loggers._logs 是 isolate 内全局累加器，断言一律用唯一 marker 过滤，
//   不锁全局总数。
import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/view_models/sentry_log/app_log_viewmodel.dart';

/// 以固定时间戳向内存日志累加器注入一行，返回原始行文本。
String emitLog(String marker, {String name = 'APPT', int second = 0}) {
  return const Loggers().log(
    marker,
    name: name,
    time: DateTime(2024, 1, 2, 3, 4, 5 + second),
  );
}

/// 从当前 entries 中找到注入行的第一条。
AppLogEntry entryWithMarker(AppLogViewModel vm, String marker) {
  return vm.entries.firstWhere((e) => e.rawLine.contains(marker));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLogViewModel vm;

  setUp(() {
    vm = AppLogViewModel();
  });

  // ── _parseLine（经 loadLogs 公开管线） ────────────────────────────────────

  group('日志行解析', () {
    test('规范行：时间戳/级别/消息/来源逐字段解析', () async {
      final marker = 'alpha-parse-line';
      final raw = emitLog(marker, name: 'ERROR');
      await vm.loadLogs();

      final entry = entryWithMarker(vm, marker);
      expect(entry.source, 'dart');
      expect(entry.level, 'ERROR');
      expect(entry.rawTimestamp, '2024-01-02 03:04:05:00'); // 实测 flustars 毫秒段只出两位
      expect(entry.timestamp, DateTime(2024, 1, 2, 3, 4, 5));
      expect(entry.message, marker);
      expect(entry.rawLine, raw);
    });

    test('毫秒段被剥掉后再解析；时间不同的行按时间戳升序排列', () async {
      final lateMarker = 'beta-late-line';
      final earlyMarker = 'beta-early-line';
      emitLog(lateMarker, name: 'INFO', second: 0); // 03:04:05
      emitLog(earlyMarker, name: 'INFO', second: -2); // 03:04:03

      await vm.loadLogs();
      final timestamps = vm.entries.map((e) => e.timestamp).toList();
      // 全局排序单调不减
      for (var i = 1; i < timestamps.length; i++) {
        expect(timestamps[i].isBefore(timestamps[i - 1]), isFalse);
      }
      expect(
        entryWithMarker(vm, earlyMarker).timestamp,
        DateTime(2024, 1, 2, 3, 4, 3),
      );
      expect(
        entryWithMarker(vm, lateMarker).timestamp,
        DateTime(2024, 1, 2, 3, 4, 5),
      );
    });

    test('非 ASCII 标签行匹配失败 → 回退 INFO / 空 rawTimestamp / 整行为消息', () async {
      final marker = 'gamma-cjk-tag-line';
      final raw = emitLog(marker, name: '中文标签');
      await vm.loadLogs();

      final entry = entryWithMarker(vm, marker);
      expect(entry.level, 'INFO');
      expect(entry.rawTimestamp, isEmpty);
      expect(entry.message, raw); // 回退分支把整行（trim 后）当消息
      expect(entry.source, 'dart');
    });

    test('_normalizeLevel 归一：ERR→ERROR / WARNING→WARN / dbg→DEBUG / 未知保留', () async {
      final cases = {
        'delta-err-alias': 'ERR',
        'delta-warn-alias': 'WARNING',
        'delta-dbg-alias': 'dbg',
        'delta-info-alias': 'info',
        'delta-unknown-alias': 'LOG', // Loggers 默认标签，不归入四类
      };
      for (final e in cases.entries) {
        emitLog(e.key, name: e.value);
      }
      await vm.loadLogs();

      expect(entryWithMarker(vm, 'delta-err-alias').level, 'ERROR');
      expect(entryWithMarker(vm, 'delta-warn-alias').level, 'WARN');
      expect(entryWithMarker(vm, 'delta-dbg-alias').level, 'DEBUG');
      expect(entryWithMarker(vm, 'delta-info-alias').level, 'INFO');
      expect(entryWithMarker(vm, 'delta-unknown-alias').level, 'LOG');
    });
  });

  // ── _applyFilter（经 setLevelFilter / setSearchQuery / clearFilters） ──────

  group('过滤状态演化', () {
    late String errMarker;
    late String infoMarker;

    setUp(() async {
      errMarker = 'epsilon-err-row';
      infoMarker = 'epsilon-info-row';
      emitLog(errMarker, name: 'ERROR', second: 10);
      emitLog(infoMarker, name: 'INFO', second: 11);
      await vm.loadLogs();
    });

    test('未加载前设置过滤条件不崩、结果为空', () async {
      final fresh = AppLogViewModel();
      fresh.setSearchQuery('anything');
      fresh.setLevelFilter('ERROR');
      expect(fresh.entries, isEmpty);
    });

    test('级别过滤只留该级别且保留命中的 marker 行', () {
      vm.setLevelFilter('ERROR');
      expect(vm.entries.every((e) => e.level == 'ERROR'), isTrue);
      expect(vm.entries.any((e) => e.rawLine.contains(errMarker)), isTrue);
      expect(vm.entries.any((e) => e.rawLine.contains(infoMarker)), isFalse);
    });

    test('关键词过滤忽略大小写匹配 rawLine', () {
      // marker 是小写，用大写查询验证 lower-case 双侧归一
      vm.setSearchQuery(errMarker.toUpperCase());
      expect(vm.entries.every((e) => e.rawLine.contains(errMarker)), isTrue);
      expect(vm.entries, isNotEmpty);
    });

    test('级别 + 关键词叠加为交集；clearFilters 恢复全量', () {
      final all = vm.entries.length;
      vm.setLevelFilter('ERROR');
      final withErrOnly = vm.entries.length;
      expect(withErrOnly, lessThan(all));

      // 叠加一个只命中 INFO 行的关键词 → 交集为空
      vm.setSearchQuery(infoMarker);
      expect(vm.entries, isEmpty);

      vm.clearFilters();
      expect(vm.entries.length, all);
      expect(vm.searchQuery.value, isEmpty);
      expect(vm.selectedLevel.value, isEmpty);
    });

    test('过滤不重新解析：loadLogs 前改条件也能作用于已缓存 _allEntries', () async {
      vm.setLevelFilter('WARN');
      final warnCount = vm.entries.length;
      const newMarker = 'zeta-warn-row';
      emitLog(newMarker, name: 'WARN');
      // 未 loadLogs 时新增行不进入缓存 → 过滤结果不变
      expect(vm.entries.length, warnCount);
      await vm.loadLogs();
      // 行数只增不减（本 isolate 早前用例也可能贡献 WARN 行）
      expect(vm.entries.length, greaterThanOrEqualTo(warnCount + 1));
      expect(vm.entries.every((e) => e.level == 'WARN'), isTrue);
      expect(vm.entries.any((e) => e.rawLine.contains(newMarker)), isTrue);
    });
  });

  // ── 其他公开状态 ───────────────────────────────────────────────────────────

  group('加载与监听开关', () {
    test('loadLogs 首尾 isLoading 归位，重复加载幂等', () async {
      expect(vm.isLoading.value, isFalse);
      await vm.loadLogs();
      expect(vm.isLoading.value, isFalse);
      final first = vm.entries.length;
      await vm.loadLogs();
      expect(vm.entries.length, first); // 同一份累加器 → 行数不翻倍
    });

    test('startWatching / stopWatching 切换 isWatching（周期任务未触发即取消）', () {
      vm.startWatching();
      expect(vm.isWatching.value, isTrue);
      vm.startWatching(); // 幂等：重复启动不再建表
      expect(vm.isWatching.value, isTrue);
      vm.stopWatching();
      expect(vm.isWatching.value, isFalse);
    });

    test('getLevelColor 四级各有颜色，未知级别走默认灰', () {
      const kColor = Color(0xFF94A3B8);
      expect(vm.getLevelColor('ERROR'), const Color(0xFFEF4444));
      expect(vm.getLevelColor('WARN'), const Color(0xFFF59E0B));
      expect(vm.getLevelColor('DEBUG'), const Color(0xFF8B5CF6));
      expect(vm.getLevelColor('INFO'), const Color(0xFF22C55E));
      expect(vm.getLevelColor('LOG'), kColor);
    });
  });
}
