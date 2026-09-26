import 'package:flutter/material.dart';

import '../components/window/sidebar_resize_handle.dart';
import '../core/theme/style_tokens.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';

/// 样式总览页：用同一套设计令牌渲染整块界面，明暗两版并排对照。
///
/// 面板宽度固定，保证不同窗口尺寸下排版不塌陷、截图可复现。
class StyleShowcaseScreen extends StatelessWidget {
  const StyleShowcaseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9E9E6),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(DesignSpace.u6),
          child: Center(
            child: Column(
              children: [
                Wrap(
                  spacing: DesignSpace.u6,
                  runSpacing: DesignSpace.u6,
                  children: const [
                    _ShellPanel(palette: DesignPalette.light),
                    _ShellPanel(palette: DesignPalette.dark),
                  ],
                ),
                const SizedBox(height: DesignSpace.u6),
                Wrap(
                  spacing: DesignSpace.u6,
                  runSpacing: DesignSpace.u6,
                  children: const [
                    _Panel(palette: DesignPalette.light),
                    _Panel(palette: DesignPalette.dark),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.palette});

  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 720,
      height: 1040,
      child: _TokenScope(
        palette: palette,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: DesignRadius.rXxxl,
            boxShadow: DesignShadow.of(
              DesignShadowLevel.xxl,
              isDark: palette.isDark,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(DesignSpace.u4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _IconRail(palette: palette),
                const SizedBox(width: DesignSpace.u3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(palette: palette),
                      const SizedBox(height: DesignSpace.u4),
                      _Tabs(palette: palette),
                      const SizedBox(height: DesignSpace.u4),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _MissionCard(palette: palette)),
                            const SizedBox(width: DesignSpace.u4),
                            SizedBox(
                              width: 208,
                              child: _SkeletonColumn(palette: palette),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 令牌作用域：把这份调色板解析成 ThemeData，并给裸 Text 兜上字体
class _TokenScope extends StatelessWidget {
  const _TokenScope({required this.palette, required this.child});

  final DesignPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: designThemeData(palette),
      // 裸 Text 只走 DefaultTextStyle，不写这一层的话 fontFamily 落不到内置字体
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: DesignFont.family,
          fontFamilyFallback: DesignFont.fallback,
          fontSize: DesignType.sm,
          color: palette.foreground,
        ),
        child: child,
      ),
    );
  }
}

// ── 左侧图标栏 ──────────────────────────────────────────────

class _IconRail extends StatelessWidget {
  const _IconRail({required this.palette});

  final DesignPalette palette;

  static const List<StrokeIcon> _icons = [
    StrokeIcons.dashboard,
    StrokeIcons.map,
    StrokeIcons.smartToy,
    StrokeIcons.hub,
    StrokeIcons.personOutline,
    StrokeIcons.assignment,
    StrokeIcons.bolt,
    StrokeIcons.key,
    StrokeIcons.shield,
    StrokeIcons.contentCopy,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      decoration: BoxDecoration(
        color: palette.sidebar,
        borderRadius: DesignRadius.rXl,
        border: Border.all(color: palette.sidebarBorder),
      ),
      child: Column(
        children: [
          const SizedBox(height: DesignSpace.u2),
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: palette.sidebarPrimary,
              borderRadius: DesignRadius.rMd,
            ),
            child: DrawIcon(StrokeIcons.token,
              size: 17,
              color: palette.sidebarPrimaryForeground,
            ),
          ),
          const SizedBox(height: DesignSpace.u5),
          for (var i = 0; i < _icons.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: DesignSpace.u1),
              child: _RailButton(
                icon: _icons[i],
                selected: i == 2,
                palette: palette,
              ),
            ),
          const Spacer(),
          _RailButton(icon: StrokeIcons.helpOutline, palette: palette),
          _RailButton(icon: StrokeIcons.settings, palette: palette),
          const SizedBox(height: DesignSpace.u1),
          const _Avatar(label: 'A', size: 28, hue: Color(0xFFAC4BFF)),
          const SizedBox(height: DesignSpace.u2),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.palette,
    this.selected = false,
  });

  final StrokeIcon icon;
  final bool selected;
  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? palette.sidebarPrimary : null,
          borderRadius: DesignRadius.rMd,
        ),
        child: DrawIcon(icon,
          size: 17,
          color: selected
              ? palette.sidebarPrimaryForeground
              : palette.mutedForeground,
        ),
      ),
    );
  }
}

