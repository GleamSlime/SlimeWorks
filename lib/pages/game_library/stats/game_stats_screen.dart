import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/pages/game_library/models/game_library_models.dart';
import 'package:slime_works/view_models/game_library/game_library_stats_viewmodel.dart';

class GameStatsScreen extends BasePage<GameLibraryStatsViewModel> {
  const GameStatsScreen({super.key});

  @override
  State<GameStatsScreen> createState() => _GameStatsScreenState();
}

class _GameStatsScreenState extends BasePageState<GameLibraryStatsViewModel, GameStatsScreen> {
  @override
  bool get showAppBar => false;

  @override
  GameLibraryStatsViewModel createViewModel() => GameLibraryStatsViewModel();

  ScreenChromeData _buildChromeData() {
    return ScreenChromeData(
      title: '游玩统计',
      actions: <Widget>[
        FilledButton.icon(
          onPressed: _pickRange,
          icon: const Icon(Icons.date_range),
          label: const Text('选择区间'),
        ),
      ],
    );
  }

  Future<void> _pickRange() async {
    final DateTime now = DateTime.now();
    final DateTimeRange? range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: viewModel.startDate.value,
        end: viewModel.endDate.value,
      ),
    );
    if (range != null) {
      await viewModel.setRange(range.start, range.end);
    }
  }

  @override
  Widget buildContent(BuildContext context) {
    return ScreenChrome(
      data: _buildChromeData(),
      child: Obx(() {
        final GameStatsData? data = viewModel.statsData.value;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final int maxValue = data.timeline.isEmpty
            ? 1
            : data.timeline
                  .map((DayPlayTime e) => e.durationSec)
                  .reduce((int a, int b) => a > b ? a : b);

        return ListView(
          padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
          children: <Widget>[
            Card(
              child: Padding(
                padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
                child: Wrap(
                  spacing: AppTheme.metrics.kSpace16,
                  runSpacing: AppTheme.metrics.kSpace12,
                  children: <Widget>[
                    _StatChip(title: '总时长', value: viewModel.formatDuration(data.totalPlayTimeSec)),
                    _StatChip(title: '会话次数', value: '${data.sessionCount} 次'),
                    _StatChip(
                      title: '时间范围',
                      value:
                          '${viewModel.startDate.value.toLocal().toString().split(' ').first} ~ ${viewModel.endDate.value.toLocal().toString().split(' ').first}',
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: AppTheme.metrics.kSpace16),
            Text('日维度趋势', style: Theme.of(context).textTheme.titleMedium),
            SizedBox(height: AppTheme.metrics.kSpace8),
            if (data.timeline.isEmpty)
              const Card(child: ListTile(title: Text('当前时间范围没有数据')))
            else
              ...data.timeline.map(
                (DayPlayTime item) => Card(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppTheme.metrics.kSpace12,
                      vertical: AppTheme.metrics.kSpace10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(item.date.toLocal().toString().split(' ').first),
                            Text(viewModel.formatDuration(item.durationSec)),
                          ],
                        ),
                        SizedBox(height: AppTheme.metrics.kSpace8),
                        LinearProgressIndicator(value: item.durationSec / maxValue),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(title),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}
