import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 5. Menu dropdown — 以顶边中心为锚点的展开 / 收起
///
/// 参考稿把开和收拆成两套时长：开 250ms 从预缩 0.97 长到 1，
/// 收只有 150ms 且退到 0.99（比预缩略大，观感是"松手"而不是"弹回"），
/// 两条共用同一条顺出曲线，锚点固定在顶边中心（`--p2-origin: top center`），
/// 菜单像是从自己上边缘"滴下来"的。
class Case05MenuDropdown extends StatefulWidget {
  const Case05MenuDropdown({super.key});

  @override
  State<Case05MenuDropdown> createState() => _Case05MenuDropdownState();
}

class _Case05MenuDropdownState extends State<Case05MenuDropdown> {
  /// `--p2-open-dur / --p2-close-dur`
  static const _openDur = Duration(milliseconds: 250);
  static const _closeDur = Duration(milliseconds: 150);

  /// `--p2-pre-scale / --p2-closing-scale`
  static const _preScale = 0.97;
  static const _closingScale = 0.99;

  static const _menuW = 234.0;

  bool _open = false;

  void _toggle() => setState(() => _open = !_open);

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Stack(
        children: [
          Positioned(
            left: (LabSize.stageW - _menuW) / 2,
            // 参考稿菜单在开关按钮下方 10px：顶 20 + 按钮 36 + 间距 10
            top: 66,
            child: LabTween(
              target: _open ? 1 : 0,
              duration: _open ? _openDur : _closeDur,
              curve: LabEase.smoothOut,
              builder: (context, t) {
                // 开、收共用同一条 0→1 进度，但各自的缩放的起点不同
                // （0.97 vs 0.99），所以按当前方向换算，避免两段之间跳变
                final from = _open ? _preScale : _closingScale;
                return Opacity(
                  opacity: t,
                  child: Transform.scale(
                    scale: from + (1 - from) * t,
                    alignment: Alignment.topCenter,
                    child: const _DropdownSurface(),
                  ),
                );
              },
            ),
          ),
          LabStageFooter(
            children: [LabAnimateButton(label: 'Animate', onTap: _toggle)],
          ),
        ],
      ),
    );
  }
}

/// 234×136 浮层：圆角 12、材料底 + 三层投影，内部三根定位骨架条
class _DropdownSurface extends StatelessWidget {
  const _DropdownSurface();

  static const _bars = <(double, double, double)>[
    (18, 23, 173), // s1：左 18、上 23、宽 173
    (18, 63, 131), // s2
    (18, 103, 194), // s3
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 234,
      height: 136,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: LabColor.card,
        borderRadius: BorderRadius.all(Radius.circular(12)),
        boxShadow: LabShadow.material,
      ),
      child: Stack(
        children: [
          for (final (x, y, w) in _bars)
            Positioned(
              left: x,
              top: y,
              child: Container(
                width: w,
                height: 14,
                decoration: const BoxDecoration(
                  color: LabColor.skeleton,
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