// ── 页头 ────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.palette});

  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 236,
          child: Text(
            'Mission Control Center',
            style: TextStyle(
              fontSize: DesignType.xl,
              fontWeight: FontWeight.w600,
              height: 1.4,
              color: palette.foreground,
            ),
          ),
        ),
        const SizedBox(width: DesignSpace.u4),
        Expanded(
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: DesignSpace.u3),
            decoration: BoxDecoration(
              color: palette.background,
              borderRadius: DesignRadius.rLg,
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                DrawIcon(StrokeIcons.search,
                  size: 17,
                  color: palette.mutedForeground,
                ),
                const SizedBox(width: DesignSpace.u2),
                Text(
                  'Enter Robot SKV or Nickname',
                  style: TextStyle(
                    fontSize: DesignType.sm,
                    color: palette.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.palette});

  final DesignPalette palette;

  static const List<String> _labels = [
    'Missions',
    'Robots',
    'Stations',
    'Alerts',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.secondary,
        borderRadius: DesignRadius.rLg,
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++)
            Expanded(
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == 1 ? palette.card : null,
                  borderRadius: DesignRadius.rMd,
                  border: Border.all(
                    color: i == 1 ? palette.border : Colors.transparent,
                  ),
                  boxShadow: i == 1
                      ? DesignShadow.of(
                          DesignShadowLevel.xs,
                          isDark: palette.isDark,
                        )
                      : null,
                ),
                child: Text(
                  _labels[i],
                  style: TextStyle(
                    fontSize: DesignType.sm,
                    fontWeight: i == 1 ? FontWeight.w600 : FontWeight.w500,
                    color: i == 1
                        ? palette.foreground
                        : palette.mutedForeground,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── 主卡片 ──────────────────────────────────────────────────

class _MissionCard extends StatelessWidget {
  const _MissionCard({required this.palette});

  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: DesignRadius.rXl,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Robot Management',
                    style: TextStyle(
                      fontSize: DesignType.base,
                      fontWeight: FontWeight.w600,
                      color: palette.foreground,
                    ),
                  ),
                ),
                _PillButton(
                  icon: StrokeIcons.workOutline,
                  label: 'Onboarding',
                  palette: palette,
                ),
                const SizedBox(width: DesignSpace.u2),
                _SquareIconButton(icon: StrokeIcons.tune, palette: palette),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: palette.border),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Sparkline(palette: palette),
                  const SizedBox(height: DesignSpace.u3),
                  _Legend(palette: palette),
                  const SizedBox(height: DesignSpace.u4),
                  _StatStrip(palette: palette),
                  const SizedBox(height: DesignSpace.u5),
                  _SectionHeader(
                    title: 'Scheduled',
                    count: '38 Missions',
                    palette: palette,
                    expanded: false,
                  ),
                  const SizedBox(height: DesignSpace.u4),
                  _SectionHeader(
                    title: 'Active Assignments',
                    count: '5 Missions',
                    palette: palette,
                    expanded: true,
                  ),
                  const SizedBox(height: DesignSpace.u2),
                  _AssignmentRow(
                    name: 'Meow S025',
                    avatar: const _Avatar(
                      label: 'M',
                      size: 26,
                      hue: Color(0xFFFCBB00),
                    ),
                    status: _Status.onTime,
                    palette: palette,
                  ),
                  _AssignmentRow(
                    name: 'Dock C112',
                    avatar: const _Avatar(
                      label: 'D',
                      size: 26,
                      hue: Color(0xFFF05100),
                    ),
                    status: _Status.late,
                    palette: palette,
                    expanded: true,
                  ),
                  _AssignmentRow(
                    name: 'Pip W92',
                    avatar: const _Avatar(
                      label: 'P',
                      size: 26,
                      hue: Color(0xFF009588),
                    ),
                    status: _Status.onTime,
                    palette: palette,
                  ),
                  _AssignmentRow(
                    name: 'Humble P028',
                    avatar: const _Avatar(
                      label: 'H',
                      size: 26,
                      hue: Color(0xFF104E64),
                    ),
                    status: _Status.failed,
                    palette: palette,
                    trailingIcon: StrokeIcons.openInFull,
                  ),
                  _AssignmentRow(
                    name: 'Kiko B17',
                    avatar: const _Avatar(
                      label: 'K',
                      size: 26,
                      hue: Color(0xFFEDB200),
                    ),
                    status: _Status.onTimeMuted,
                    palette: palette,
                    trailingIcon: StrokeIcons.openInFull,
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, thickness: 1, color: palette.border),
          _FooterActions(palette: palette),
        ],
      ),
    );
  }
}

