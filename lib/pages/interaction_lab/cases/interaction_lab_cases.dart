import 'package:flutter/material.dart';

import '../kit.dart';
import 'case_01_search.dart';
import 'case_02_icon_bar.dart';
import 'case_03_slide_confirm.dart';
import 'case_04_reorder_list.dart';
import 'case_05_inline_confirm.dart';
import 'case_06_pull_refresh.dart';
import 'case_07_assignees.dart';
import 'case_08_create_menu.dart';
import 'case_09_one_time_code.dart';

/// 分类：只用于这张页面上的筛选，不参与任何全局配置
enum IlCat {
  press('按压'),
  drag('拖拽'),
  select('选择'),
  input('输入');

  const IlCat(this.label);

  final String label;
}

/// 一格案例
@immutable
class IlCase {
  const IlCase({
    required this.seq,
    required this.title,
    required this.subtitle,
    required this.cat,
    required this.build,
    this.stageW = IlSize.stageW,
    this.stageH = IlSize.stageH,
  });

  final int seq;
  final String title;

  /// 这一格该动手试什么
  final String subtitle;
  final IlCat cat;
  final Widget Function() build;

  /// 这一格的舞台尺寸，默认全页统一档；量出来更高的格子自己报
  final double stageW;
  final double stageH;
}

/// 12 格，顺序和用户给的清单一致
final List<IlCase> kIlCases = <IlCase>[
  IlCase(
    seq: 1,
    title: 'Search',
    subtitle: '按下先压一下，再弹簧展开；收起态整颗朝指针磁吸',
    cat: IlCat.press,
    build: Case01Search.new,
  ),
  IlCase(
    seq: 2,
    title: 'Icon bar',
    subtitle: '滑块先横跨到并集区间停一下，再带过冲弹回目标格',
    cat: IlCat.select,
    build: Case02IconBar.new,
  ),
  IlCase(
    seq: 3,
    title: 'Slide to confirm',
    subtitle: '真按住拖：拖到底松手才确认，确认时右边缘钉住、把手在身后摊平',
    cat: IlCat.drag,
    build: Case03SlideConfirm.new,
  ),
  IlCase(
    seq: 4,
    title: 'Reorder list',
    subtitle: '按住整行拖：拿起的钉在指上、其余让开，靠近 6px 内药丸会熔化接上',
    cat: IlCat.drag,
    build: Case04ReorderList.new,
  ),
  IlCase(
    seq: 5,
    title: 'Inline confirm',
    subtitle: '一按就删：白药丸弹簧长大 4 秒，标签只淡入淡出，Undo 或倒计时归零收回',
    cat: IlCat.press,
    build: Case05InlineConfirm.new,
  ),
  IlCase(
    seq: 6,
    title: 'Pull to refresh',
    subtitle: '按住卡片往下拽：65px 才够阈值，松手转 1.15 秒换一条数据；图上可横扫读数',
    cat: IlCat.drag,
    // 卡片 320×261.5 是量出来的，往下长还要 88px，只能把这格的舞台单独加高
    stageH: 372,
    build: Case06PullRefresh.new,
  ),
  IlCase(
    seq: 7,
    title: 'Assignees',
    subtitle: '点头像条展开选人：宽度是定时补间，脸按弹簧逐个进、靠前者压住后者',
    cat: IlCat.select,
    // 264×268 的组件坐在舞台里；行进场那 4 段 delay 要有余量走完
    stageH: 280,
    build: Case07Assignees.new,
  ),
  IlCase(
    seq: 8,
    title: 'Create menu',
    subtitle: '按下先压 60ms 再自己展开：白块的宽/高/圆角吃三条同参数弹簧，四行按 22ms 逐个进',
    cat: IlCat.press,
    // 244 见方的舞台，比默认那档高一点
    stageH: 256,
    build: Case08CreateMenu.new,
  ),
  IlCase(
    seq: 9,
    title: 'One-time code',
    subtitle: '点一下再敲四位：先看一遍呼吸波，对了四格拉丝融成胶囊，错了抖散（数字只掉不淡）',
    cat: IlCat.input,
    build: Case09OneTimeCode.new,
  ),
];
