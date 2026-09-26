import 'package:flutter/material.dart';

import 'package:slime_works/core/theme/app_semantics.dart';

/// 一组身份色：一根主线 + 渐变终点
///
/// 图标底的水洗色、折线本身、折线末端那个圆点共用同一个身份，所以这两个值
/// 必须成对出现，不能各调各的。
class AppViz {
  const AppViz(this.base, this.to);

  final Color base;
  final Color to;

  List<Color> get gradient => [base, to];
}

/// 概览/监控类页面里并列卡片身份色板的唯一出处
///
/// 这些色相不是语义角色（既不是"成功/危险"，也不是"强调"），只是给同一页里
/// 并排的卡片分派可辨认的身份，所以单列一档，别塞进 AppSemantic 冒充状态色。
/// 原来这十几组值直接写在页面里，同一个绿在两个地方各写一遍。
class AppVizSet {
  const AppVizSet({
    required this.sky,
    required this.sea,
    required this.lagoon,
    required this.mint,
    required this.amber,
    required this.lilac,
    required this.coral,
  });

  /// 天蓝：CPU
  final AppViz sky;

  /// 浅海蓝：节点请求
  final AppViz sea;

  /// 海蓝转青：流水账
  final AppViz lagoon;

  /// 青绿：下行/笔记
  final AppViz mint;

  /// 暖橙：内存/阿里云
  final AppViz amber;

  /// 淡紫：上行/工具箱
  final AppViz lilac;

  /// 珊瑚：媒体库
  final AppViz coral;

  static const AppVizSet light = AppVizSet(
    sky: AppViz(Color(0xFF6FB8E8), Color(0xFFA8B8F6)),
    sea: AppViz(Color(0xFF9AC8DD), Color(0xFF6FB8E8)),
    lagoon: AppViz(Color(0xFF9AC8DD), Color(0xFF82D7BB)),
    mint: AppViz(Color(0xFF4CAF50), Color(0xFF82D7BB)),
    amber: AppViz(Color(0xFFF5A569), Color(0xFFFFCB3A)),
    lilac: AppViz(Color(0xFFBBA8F6), Color(0xFFA89FEE)),
    coral: AppViz(Color(0xFFFF6C74), Color(0xFFF5A569)),
  );

  /// 暗色下只有绿色这一档需要提亮：压在深灰上 4CAF50 会发闷
  static const AppVizSet dark = AppVizSet(
    sky: AppViz(Color(0xFF6FB8E8), Color(0xFFA8B8F6)),
    sea: AppViz(Color(0xFF9AC8DD), Color(0xFF6FB8E8)),
    lagoon: AppViz(Color(0xFF9AC8DD), Color(0xFF82D7BB)),
    mint: AppViz(Color(0xFF66BB6A), Color(0xFF82D7BB)),
    amber: AppViz(Color(0xFFF5A569), Color(0xFFFFCB3A)),
    lilac: AppViz(Color(0xFFBBA8F6), Color(0xFFA89FEE)),
    coral: AppViz(Color(0xFFFF6C74), Color(0xFFF5A569)),
  );

  static AppVizSet of(BuildContext context) =>
      AppSemantic.of(context).isDark ? dark : light;
}