class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.palette});

  final DesignPalette palette;

  static const List<_Group> _groups = [
    _Group(30, _LegendKey.scheduled),
    _Group(6, _LegendKey.active),
    _Group(8, _LegendKey.paused),
    _Group(2, _LegendKey.failed),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final g in _groups)
            for (var i = 0; i < g.count; i++)
              Padding(
                padding: const EdgeInsets.only(right: 2.5),
                child: Container(
                  width: 2.5,
                  height: 18 + ((i * 7 + g.count) % 4) * 2,
                  decoration: BoxDecoration(
                    color: _legendColor(palette, g.key),
                    borderRadius: DesignRadius.br(2),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _Group {
  const _Group(this.count, this.key);
  final int count;
  final _LegendKey key;
}

enum _LegendKey { scheduled, active, paused, failed }

Color _legendColor(DesignPalette palette, _LegendKey key) => switch (key) {
  _LegendKey.scheduled => palette.series,
  _LegendKey.active => palette.success,
  _LegendKey.paused => palette.warning,
  _LegendKey.failed => palette.destructive,
};

class _Legend extends StatelessWidget {
  const _Legend({required this.palette});

  final DesignPalette palette;

  static const Map<_LegendKey, String> _text = {
    _LegendKey.scheduled: '38 Scheduled',
    _LegendKey.active: '5 Active',
    _LegendKey.paused: '12 Paused',
    _LegendKey.failed: '3 Failed',
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: DesignSpace.u4,
      children: [
        for (final e in _text.entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _legendColor(palette, e.key),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: DesignSpace.u1_5),
              Text(
                e.value,
                style: TextStyle(
                  fontSize: DesignType.sm,
                  fontWeight: FontWeight.w500,
                  color: palette.foreground,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _StatStrip extends StatelessWidget {
  const _StatStrip({required this.palette});

  final DesignPalette palette;

  static const List<(String, String)> _items = [
    (r'$12.8k', 'Order Value'),
    ('32 min', 'Avg. Run'),
    ('68%', 'On Time'),
    ('28', 'Zones'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.secondary,
        borderRadius: DesignRadius.rLg,
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++) ...[
            if (i > 0)
              SizedBox(
                height: 34,
                child: VerticalDivider(width: 1, color: palette.border),
              ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    _items[i].$1,
                    style: TextStyle(
                      fontSize: DesignType.base,
                      fontWeight: FontWeight.w600,
                      color: palette.foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _items[i].$2,
                    style: TextStyle(
                      fontSize: DesignType.xs,
                      color: palette.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.palette,
    required this.expanded,
  });

  final String title;
  final String count;
  final DesignPalette palette;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: DesignType.base,
            fontWeight: FontWeight.w600,
            color: palette.foreground,
          ),
        ),
        const SizedBox(width: DesignSpace.u2),
        _CountPill(label: count, palette: palette),
        const Spacer(),
        _PillButton(label: 'View All', palette: palette, dense: true),
        const SizedBox(width: DesignSpace.u2),
        _SquareIconButton(
          icon: expanded
              ? StrokeIcons.expandLess
              : StrokeIcons.expandMore,
          palette: palette,
        ),
      ],
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.label, required this.palette});

  final String label;
  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: palette.muted,
        borderRadius: DesignRadius.rFull,
        border: Border.all(color: palette.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: DesignType.xs,
          fontWeight: FontWeight.w500,
          color: palette.mutedForeground,
        ),
      ),
    );
  }
}

enum _Status { onTime, onTimeMuted, late, failed }

class _AssignmentRow extends StatelessWidget {
  const _AssignmentRow({
    required this.name,
    required this.avatar,
    required this.status,
    required this.palette,
    this.expanded = false,
    this.trailingIcon = StrokeIcons.arrowOutward,
  });

  final String name;
  final _Avatar avatar;
  final _Status status;
  final DesignPalette palette;
  final bool expanded;
  final StrokeIcon trailingIcon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: DesignSpace.u3),
          child: Row(
            children: [
              avatar,
              const SizedBox(width: DesignSpace.u2),
              Text(
                name,
                style: TextStyle(
                  fontSize: DesignType.sm,
                  fontWeight: FontWeight.w600,
                  color: palette.foreground,
                ),
              ),
              const SizedBox(width: DesignSpace.u2),
              _StatusChip(status: status, palette: palette),
              const Spacer(),
              _SquareIconButton(
                icon: trailingIcon,
                palette: palette,
                dense: true,
              ),
              const SizedBox(width: DesignSpace.u2),
              _SquareIconButton(
                icon: expanded
                    ? StrokeIcons.expandLess
                    : StrokeIcons.expandMore,
                palette: palette,
                dense: true,
              ),
            ],
          ),
        ),
        if (expanded) ...[
          _DashedLine(palette: palette),
          _RunDetail(palette: palette),
          const SizedBox(height: DesignSpace.u3),
        ],
        Divider(height: 1, thickness: 1, color: palette.border),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.palette});

  final _Status status;
  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    final (label, base) = switch (status) {
      _Status.onTime => ('On time', palette.success),
      _Status.onTimeMuted => ('On time', palette.mutedForeground),
      _Status.late => ('Running late', palette.warning),
      _Status.failed => ('Failed', palette.destructive),
    };
    final icon = switch (status) {
      _Status.late => StrokeIcons.schedule,
      _Status.failed => StrokeIcons.errorOutline,
      _ => null,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: palette.container(base),
        borderRadius: DesignRadius.rFull,
        border: Border.all(color: palette.containerBorder(base)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            DrawIcon(icon, size: 12, color: base),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: DesignType.xs,
              fontWeight: FontWeight.w500,
              color: base,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine({required this.palette});

  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: LayoutBuilder(
        builder: (context, c) {
          const dash = 4.0;
          final n = (c.maxWidth / (dash * 2)).floor();
          return Row(
            children: List.generate(
              n,
              (_) => SizedBox(
                width: dash * 2,
                child: Container(
                  height: 1,
                  margin: const EdgeInsets.only(right: dash),
                  color: palette.border,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RunDetail extends StatelessWidget {
  const _RunDetail({required this.palette});

  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: DesignSpace.u3),
        Row(
          children: [
            _Meta(icon: StrokeIcons.schedule, label: '24m', palette: palette),
            const SizedBox(width: DesignSpace.u3),
            _Meta(icon: StrokeIcons.route, label: '3.8km', palette: palette),
            const SizedBox(width: DesignSpace.u3),
            _Meta(
              icon: StrokeIcons.battery5Bar,
              label: '76%',
              palette: palette,
            ),
            const SizedBox(width: DesignSpace.u3),
            _Meta(
              icon: StrokeIcons.callSplit,
              label: 'Checking',
              palette: palette,
            ),
            const Spacer(),
            _UserPill(
              label: 'Mark',
              avatarHue: const Color(0xFFEDB200),
              palette: palette,
            ),
          ],
        ),
        const SizedBox(height: DesignSpace.u4),
        _Timeline(
          palette: palette,
          time: '15:05',
          label: 'Cargo scanned',
          icon: StrokeIcons.centerFocusStrong,
          trailing: Text(
            '18/18 units',
            style: TextStyle(
              fontSize: DesignType.xs,
              color: palette.mutedForeground,
            ),
          ),
        ),
        _Timeline(
          palette: palette,
          time: '15:13',
          label: 'Delay detected',
          icon: StrokeIcons.schedule,
          trailing: _TonePill(
            label: '+6 min',
            base: palette.warning,
            palette: palette,
          ),
        ),
        _Timeline(
          palette: palette,
          time: '15:15',
          label: 'Checkpoint reached',
          icon: StrokeIcons.place,
          trailing: _UserPill(
            label: 'Zone B',
            icon: StrokeIcons.gridView,
            palette: palette,
          ),
        ),
        _Timeline(
          palette: palette,
          time: '15:17',
          label: 'Route changed by',
          icon: StrokeIcons.altRoute,
          trailing: _UserPill(
            label: 'Chris',
            avatarHue: const Color(0xFF00BB7F),
            palette: palette,
          ),
        ),
        _Timeline(
          palette: palette,
          time: '15:18',
          label: 'Battery dropped',
          icon: StrokeIcons.bolt,
          trailing: _BatteryBars(palette: palette),
        ),
        const SizedBox(height: DesignSpace.u2),
        SizedBox(
          height: 36,
          child: OutlinedButton.icon(
            onPressed: () {},
            icon: DrawIcon(StrokeIcons.travelExplore, size: 16),
            label: const Text('Track Mission'),
          ),
        ),
        const SizedBox(height: DesignSpace.u4),
      ],
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label, required this.palette});

  final StrokeIcon icon;
  final String label;
  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DrawIcon(icon, size: 15, color: palette.mutedForeground),
        const SizedBox(width: DesignSpace.u1_5),
        Text(
          label,
          style: TextStyle(
            fontSize: DesignType.sm,
            fontWeight: FontWeight.w500,
            color: palette.foreground,
          ),
        ),
      ],
    );
  }
}

class _UserPill extends StatelessWidget {
  const _UserPill({
    required this.label,
    required this.palette,
    this.avatarHue,
    this.icon,
  });

  final String label;
  final DesignPalette palette;
  final Color? avatarHue;
  final StrokeIcon? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: DesignRadius.rFull,
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (avatarHue != null)
            _Avatar(label: label[0], size: 18, hue: avatarHue!)
          else if (icon != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: DrawIcon(icon!, size: 14, color: palette.mutedForeground),
            ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: Text(
              label,
              style: TextStyle(
                fontSize: DesignType.xs,
                fontWeight: FontWeight.w500,
                color: palette.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TonePill extends StatelessWidget {
  const _TonePill({
    required this.label,
    required this.base,
    required this.palette,
  });

  final String label;
  final Color base;
  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: palette.container(base),
        borderRadius: DesignRadius.rSm,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: DesignType.xs,
          fontWeight: FontWeight.w600,
          color: base,
        ),
      ),
    );
  }
}

class _BatteryBars extends StatelessWidget {
  const _BatteryBars({required this.palette});

  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        10,
        (i) => Container(
          width: 3,
          height: i.isEven ? 14 : 11,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: i < 4 ? palette.success : palette.muted,
            borderRadius: DesignRadius.br(1.5),
          ),
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.palette,
    required this.time,
    required this.label,
    required this.icon,
    required this.trailing,
  });

  final DesignPalette palette;
  final String time;
  final String label;
  final StrokeIcon icon;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpace.u3),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: palette.mutedForeground,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: DesignSpace.u2),
          Text(
            time,
            style: TextStyle(
              fontSize: DesignType.sm,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: palette.mutedForeground,
            ),
          ),
          const SizedBox(width: DesignSpace.u2),
          Text(
            label,
            style: TextStyle(
              fontSize: DesignType.sm,
              color: palette.foreground,
            ),
          ),
          const SizedBox(width: DesignSpace.u1_5),
          DrawIcon(icon, size: 14, color: palette.mutedForeground),
          const Spacer(),
          trailing,
        ],
      ),
    );
  }
}

