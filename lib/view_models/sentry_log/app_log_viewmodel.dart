import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/src/rust/api/logger.dart';

class AppLogEntry {
  final DateTime timestamp;
  final String rawTimestamp;
  final String level;
  final String message;
  final String source;
  final String rawLine;

  AppLogEntry({
    required this.timestamp,
    required this.rawTimestamp,
    required this.level,
    required this.message,
    required this.source,
    required this.rawLine,
  });
}

class AppLogViewModel extends GetxController {
  final RxList<AppLogEntry> entries = <AppLogEntry>[].obs;
  final RxBool isLoading = false.obs;
  final RxString searchQuery = ''.obs;
  final RxString selectedLevel = ''.obs;
  final RxBool autoScroll = true.obs;
  final RxBool isWatching = false.obs;

  ScrollController? scrollController;

  List<AppLogEntry> _allEntries = [];
  Timer? _refreshTimer;

  @override
  void onInit() {
    super.onInit();
    scrollController = ScrollController();
  }

  @override
  void onClose() {
    _refreshTimer?.cancel();
    scrollController?.dispose();
    super.onClose();
  }

  Future<void> loadLogs() async {
    isLoading.value = true;
    try {
      final dartLogs = Loggers.allLogs.toList();
      final rustLogs = await _loadRustLogs();

      final dartEntries = dartLogs.map((line) => _parseLine(line, source: 'dart')).toList();
      final rustEntries = rustLogs.map((line) => _parseLine(line, source: 'rust')).toList();

      _allEntries = [...dartEntries, ...rustEntries];
      _allEntries.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      entries.value = _applyFilter(_allEntries);
    } catch (e) {
      logger.error('加载应用日志失败: $e');
    } finally {
      isLoading.value = false;
    }
  }

  void startWatching() {
    if (isWatching.value) return;
    isWatching.value = true;

    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _pollNewLogs();
    });
  }

  void stopWatching() {
    isWatching.value = false;
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> _pollNewLogs() async {
    try {
      final dartLogs = Loggers.allLogs.toList();
      final rustLogs = await _loadRustLogs();

      final dartEntries = dartLogs.map((line) => _parseLine(line, source: 'dart')).toList();
      final rustEntries = rustLogs.map((line) => _parseLine(line, source: 'rust')).toList();

      _allEntries = [...dartEntries, ...rustEntries];
      _allEntries.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      final filtered = _applyFilter(_allEntries);
      final hadEntries = entries.length;
      entries.value = filtered;

      if (autoScroll.value && filtered.length > hadEntries && scrollController != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scrollController!.hasClients) {
            scrollController!.animateTo(
              scrollController!.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (_) {}
  }

  Future<List<String>> _loadRustLogs() async {
    try {
      final logDir = await getLogDir();
      if (logDir == null || logDir.isEmpty) return [];

      final date = DateTime.now();
      final dateStr =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final filePath = '$logDir/slime_works_$dateStr.log';

      final file = File(filePath);
      if (!await file.exists()) return [];

      final content = await file.readAsString();
      return content.split('\n').where((line) => line.trim().isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  AppLogEntry _parseLine(String line, {required String source}) {
    final regex = RegExp(
      r'^(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}(?:[:.]\d+)?)\s+\[?(\w+)\]?\s+(.*)$',
    );
    final match = regex.matchAsPrefix(line);

    if (match != null) {
      final tsStr = match.group(1) ?? '';
      final level = match.group(2)?.toUpperCase() ?? 'INFO';
      final message = match.group(3) ?? line;

      DateTime ts;
      try {
        final clean = tsStr.replaceAll(RegExp(r'[:.]\d+$'), '');
        ts = DateTime.parse(clean);
      } catch (_) {
        ts = DateTime.now();
      }

      return AppLogEntry(
        timestamp: ts,
        rawTimestamp: tsStr,
        level: _normalizeLevel(level),
        message: message.trim(),
        source: source,
        rawLine: line,
      );
    }

    return AppLogEntry(
      timestamp: DateTime.now(),
      rawTimestamp: '',
      level: 'INFO',
      message: line.trim(),
      source: source,
      rawLine: line,
    );
  }

  String _normalizeLevel(String level) {
    final l = level.toUpperCase();
    if (l.contains('ERROR') || l.contains('ERR')) return 'ERROR';
    if (l.contains('WARN')) return 'WARN';
    if (l.contains('DEBUG') || l.contains('DBG')) return 'DEBUG';
    if (l.contains('INFO')) return 'INFO';
    return l;
  }

  List<AppLogEntry> _applyFilter(List<AppLogEntry> all) {
    var result = all;
    if (selectedLevel.value.isNotEmpty) {
      result = result.where((e) => e.level == selectedLevel.value).toList();
    }
    if (searchQuery.value.isNotEmpty) {
      final q = searchQuery.value.toLowerCase();
      result = result.where((e) => e.rawLine.toLowerCase().contains(q)).toList();
    }
    return result;
  }

  void setSearchQuery(String query) {
    searchQuery.value = query;
    entries.value = _applyFilter(_allEntries);
  }

  void setLevelFilter(String level) {
    selectedLevel.value = level;
    entries.value = _applyFilter(_allEntries);
  }

  void clearFilters() {
    searchQuery.value = '';
    selectedLevel.value = '';
    entries.value = _applyFilter(_allEntries);
  }

  Color getLevelColor(String level) {
    switch (level) {
      case 'ERROR':
        return const Color(0xFFEF4444);
      case 'WARN':
        return const Color(0xFFF59E0B);
      case 'DEBUG':
        return const Color(0xFF8B5CF6);
      case 'INFO':
        return const Color(0xFF22C55E);
      default:
        return const Color(0xFF94A3B8);
    }
  }
}
