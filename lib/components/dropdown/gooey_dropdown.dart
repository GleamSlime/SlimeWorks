import 'dart:ui';

import 'package:flutter/material.dart';

class GooeyDropdown extends StatefulWidget {
  final Widget child;
  final Widget dropdown;
  final double dropdownWidth;
  final double dropdownHeight;
  final Duration duration;

  const GooeyDropdown({
    super.key,
    required this.child,
    required this.dropdown,
    required this.dropdownWidth,
    required this.dropdownHeight,
    this.duration = const Duration(milliseconds: 450),
  });

  @override
  State<GooeyDropdown> createState() => _GooeyDropdownState();
}

class _GooeyDropdownState extends State<GooeyDropdown> with SingleTickerProviderStateMixin {
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _buttonKey = GlobalKey();

  OverlayEntry? _overlayEntry;
  late AnimationController _controller;
  late Animation<double> _expandAnim;
  late Animation<double> _fadeAnim;

  Size _buttonSize = Size.zero;
  bool _isHiding = false;

  Offset _buttonOffset = Offset.zero;
  final double _screenPadding = 8.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    _expandAnim = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _fadeAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.4, 1, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _controller.dispose();
    super.dispose();
  }

  void _showDropdown() {
    final renderBox = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    _buttonSize = renderBox.size;
    // 保存按钮在全局坐标系中的位置，用于边界检测
    _buttonOffset = renderBox.localToGlobal(Offset.zero);

    final overlay = Overlay.of(context, rootOverlay: true);

    _overlayEntry = OverlayEntry(builder: _buildOverlay);

    overlay.insert(_overlayEntry!);
    _controller.forward(from: 0);
  }

  Widget _buildOverlay(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _hideDropdown,
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            CompositedTransformFollower(
              link: _layerLink,
              // 默认向下展开，但会在绘制时根据屏幕边界做出微调
              offset: Offset.zero,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final width = lerpDouble(_buttonSize.width, widget.dropdownWidth, _expandAnim.value)!;
                  final height = widget.dropdownHeight * _expandAnim.value;

                  // 屏幕尺寸与按钮全局位置
                  final overlaySize = MediaQuery.of(context).size;
                  double dx = 0;
                  double dy = _buttonSize.height; // 默认在按钮下方

                  // 计算水平溢出：如果右侧溢出，则向左平移；如果左侧不足，则向右校正
                  final left = _buttonOffset.dx;
                  if (left + width > overlaySize.width - _screenPadding) {
                    dx = (overlaySize.width - _screenPadding) - (left + width);
                  }
                  if (left + dx < _screenPadding) {
                    dx += _screenPadding - (left + dx);
                  }

                  // 计算垂直溢出：如果向下展开会超出底部，则改为向上展开
                  final top = _buttonOffset.dy + _buttonSize.height;
                  if (top + height > overlaySize.height - _screenPadding) {
                    dy = -height; // 置于按钮上方
                    // 如果置于上方后仍超出顶部，则把它夹在可见范围内
                    if (_buttonOffset.dy + dy < _screenPadding) {
                      dy = _screenPadding - _buttonOffset.dy;
                    }
                  }

                  return Transform.translate(
                    // 将 child 移动到与 CompositedTransformFollower 对齐的位置后，再应用额外偏移修正
                    offset: Offset(dx, dy),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        color: Colors.transparent,
                        child: Container(
                          width: width,
                          height: height,
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(12 * (1 - _expandAnim.value)),
                              bottom: const Radius.circular(16),
                            ),
                            boxShadow: [BoxShadow(blurRadius: 20 * _expandAnim.value, color: Colors.black.withAlpha(38))],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: FadeTransition(
                              opacity: _fadeAnim,
                              child: Transform.translate(offset: Offset(0, 10 * (1 - _fadeAnim.value)), child: widget.dropdown),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _hideDropdown() async {
    if (_isHiding) return;
    _isHiding = true;

    try {
      await _controller.reverse();
    } catch (_) {}

    if (mounted) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    }

    _isHiding = false;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        key: _buttonKey,
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_overlayEntry == null) {
            _showDropdown();
          } else {
            _hideDropdown();
          }
        },
        child: widget.child,
      ),
    );
  }
}