class _FooterActions extends StatelessWidget {
  const _FooterActions({required this.palette});

  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 38,
              child: FilledButton.icon(
                onPressed: () {},
                icon: DrawIcon(StrokeIcons.assignment, size: 16),
                label: const Text('Review Assignments'),
              ),
            ),
          ),
          const SizedBox(width: DesignSpace.u2),
          SizedBox(
            height: 38,
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: DrawIcon(StrokeIcons.history, size: 16),
              label: const Text('Activity'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 右侧骨架列 ──────────────────────────────────────────────

class _SkeletonColumn extends StatelessWidget {
  const _SkeletonColumn({required this.palette});

  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 118,
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: DesignRadius.rXl,
            border: Border.all(color: palette.border),
          ),
          padding: const EdgeInsets.all(DesignSpace.u4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _SkeletonBox(
                    width: 22,
                    height: 22,
                    circle: true,
                    palette: palette,
                  ),
                  const SizedBox(width: DesignSpace.u2),
                  _SkeletonBox(width: 86, height: 10, palette: palette),
                ],
              ),
              const SizedBox(height: DesignSpace.u4),
              _SkeletonBox(width: 62, height: 10, palette: palette),
            ],
          ),
        ),
        const SizedBox(height: DesignSpace.u4),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _SkeletonBox(width: 118, height: 10, palette: palette),
              const SizedBox(height: DesignSpace.u4),
              _SkeletonBox(width: 150, height: 10, palette: palette),
              const SizedBox(height: DesignSpace.u4),
              _SkeletonCard(height: 96, palette: palette),
              const SizedBox(height: DesignSpace.u4),
              _SkeletonCard(height: 128, palette: palette),
              const SizedBox(height: DesignSpace.u4),
              _SkeletonCard(height: 112, palette: palette),
            ],
          ),
        ),
      ],
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.height, required this.palette});

  final double height;
  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: palette.skeleton,
        borderRadius: DesignRadius.rLg,
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.palette,
    this.circle = false,
  });

  final double width;
  final double height;
  final DesignPalette palette;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: circle ? height : width,
      height: height,
      decoration: BoxDecoration(
        color: palette.skeleton,
        borderRadius: circle ? DesignRadius.rFull : DesignRadius.rSm,
      ),
    );
  }
}

