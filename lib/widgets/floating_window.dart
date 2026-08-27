import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'morph_switch.dart';

/// 可拖拽、可缩放、带启动/展开/收缩动画的 Material 3 悬浮窗
class FloatingWindowHost extends StatefulWidget {
  const FloatingWindowHost({super.key});

  @override
  State<FloatingWindowHost> createState() => _FloatingWindowHostState();
}

class _FloatingWindowHostState extends State<FloatingWindowHost>
    with TickerProviderStateMixin {
  static const _minW = 280.0;
  static const _minH = 320.0;

  late final AnimationController _launch = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final AnimationController _expand = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );

  late final Animation<double> _launchScale = CurvedAnimation(
    parent: _launch,
    curve: Curves.easeOutBack,
  );
  late final Animation<double> _launchFade = CurvedAnimation(
    parent: _launch,
    curve: const Interval(0, 0.6, curve: Curves.easeOut),
  );

  Offset _pos = const Offset(24, 120);
  Size _size = const Size(340, 480);
  bool _showWindow = true;
  int _page = 0;

  // 选项
  bool _optNotify = true;
  bool _optDarkFab = false;
  bool _optKeepFront = true;
  bool _optHaptics = true;

  @override
  void initState() {
    super.initState();
    _launch.forward();
  }

  @override
  void dispose() {
    _launch.dispose();
    _expand.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    if (_optHaptics) HapticFeedback.lightImpact();
    if (_expand.value > 0.5) {
      _expand.reverse();
    } else {
      _expand.forward();
    }
  }

  void _openWindow() {
    if (_optHaptics) HapticFeedback.mediumImpact();
    setState(() => _showWindow = true);
    _launch
      ..value = 0
      ..forward();
    _expand.value = 1;
  }

  void _closeWindow() {
    if (_optHaptics) HapticFeedback.lightImpact();
    _launch.reverse().whenComplete(() {
      if (mounted) setState(() => _showWindow = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    final maxW = mq.size.width - 16;
    final maxH = mq.size.height - mq.padding.top - mq.padding.bottom - 16;

    return Scaffold(
      appBar: AppBar(
        title: const Text('悬浮窗演示'),
        centerTitle: true,
      ),
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          // 背景说明
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.layers_outlined, size: 56, color: cs.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Material 3 悬浮窗',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '拖动标题栏移动 · 右下角拖动调整大小\n侧边栏切换页面 · 开关带对号/叉号动画',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 24),
                  if (!_showWindow)
                    FilledButton.tonalIcon(
                      onPressed: _openWindow,
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('打开悬浮窗'),
                    ),
                ],
              ),
            ),
          ),

          // 悬浮窗
          if (_showWindow)
            Positioned(
              left: _pos.dx.clamp(0, mq.size.width - _minW),
              top: _pos.dy.clamp(mq.padding.top, mq.size.height - _minH),
              child: FadeTransition(
                opacity: _launchFade,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.85, end: 1).animate(_launchScale),
                  alignment: Alignment.bottomRight,
                  child: SizeTransition(
                    sizeFactor: CurvedAnimation(
                      parent: _expand,
                      curve: Curves.easeOutCubic,
                    ),
                    axisAlignment: -1,
                    child: _buildWindow(cs, maxW, maxH),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _AnimatedFab(
        visible: !_showWindow || _expand.value < 0.5,
        onPressed: () {
          if (!_showWindow) {
            _openWindow();
          } else {
            _expand.forward();
          }
        },
      ),
    );
  }

  Widget _buildWindow(ColorScheme cs, double maxW, double maxH) {
    final w = _size.width.clamp(_minW, maxW);
    final h = _size.height.clamp(_minH, maxH);

    return Material(
      elevation: 8,
      shadowColor: cs.shadow.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      color: cs.surfaceContainerHigh,
      child: SizedBox(
        width: w,
        height: h,
        child: Column(
          children: [
            // 标题栏（拖动）
            GestureDetector(
              onPanUpdate: (d) {
                setState(() {
                  _pos += d.delta;
                });
              },
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '收起',
                      icon: AnimatedRotation(
                        turns: _expand.value > 0.5 ? 0 : 0.5,
                        duration: const Duration(milliseconds: 280),
                        child: const Icon(Icons.expand_more_rounded),
                      ),
                      onPressed: _toggleExpand,
                    ),
                    Expanded(
                      child: Text(
                        'Morph 悬浮窗',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: _closeWindow,
                    ),
                  ],
                ),
              ),
            ),
            // 主体：侧栏 + 内容
            Expanded(
              child: Row(
                children: [
                  _SideRail(
                    selected: _page,
                    onSelect: (i) {
                      if (_optHaptics) HapticFeedback.selectionClick();
                      setState(() => _page = i);
                    },
                  ),
                  VerticalDivider(width: 1, color: cs.outlineVariant),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, anim) {
                        return FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.06, 0),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey(_page),
                        child: _pageBody(cs),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 缩放手柄
            Align(
              alignment: Alignment.bottomRight,
              child: GestureDetector(
                onPanUpdate: (d) {
                  setState(() {
                    _size = Size(
                      (_size.width + d.delta.dx).clamp(_minW, maxW),
                      (_size.height + d.delta.dy).clamp(_minH, maxH),
                    );
                  });
                },
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: CustomPaint(
                    painter: _ResizeHandlePainter(color: cs.outline),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageBody(ColorScheme cs) {
    switch (_page) {
      case 0:
        return _HomePane(cs: cs);
      case 1:
        return _OptionsPane(
          notify: _optNotify,
          darkFab: _optDarkFab,
          keepFront: _optKeepFront,
          haptics: _optHaptics,
          onNotify: (v) => setState(() => _optNotify = v),
          onDarkFab: (v) => setState(() => _optDarkFab = v),
          onKeepFront: (v) => setState(() => _optKeepFront = v),
          onHaptics: (v) => setState(() => _optHaptics = v),
        );
      case 2:
        return _AboutPane(cs: cs);
      default:
        return const SizedBox.shrink();
    }
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, '主页'),
    (Icons.tune_outlined, Icons.tune_rounded, '选项'),
    (Icons.info_outline_rounded, Icons.info_rounded, '关于'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return NavigationRail(
      selectedIndex: selected,
      onDestinationSelected: onSelect,
      labelType: NavigationRailLabelType.selected,
      backgroundColor: cs.surfaceContainerHigh,
      destinations: [
        for (final e in _items)
          NavigationRailDestination(
            icon: Icon(e.$1),
            selectedIcon: Icon(e.$2),
            label: Text(e.$3),
          ),
      ],
    );
  }
}

class _HomePane extends StatelessWidget {
  const _HomePane({required this.cs});
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('快速操作', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in [
              (Icons.public_rounded, '浏览'),
              (Icons.bookmark_rounded, '收藏'),
              (Icons.history_rounded, '历史'),
              (Icons.download_rounded, '下载'),
            ])
              ActionChip(
                avatar: Icon(e.$1, size: 18),
                label: Text(e.$2),
                onPressed: () {},
              ),
          ],
        ),
        const SizedBox(height: 20),
        Card(
          elevation: 0,
          color: cs.primaryContainer.withValues(alpha: 0.45),
          child: ListTile(
            leading: Icon(Icons.animation_rounded, color: cs.primary),
            title: const Text('动画已启用'),
            subtitle: const Text('启动、展开、收缩、切页均带过渡'),
          ),
        ),
      ],
    );
  }
}

class _OptionsPane extends StatelessWidget {
  const _OptionsPane({
    required this.notify,
    required this.darkFab,
    required this.keepFront,
    required this.haptics,
    required this.onNotify,
    required this.onDarkFab,
    required this.onKeepFront,
    required this.onHaptics,
  });

  final bool notify, darkFab, keepFront, haptics;
  final ValueChanged<bool> onNotify, onDarkFab, onKeepFront, onHaptics;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _switchTile(
          context,
          icon: Icons.notifications_outlined,
          title: '通知提示',
          subtitle: '操作完成时提示',
          value: notify,
          onChanged: onNotify,
        ),
        _switchTile(
          context,
          icon: Icons.dark_mode_outlined,
          title: '强调色悬浮按钮',
          subtitle: 'FAB 使用主色填充',
          value: darkFab,
          onChanged: onDarkFab,
        ),
        _switchTile(
          context,
          icon: Icons.push_pin_outlined,
          title: '保持前置',
          subtitle: '演示用选项',
          value: keepFront,
          onChanged: onKeepFront,
        ),
        _switchTile(
          context,
          icon: Icons.vibration_rounded,
          title: '触感反馈',
          subtitle: '切换与拖动时震动',
          value: haptics,
          onChanged: onHaptics,
        ),
      ],
    );
  }

  Widget _switchTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: MorphSwitch(value: value, onChanged: onChanged),
      onTap: () => onChanged(!value),
    );
  }
}

