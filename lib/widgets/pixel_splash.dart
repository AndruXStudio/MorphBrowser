import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 类似新版 Pixel 开机：黑底 + 呼吸/旋转色点汇聚成 G 风格标记
class PixelSplash extends StatefulWidget {
  const PixelSplash({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<PixelSplash> createState() => _PixelSplashState();
}

class _PixelSplashState extends State<PixelSplash>
    with TickerProviderStateMixin {
  late final AnimationController _main = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final Animation<double> _scale = CurvedAnimation(
    parent: _main,
    curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
  );
  late final Animation<double> _fadeOut = CurvedAnimation(
    parent: _main,
    curve: const Interval(0.75, 1.0, curve: Curves.easeIn),
  );

  @override
  void initState() {
    super.initState();
    _main.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _main.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: Listenable.merge([_main, _pulse]),
        builder: (context, _) {
          final opacity = 1.0 - _fadeOut.value;
          return Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Center(
              child: Transform.scale(
                scale: 0.6 + _scale.value * 0.5,
                child: SizedBox(
                  width: 120,
                  height: 120,
                  child: CustomPaint(
                    painter: _PixelGPainter(
                      progress: _scale.value,
                      pulse: _pulse.value,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PixelGPainter extends CustomPainter {
  _PixelGPainter({required this.progress, required this.pulse});

  final double progress;
  final double pulse;

  static const _colors = [
    Color(0xFF4285F4),
    Color(0xFFEA4335),
    Color(0xFFFBBC05),
    Color(0xFF34A853),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide * 0.38;
    final paint = Paint()..style = PaintingStyle.fill;

    // 外圈色点
    for (var i = 0; i < 8; i++) {
      final ang = (i / 8) * math.pi * 2 - math.pi / 2 + progress * math.pi * 0.5;
      final dist = r * (1.15 - progress * 0.35) * (0.92 + pulse * 0.08);
      final p = c + Offset(math.cos(ang) * dist, math.sin(ang) * dist);
      paint.color = _colors[i % 4].withValues(alpha: 0.55 + progress * 0.45);
      canvas.drawCircle(p, 5 + progress * 3, paint);
    }

    // 中心环
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = Color.lerp(
            _colors[0],
            Colors.white,
            (1 - progress).clamp(0, 1),
          )!
          .withValues(alpha: 0.9);
    final sweep = progress * math.pi * 1.7;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.55),
      -math.pi / 2,
      sweep,
      false,
      ring,
    );

    // 中心点
    paint.color = Colors.white.withValues(alpha: progress);
    canvas.drawCircle(c, 6 * progress, paint);
  }

  @override
  bool shouldRepaint(covariant _PixelGPainter old) =>
      old.progress != progress || old.pulse != pulse;
}