// ── 通用小件 ────────────────────────────────────────────────

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.palette,
    this.label = '',
    this.icon,
    this.dense = false,
  });

  final DesignPalette palette;
  final String label;
  final StrokeIcon? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: dense ? 28 : 32,
      padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: DesignRadius.rFull,
        border: Border.all(color: palette.border),
        boxShadow: DesignShadow.of(
          DesignShadowLevel.xs,
          isDark: palette.isDark,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            DrawIcon(icon!, size: 15, color: palette.foreground),
            const SizedBox(width: DesignSpace.u1_5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: DesignType.sm,
              fontWeight: FontWeight.w500,
              color: palette.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _SquareIconButton extends StatelessWidget {
  const _SquareIconButton({
    required this.icon,
    required this.palette,
    this.dense = false,
  });

  final StrokeIcon icon;
  final DesignPalette palette;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final side = dense ? 28.0 : 32.0;
    return Container(
      width: side,
      height: side,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: DesignRadius.rMd,
        border: Border.all(color: palette.border),
        boxShadow: DesignShadow.of(
          DesignShadowLevel.xs,
          isDark: palette.isDark,
        ),
      ),
      child: DrawIcon(icon, size: 15, color: palette.foreground),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.label, required this.size, required this.hue});

  final String label;
  final double size;
  final Color hue;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [hue.withValues(alpha: 0.55), hue],
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ── 应用外壳：可拖拽侧边栏 ──────────────────────────────────

/// 图标栏 + 导航栏 + 内容区三段式外壳
///
/// 导航栏右缘挂着和真侧栏同一个拖拽指示条：拖动实时改宽、双击复位、
/// 点品牌行右侧的按钮可折叠成图标栏，折叠动画期间指示条淡出。
class _ShellPanel extends StatefulWidget {
  const _ShellPanel({required this.palette});

  final DesignPalette palette;

  static const double _defaultNavWidth = 232;
  static const double _minNavWidth = 150;
  static const double _maxNavWidth = 340;
  static const double _collapsedNavWidth = 64;

  /// 标签出现/消失的宽度门槛
  static const double _navLabelBreakpoint = 150;

  @override
  State<_ShellPanel> createState() => _ShellPanelState();
}

class _ShellPanelState extends State<_ShellPanel> {
  double _navWidth = _ShellPanel._defaultNavWidth;
  bool _collapsed = false;
  bool _resizing = false;

  /// 点把手：收起 / 展开
  void _toggle() => setState(() => _collapsed = !_collapsed);

  /// 拖把手：改宽度，拖到最窄自动收成图标条
  void _dragBy(double dx) {
    if (_collapsed) {
      // 收起态往右拖等于把它拉回来，不用先点一下
      if (dx > 0) setState(() => _collapsed = false);
      return;
    }
    final next = (_navWidth + dx).clamp(
      _ShellPanel._minNavWidth,
      _ShellPanel._maxNavWidth,
    );
    if (next <= _ShellPanel._minNavWidth) {
      setState(() {
        // 宽度回默认：拖到最窄的人是想要它收起来，不是想要一条 150 的窄栏
        _navWidth = _ShellPanel._defaultNavWidth;
        _collapsed = true;
        // 收这一刻要把动画打开，否则整条侧栏瞬间弹没
        _resizing = false;
      });
      return;
    }
    setState(() => _navWidth = next);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final expanded = !_collapsed;
    final targetWidth = expanded ? _navWidth : _ShellPanel._collapsedNavWidth;

    return SizedBox(
      width: 720,
      height: 800,
      child: _TokenScope(
        palette: palette,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: DesignRadius.rXxxl,
            boxShadow: DesignShadow.of(
              DesignShadowLevel.xxl,
              isDark: palette.isDark,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Container(
              decoration: BoxDecoration(
                color: palette.background,
                borderRadius: DesignRadius.rXxl,
                border: Border.all(color: palette.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: [
                  // 一条侧栏两种状态：图标条是收起态，整块菜单是展开态
                  AnimatedContainer(
                    duration: _resizing
                        ? Duration.zero
                        : const Duration(milliseconds: 260),
                    curve: Curves.easeInOutCubic,
                    width: targetWidth,
                    // 布局按实际宽度决定，不按 _collapsed：动画途中两种状态都会
                    // 经过装不下标签的宽度，标签提前进来就溢出、提前走就跳一下
                    child: LayoutBuilder(
                      builder: (context, constraints) => _ShellNav(
                        palette: palette,
                        expanded:
                            constraints.maxWidth >=
                            _ShellPanel._navLabelBreakpoint,
                        onToggle: _toggle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        // 非定位子件在 Stack 里拿到的是松约束，宽度会按内容缩，
                        // 画布要铺满这一格得钉住
                        Positioned.fill(child: _ShellCanvas(palette: palette)),
                        // 把手在内容区这一侧：贴在侧栏右缘会被内容区盖掉半截，
                        // 缩回侧栏里又会被那条滚动条压住
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          child: SidebarResizeHandle(
                            collapsed: _collapsed,
                            idleColor: palette.mutedForeground,
                            activeColor: palette.foreground,
                            onDragStart: () => setState(() => _resizing = true),
                            onDragUpdate: _dragBy,
                            onDragEnd: () => setState(() => _resizing = false),
                            onToggle: _toggle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellNav extends StatelessWidget {
  const _ShellNav({
    required this.palette,
    required this.expanded,
    required this.onToggle,
  });

  final DesignPalette palette;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(DesignSpace.u3),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: DesignSpace.u2),
              decoration: BoxDecoration(
                color: palette.secondary,
                borderRadius: DesignRadius.rLg,
                border: Border.all(color: palette.border),
              ),
              child: Row(
                children: [
                  DrawIcon(StrokeIcons.token,
                    size: 18,
                    color: palette.foreground,
                  ),
                  if (expanded)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: DesignSpace.u2),
                        child: Text(
                          'Control Plane',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: DesignType.sm,
                            fontWeight: FontWeight.w600,
                            color: palette.foreground,
                          ),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  if (expanded)
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: IconButton(
                        // 折叠/展开走 AnimatedContainer，宽度由把手那侧统一管
                        onPressed: onToggle,
                        iconSize: 16,
                        padding: EdgeInsets.zero,
                        // 不压掉触摸尺寸就把品牌行挤爆
                        constraints: const BoxConstraints.tightFor(
                          width: 22,
                          height: 22,
                        ),
                        icon: DrawIcon(
                          expanded
                              ? StrokeIcons.chevronLeft
                              : StrokeIcons.chevronRight,
                          color: palette.mutedForeground,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: DesignSpace.u2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Overline(
                    palette: palette,
                    label: 'Platform',
                    expanded: expanded,
                  ),
                  _NavItem(
                    palette: palette,
                    expanded: expanded,
                    label: 'Overview',
                    icon: StrokeIcons.home,
                    selected: true,
                  ),
                  _NavItem(
                    palette: palette,
                    expanded: expanded,
                    label: 'Pipelines',
                    icon: StrokeIcons.bolt,
                    trailing: StrokeIcons.expandMore,
                  ),
                  _NavItem(
                    palette: palette,
                    expanded: expanded,
                    label: 'Build Runs',
                    indent: true,
                  ),
                  _NavItem(
                    palette: palette,
                    expanded: expanded,
                    label: 'Deployments',
                    indent: true,
                    highlighted: true,
                  ),
                  _NavItem(
                    palette: palette,
                    expanded: expanded,
                    label: 'Release Gates',
                    indent: true,
                  ),
                  _NavItem(
                    palette: palette,
                    expanded: expanded,
                    label: 'Infrastructure',
                    icon: StrokeIcons.layers,
                    trailing: StrokeIcons.chevronRight,
                  ),
                  _NavItem(
                    palette: palette,
                    expanded: expanded,
                    label: 'Observability',
                    icon: StrokeIcons.timeline,
                    badge: '14',
                    badgeBase: palette.success,
                  ),
                  _NavItem(
                    palette: palette,
                    expanded: expanded,
                    label: 'Security',
                    icon: StrokeIcons.verifiedUser,
                  ),
                  const SizedBox(height: DesignSpace.u3),
                  _Overline(
                    palette: palette,
                    label: 'Resources',
                    expanded: expanded,
                    chevron: true,
                  ),
                  _NavItem(
                    palette: palette,
                    expanded: expanded,
                    label: 'API Gateway',
                    dot: palette.success,
                    pill: 'Prod',
                  ),
                  _NavItem(
                    palette: palette,
                    expanded: expanded,
                    label: 'ML Pipeline',
                    dot: palette.info,
                  ),
                  _NavItem(
                    palette: palette,
                    expanded: expanded,
                    label: 'Database',
                    dot: palette.series,
                    pill: 'US-East',
                  ),
                  _NavItem(
                    palette: palette,
                    expanded: expanded,
                    label: 'CDN',
                    dot: palette.warning,
                  ),
                  _NavItem(
                    palette: palette,
                    expanded: expanded,
                    label: 'Authentication',
                    dot: palette.destructive,
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0x00000000)),
          Padding(
            // 图标态把这层内缩让掉：它叠在条目自己的内缩之上，
            // 64 宽的图标条里再缩 24 就没地方放图标了
            padding: EdgeInsets.fromLTRB(
              expanded ? DesignSpace.u3 : 0,
              DesignSpace.u2,
              expanded ? DesignSpace.u3 : 0,
              DesignSpace.u2,
            ),
            child: Column(
              children: [
                _NavItem(
                  palette: palette,
                  expanded: expanded,
                  label: 'Settings',
                  icon: StrokeIcons.settings,
                ),
                _NavItem(
                  palette: palette,
                  expanded: expanded,
                  label: 'Invite Team',
                  icon: StrokeIcons.group,
                ),
                _NavItem(
                  palette: palette,
                  expanded: expanded,
                  label: 'Documentation',
                  icon: StrokeIcons.menuBook,
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              expanded ? DesignSpace.u3 : DesignSpace.u2,
              0,
              expanded ? DesignSpace.u3 : DesignSpace.u2,
              DesignSpace.u3,
            ),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: DesignSpace.u2),
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: DesignRadius.rLg,
                border: Border.all(color: palette.border),
              ),
              child: Row(
                children: [
                  const _Avatar(label: 'N', size: 26, hue: Color(0xFF009588)),
                  if (expanded) ...[
                    const SizedBox(width: DesignSpace.u2),
                    Expanded(
                      child: Text(
                        'Nick Bold',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: DesignType.sm,
                          fontWeight: FontWeight.w600,
                          color: palette.foreground,
                        ),
                      ),
                    ),
                    DrawIcon(StrokeIcons.moreHoriz,
                      size: 16,
                      color: palette.mutedForeground,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Overline extends StatelessWidget {
  const _Overline({
    required this.palette,
    required this.label,
    required this.expanded,
    this.chevron = false,
  });

  final DesignPalette palette;
  final String label;
  final bool expanded;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: DesignSpace.u2),
        child: Divider(height: 1, thickness: 1, color: palette.border),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        10,
        DesignSpace.u3,
        10,
        DesignSpace.u1,
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: DesignType.sm,
              fontWeight: FontWeight.w500,
              color: palette.mutedForeground,
            ),
          ),
          const Spacer(),
          if (chevron)
            DrawIcon(StrokeIcons.expandMore,
              size: 15,
              color: palette.mutedForeground,
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.palette,
    required this.expanded,
    required this.label,
    this.icon,
    this.dot,
    this.pill,
    this.badge,
    this.badgeBase,
    this.trailing,
    this.indent = false,
    this.selected = false,
    this.highlighted = false,
  });

  final DesignPalette palette;
  final bool expanded;
  final String label;
  final StrokeIcon? icon;
  final Color? dot;
  final String? pill;
  final String? badge;
  final Color? badgeBase;
  final StrokeIcon? trailing;
  final bool indent;
  final bool selected;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? palette.muted : (highlighted ? palette.accent : null);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignSpace.u2,
        vertical: 1,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 34,
          // 图标态不留缩进：缩进是给文字让位的，压上去图标就没地方放了
          padding: EdgeInsets.only(left: expanded && indent ? 26 : 10, right: 10),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(color: bg, borderRadius: DesignRadius.rMd),
          child: Row(
            children: [
              if (!expanded && indent)
                // 收起态没有文字可摆，子项留一道小竖线表示"这里缩进了一层"
                Container(
                  width: 2,
                  height: 12,
                  margin: const EdgeInsets.only(left: 3),
                  decoration: BoxDecoration(
                    color: palette.mutedForeground.withValues(alpha: 0.45),
                    borderRadius: DesignRadius.rFull,
                  ),
                )
              else if (dot != null && expanded) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: DesignSpace.u2),
              ] else if (icon != null) ...[
                DrawIcon(icon!, size: 17, color: palette.mutedForeground),
                SizedBox(width: expanded ? DesignSpace.u2 : 0),
              ],
              if (expanded)
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: DesignType.sm,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: palette.foreground,
                    ),
                  ),
                )
              else
                const SizedBox.shrink(),
              if (expanded && pill != null)
                Container(
                  margin: const EdgeInsets.only(right: DesignSpace.u1),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: DesignRadius.rSm,
                    border: Border.all(color: palette.border),
                  ),
                  child: Text(
                    pill!,
                    style: TextStyle(
                      fontSize: DesignType.xs,
                      color: palette.mutedForeground,
                    ),
                  ),
                ),
              if (expanded && badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: palette.container(badgeBase!),
                    borderRadius: DesignRadius.rFull,
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                      fontSize: DesignType.xs,
                      fontWeight: FontWeight.w600,
                      color: badgeBase,
                    ),
                  ),
                ),
              if (expanded && trailing != null)
                DrawIcon(trailing!, size: 15, color: palette.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellCanvas extends StatelessWidget {
  const _ShellCanvas({required this.palette});

  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: palette.background,
      padding: const EdgeInsets.all(DesignSpace.u4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Dashboard',
                style: TextStyle(
                  fontSize: DesignType.lg,
                  fontWeight: FontWeight.w600,
                  color: palette.foreground,
                ),
              ),
              const Spacer(),
              _PillButton(label: 'Deploy', palette: palette, dense: true),
            ],
          ),
          const SizedBox(height: DesignSpace.u4),
          for (final height in [132.0, 168.0])
            Padding(
              padding: const EdgeInsets.only(bottom: DesignSpace.u4),
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  borderRadius: DesignRadius.rLg,
                  border: Border.all(color: palette.border),
                ),
                padding: const EdgeInsets.all(DesignSpace.u4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBox(width: 96, height: 10, palette: palette),
                    const SizedBox(height: DesignSpace.u4),
                    _SkeletonBox(width: 168, height: 10, palette: palette),
                    const SizedBox(height: DesignSpace.u2),
                    _SkeletonBox(width: 132, height: 10, palette: palette),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
