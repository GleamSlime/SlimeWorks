import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/src/rust/api/sentry_log.dart';

class SentryLogViewModel extends GetxController {
  final RxList<Map<String, dynamic>> events = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> projects = <Map<String, dynamic>>[].obs;
  final RxMap<String, dynamic> stats = <String, dynamic>{}.obs;
  final RxBool isLoading = false.obs;
  final RxString errorMessage = ''.obs;

  final RxString selectedProjectId = ''.obs;
  final RxString selectedLevel = ''.obs;
  final RxString searchQuery = ''.obs;
  final RxString selectedEnvironment = ''.obs;
  final RxInt totalEvents = 0.obs;
  final RxInt currentOffset = 0.obs;
  final int pageSize = 50;

  Future<void> loadInitialData() async {
    isLoading.value = true;
    try {
      await Future.wait([loadProjects(), loadStats(), loadEvents()]);
    } catch (e) {
      errorMessage.value = '加载数据失败: $e';
      logger.e('加载Sentry日志数据失败: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadEvents() async {
    try {
      final result = await sentryLogQuery(
        projectId: selectedProjectId.value.isEmpty ? null : selectedProjectId.value,
        level: selectedLevel.value.isEmpty ? null : selectedLevel.value,
        query: searchQuery.value.isEmpty ? null : searchQuery.value,
        environment: selectedEnvironment.value.isEmpty ? null : selectedEnvironment.value,
        startTime: null,
        endTime: null,
        offset: BigInt.from(currentOffset.value),
        limit: BigInt.from(pageSize),
      );

      final parsed = jsonDecode(result) as Map<String, dynamic>;
      final eventList =
          (parsed['events'] as List<dynamic>?)?.map((e) => e as Map<String, dynamic>).toList() ??
          [];
      totalEvents.value = (parsed['total'] as num?)?.toInt() ?? 0;
      events.value = eventList;
    } catch (e) {
      errorMessage.value = '加载事件失败: $e';
      logger.e('加载Sentry事件失败: $e');
    }
  }

  Future<void> loadProjects() async {
    try {
      final result = await sentryLogGetProjects();
      final parsed = jsonDecode(result) as List<dynamic>;
      projects.value = parsed.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      logger.e('加载Sentry项目失败: $e');
    }
  }

  Future<void> loadStats() async {
    try {
      final result = await sentryLogGetStats();
      stats.value = jsonDecode(result) as Map<String, dynamic>;
    } catch (e) {
      logger.e('加载Sentry统计失败: $e');
    }
  }

  Future<void> reloadData() async {
    currentOffset.value = 0;
    await loadInitialData();
  }

  Future<void> applyFilter() async {
    currentOffset.value = 0;
    isLoading.value = true;
    try {
      await loadEvents();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if ((currentOffset.value + pageSize) >= totalEvents.value) return;
    currentOffset.value += pageSize;
    try {
      final result = await sentryLogQuery(
        projectId: selectedProjectId.value.isEmpty ? null : selectedProjectId.value,
        level: selectedLevel.value.isEmpty ? null : selectedLevel.value,
        query: searchQuery.value.isEmpty ? null : searchQuery.value,
        environment: selectedEnvironment.value.isEmpty ? null : selectedEnvironment.value,
        startTime: null,
        endTime: null,
        offset: BigInt.from(currentOffset.value),
        limit: BigInt.from(pageSize),
      );

      final parsed = jsonDecode(result) as Map<String, dynamic>;
      final eventList =
          (parsed['events'] as List<dynamic>?)?.map((e) => e as Map<String, dynamic>).toList() ??
          [];
      events.addAll(eventList);
    } catch (e) {
      logger.e('加载更多Sentry事件失败: $e');
    }
  }

  Future<bool> deleteEvent(String eventId) async {
    try {
      final result = await sentryLogDeleteEvent(eventId: eventId);
      if (result) {
        events.removeWhere((e) => e['event_id'] == eventId);
        totalEvents.value--;
        await loadStats();
      }
      return result;
    } catch (e) {
      logger.e('删除Sentry事件失败: $e');
      return false;
    }
  }

  Future<int> deleteEvents(List<String> eventIds) async {
    try {
      final count = await sentryLogDeleteEvents(eventIds: eventIds);
      events.removeWhere((e) => eventIds.contains(e['event_id']));
      totalEvents.value -= count.toInt();
      await loadStats();
      return count.toInt();
    } catch (e) {
      logger.e('批量删除Sentry事件失败: $e');
      return 0;
    }
  }

  Future<String> exportLogs() async {
    try {
      return await sentryLogExportJson(
        projectId: selectedProjectId.value.isEmpty ? null : selectedProjectId.value,
        level: selectedLevel.value.isEmpty ? null : selectedLevel.value,
        query: searchQuery.value.isEmpty ? null : searchQuery.value,
        environment: selectedEnvironment.value.isEmpty ? null : selectedEnvironment.value,
        startTime: null,
        endTime: null,
      );
    } catch (e) {
      logger.e('导出Sentry日志失败: $e');
      return '';
    }
  }

  Future<void> updateProjectName(String projectId, String name) async {
    try {
      await sentryLogUpdateProjectName(projectId: projectId, name: name);
      await loadProjects();
    } catch (e) {
      logger.e('更新项目名称失败: $e');
    }
  }

  Future<void> clearProjectEvents(String projectId) async {
    try {
      await sentryLogClearProjectEvents(projectId: projectId);
      await loadInitialData();
    } catch (e) {
      logger.e('清空项目事件失败: $e');
    }
  }

  Color getLevelColor(String level) {
    switch (level) {
      case 'fatal':
        return Colors.purple.shade700;
      case 'error':
        return Colors.red.shade700;
      case 'warning':
        return Colors.orange.shade700;
      case 'info':
        return Colors.blue.shade700;
      case 'debug':
        return Colors.grey.shade600;
      default:
        return Colors.grey;
    }
  }

  IconData getLevelIcon(String level) {
    switch (level) {
      case 'fatal':
        return Icons.error;
      case 'error':
        return Icons.error_outline;
      case 'warning':
        return Icons.warning_amber;
      case 'info':
        return Icons.info_outline;
      case 'debug':
        return Icons.bug_report;
      default:
        return Icons.article;
    }
  }

  String formatTimestamp(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) return '-';
    try {
      final dt = DateTime.parse(timestamp);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    } catch (_) {
      return timestamp;
    }
  }
}