class _AboutPane extends StatelessWidget {
  const _AboutPane({required this.cs});
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: cs.primaryContainer,
          child: Icon(Icons.layers_rounded, color: cs.onPrimaryContainer, size: 32),
        ),
        const SizedBox(height: 12),
        Text('Morph 悬浮窗', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Material 3 · 可拖拽 · 可缩放 · 侧栏切页',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.check_circle_outline),
          title: Text('启动缩放 + 淡入'),
        ),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.check_circle_outline),
          title: Text('展开 / 收缩高度动画'),
        ),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.check_circle_outline),
          title: Text('开关对号 / 叉号动画'),
        ),
      ],
    );
  }
}

class _ResizeHandlePainter extends CustomPainter {
  _ResizeHandlePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const pad = 10.0;
    canvas.drawLine(
      Offset(size.width - pad, size.height - 4),
      Offset(size.width - 4, size.height - pad),
      p,
    );
    canvas.drawLine(
      Offset(size.width - pad - 5, size.height - 4),
      Offset(size.width - 4, size.height - pad - 5),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _ResizeHandlePainter old) => old.color != color;
}

class _AnimatedFab extends StatefulWidget {
  const _AnimatedFab({required this.onPressed, required this.visible});
  final VoidCallback onPressed;
  final bool visible;

  @override
  State<_AnimatedFab> createState() => _AnimatedFabState();
}

class _AnimatedFabState extends State<_AnimatedFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: widget.visible ? 1 : 0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_c.value);
          return Transform.rotate(
            angle: (t - 0.5) * 0.12,
            child: child,
          );
        },
        child: FloatingActionButton.extended(
          onPressed: widget.onPressed,
          icon: const Icon(Icons.layers_rounded),
          label: const Text('悬浮窗'),
        ),
      ),
    );
  }
}
