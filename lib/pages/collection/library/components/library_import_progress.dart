import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/view_models/novel_library_viewmodel.dart';

class LibraryImportProgressBanner extends StatelessWidget {
  final NovelLibraryViewModel viewModel;

  const LibraryImportProgressBanner({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final detecting = viewModel.isDetecting.value;
      final scanning = viewModel.isScanning.value;
      if (!detecting && !scanning) return const SizedBox.shrink();

      final m = AppTheme.metrics;
      final s = AppSemantic.of(context);
      final status = viewModel.scanStatusText.value;
      final completed = viewModel.detectionCompleted.value;
      final total = viewModel.detectionTotal.value;
      final sampleCompleted = viewModel.detectionSampleCompleted.value;
      final sampleTotal = viewModel.detectionSampleTotal.value;
      final bookProgress = '$completed/$total 本';
      final detail = detecting
          ? sampleTotal > 0
                ? '$bookProgress · 样本 $sampleCompleted/$sampleTotal'
                : '$bookProgress · 正在准备样本'
          : viewModel.scanProgressText.value;
      final progress = detecting && total > 0
          ? sampleTotal > 0
                ? (completed + sampleCompleted / sampleTotal) / total
                : completed / total
          : null;

      return Semantics(
        liveRegion: true,
        label: '$status $detail',
        child: Container(
          key: const ValueKey('novel-import-progress'),
          margin: EdgeInsets.symmetric(
            horizontal: m.kSpace12,
            vertical: m.kSpace8,
          ),
          padding: EdgeInsets.all(m.kSpace12),
          decoration: BoxDecoration(
            color: s.accent.withAlpha(18),
            borderRadius: m.radius12,
            border: Border.all(color: s.accent.withAlpha(60)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SizedBox.square(
                    dimension: m.kSpace16,
                    child: CircularProgressIndicator(
                      strokeWidth: m.strokeRegular,
                      valueColor: AlwaysStoppedAnimation<Color>(s.accent),
                    ),
                  ),
                  SizedBox(width: m.kSpace12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status.isEmpty
                              ? (detecting ? 'AI 正在解析' : '正在导入')
                              : status,
                          style: AppTextStyles.role(
                            context,
                            fontSize: m.fontSize13,
                            weight: FontWeight.w600,
                            color: s.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (detail.isNotEmpty) ...[
                          SizedBox(height: m.kSpace4),
                          Text(
                            detail,
                            style: AppTextStyles.caption(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: m.kSpace8),
              LinearProgressIndicator(
                value: progress?.clamp(0.0, 1.0).toDouble(),
                minHeight: m.strokeRegular,
                color: s.accent,
                backgroundColor: s.accent.withAlpha(25),
                borderRadius: m.radius32,
              ),
            ],
          ),
        ),
      );
    });
  }
}
