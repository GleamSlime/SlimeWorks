/// 手势类案例共用的"手机屏"底座
///
/// 这六格来自同一段手机录屏：屏 249×548、行 67 高 / 81 间距、圆角 18、
/// 左右边距 16，逐帧量出来的。六格共用一套量，等比缩到舞台高 260
/// （系数 [labK]），谁也别再抄一遍。
///
/// 和 `lab_kit.dart` 一样，这里的数字是**参考稿的字面量**，不读全局主题、
/// 不吃窗口缩放——这张页要的是像素级还原，不是全站换肤。
library;

import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 参考稿那块屏 548 高 → 舞台高 260
const labK = 0.4745;

const labScreenW = 249 * labK;
const labScreenX = (LabSize.stageW - labScreenW) / 2;

/// 行版式：边距 16 / 宽 218 / 高 67 / 间距 14 / 圆角 18 / 首行 y 61
const labPad = 16 * labK;
const labRowW = 218 * labK;
const labRowH = 67 * labK;
const labRowGap = 14 * labK;
const labRowTop = 61 * labK;
const labRadius = 18 * labK;

/// 行内骨架：头像 32 圆（x33），两条文字条 7 高（x81，长 100 / 65，y21.5 / 38）
const labAvatarD = 32 * labK;
const labAvatarX = (33 - 16) * labK;
const labLineX = (81 - 16) * labK;
const labLineH = 7 * labK;
const labLine1W = 100 * labK;
const labLine2W = 65 * labK;
const labLine1Y = 21.5 * labK;
const labLine2Y = 38 * labK;

/// 顶部标题条（y36 h11 w112）与底部 home 条（y500 h6 w84）
const labHeadY = 36 * labK;
const labHeadH = 11 * labK;
const labHeadW = 112 * labK;
const labHomeY = 500 * labK;
const labHomeH = 6 * labK;
const labHomeW = 84 * labK;

const labScreenBg = Color(0xFFFDFDFD);
const labScreenBorder = Color(0xFFDEDEE0);
const labPillBg = Color(0xFFEFEFF2); // 行底 / 标题条
const labBarBg = Color(0xFFDDDDE1); // 头像、文字条、home 条、揭开的灰条

/// 第 i 行的 y（参考稿行距 81 = 行高 67 + 间距 14）
double labRowY(int i) => labRowTop + i * (labRowH + labRowGap);

/// 手机屏：白色圆角面板 + 1px 边框，内容按面板内坐标摆，超出面板的一律裁掉
///
/// 边框压在内容上面单独画一层：贴在 ClipRRect 内侧的描边会被裁掉一半，
/// 少那一半就看不出手机边界。
class LabPhoneScreen extends StatelessWidget {
  const LabPhoneScreen({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: labScreenX,
      top: 0,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(labRadius),
            child: ColoredBox(
              color: labScreenBg,
              child: SizedBox(
                width: labScreenW,
                height: LabSize.stageH,
                child: Stack(children: children),
              ),
            ),
          ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: labScreenBorder),
                borderRadius: BorderRadius.circular(labRadius),
              ),
              child: const SizedBox(width: labScreenW, height: LabSize.stageH),
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶部标题条（跟着内容一起被拉走的那根）
const Widget labHeaderBar = Positioned(
  left: labPad,
  top: labHeadY,
  child: LabBar(width: labHeadW, height: labHeadH, color: labPillBg),
);

/// 底部 home 条（系统层，下拉/塌陷都不跟着动）
const Widget labHomeBar = Positioned(
  left: (labScreenW - labHomeW) / 2,
  top: labHomeY,
  child: LabBar(width: labHomeW, height: labHomeH, color: labBarBg),
);

/// 顶部标题条 + 底部 home 条：每格都要，省得各写一遍
const List<Widget> labChrome = [labHeaderBar, labHomeBar];

/// 面板内的一根圆角条（头像给成正方形 + circle 即可）
///
/// 自己不带定位：放进手机屏时由外面那层 `Positioned` 说话。
class LabBar extends StatelessWidget {
  const LabBar({
    super.key,
    required this.width,
    required this.height,
    required this.color,
    this.circle = false,
  });

  final double width;
  final double height;
  final Color color;

  /// true = 实心圆（头像）
  final bool circle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: circle
          ? BoxDecoration(color: color, shape: BoxShape.circle)
          : BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(height / 2),
            ),
    );
  }
}

/// 一行骨架：头像 + 两条文字条，可选右侧三横线拖拽柄
///
/// 自己带尺寸（[labRowW] × [labRowH]），放进 `Positioned` 只要给 left/top；
/// 需要塌陷/缩放的格子把它再包一层 `SizedBox` 收高度就行。
class LabSkelRow extends StatelessWidget {
  const LabSkelRow({super.key, this.color = labPillBg, this.handle = false});

  final Color color;

  /// 右侧那三横线（拖拽排序格用）
  final bool handle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: labRowW,
      height: labRowH,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(labRadius),
        ),
        child: Stack(
          children: [
            Positioned(
              left: labAvatarX,
              top: (labRowH - labAvatarD) / 2,
              child: LabBar(
                width: labAvatarD,
                height: labAvatarD,
                color: labBarBg,
                circle: true,
              ),
            ),
            Positioned(
              left: labLineX,
              top: labLine1Y,
              child: LabBar(width: labLine1W, height: labLineH, color: labBarBg),
            ),
            Positioned(
              left: labLineX,
              top: labLine2Y,
              child: LabBar(width: labLine2W, height: labLineH, color: labBarBg),
            ),
            if (handle)
              Positioned(
                right: 18 * labK,
                top: 0,
                bottom: 0,
                child: Center(
                  child: LabIcon(
                    paths: const [
                      'M2.5 4.5h11',
                      'M2.5 8h11',
                      'M2.5 11.5h11',
                    ],
                    // 16 viewBox 里三横线占 11 格，缩到参考稿那 11px
                    size: 16 * labK,
                    color: labBarBg,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
