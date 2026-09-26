import 'package:flutter/material.dart';

import '../kit.dart';
import 'case_01_popover.dart';
import 'case_02_floating_panel.dart';
import 'case_03_popover_form.dart';

/// 分类：只用于这张页面上的筛选，不参与任何全局配置
enum SvCat {
  pop('浮层'),
  drag('拖拽'),
  press('按压'),
  morph('形变'),
  input('输入'),
  reveal('揭示');

  const SvCat(this.label);

  final String label;
}

/// 一格案例
@immutable
class SvCase {
  const SvCase({
    required this.seq,
    required this.title,
    required this.subtitle,
    required this.cat,
    required this.build,
    this.stageW = SvSize.stageW,
    this.stageH = SvSize.stageH,
    this.dark = false,
  });

  final int seq;
  final String title;

  /// 这一格该动手试什么
  final String subtitle;
  final SvCat cat;
  final Widget Function() build;

  /// 这一格的舞台尺寸，默认全页统一档；面板撑出来的格子自己报
  final double stageW;
  final double stageH;

  /// 参考稿这一条本身就是暗色档（外壳跟着翻，见 [SvStage.dark]）
  final bool dark;
}

/// 9 格，顺序和用户给的清单一致
final List<SvCase> kSvCases = <SvCase>[
  SvCase(
    seq: 1,
    title: 'Popover',
    subtitle: '按钮和面板是同一块：364×200 从按钮左上角长出来，那行字跟着飞过去',
    cat: SvCat.pop,
    // 面板 200 高 + 上下留白，比默认那档高一点
    stageH: 248,
    build: Case01Popover.new,
  ),
  SvCase(
    seq: 2,
    title: 'Floating panel',
    subtitle: '面板不是从按钮里长的，是落在按钮下面；只有那行字飞过去，内容按 .2/.3 分两批进来',
    cat: SvCat.pop,
    // 214 高的面板挂在 36 的按钮下面，再加阴影那 22
    stageH: 288,
    build: Case02FloatingPanel.new,
  ),
  SvCase(
    seq: 3,
    title: 'Popover form',
    subtitle: '面板外圈还套 4px 灰框，页脚两边各咬一个缺口；交完表是两块表面互相顶替',
    cat: SvCat.pop,
    build: Case03PopoverForm.new,
  ),
];
