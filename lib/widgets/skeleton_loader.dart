import 'package:flutter/material.dart';

/// Shimmer skeleton loader for content that's still loading.
/// Provides a premium loading experience instead of plain spinners.
class SkeletonLoader extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;
  final EdgeInsets? margin;

  const SkeletonLoader({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 12,
    this.margin,
  });

  /// Card-shaped skeleton matching quick-action / insight cards.
  const SkeletonLoader.card({
    super.key,
    this.width = double.infinity,
    this.height = 100,
    this.borderRadius = 24,
    this.margin = const EdgeInsets.only(bottom: 8),
  });

  /// Small circular skeleton for avatars or icons.
  const SkeletonLoader.circle({
    super.key,
    required double size,
    this.margin,
  })  : width = size,
        height = size,
        borderRadius = 9999;

  /// Text-line skeleton.
  const SkeletonLoader.line({
    super.key,
    this.width = 120,
    this.height = 14,
    this.borderRadius = 6,
    this.margin = const EdgeInsets.only(bottom: 6),
  });

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _shimmer = Tween(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        isDark ? Colors.white.withAlpha(13) : Colors.grey.shade200;
    final highlightColor =
        isDark ? Colors.white.withAlpha(26) : Colors.grey.shade100;

    return AnimatedBuilder(
      animation: _shimmer,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        margin: widget.margin,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          gradient: LinearGradient(
            begin: Alignment(_shimmer.value - 1, 0),
            end: Alignment(_shimmer.value, 0),
            colors: [baseColor, highlightColor, baseColor],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }
}

/// A group of skeleton loaders that mimics a typical card layout.
class SkeletonCardGroup extends StatelessWidget {
  final int count;

  const SkeletonCardGroup({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(count, (i) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SkeletonLoader.circle(size: 32),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonLoader.line(width: 100 + (i * 20).toDouble()),
                      const SkeletonLoader.line(width: 60),
                    ],
                  ),
                  const Spacer(),
                  const SkeletonLoader(
                      width: 60, height: 22, borderRadius: 999),
                ],
              ),
              const SizedBox(height: 8),
              const SkeletonLoader.line(width: double.infinity),
              const SkeletonLoader.line(width: 200),
              const SizedBox(height: 4),
            ],
          ),
        );
      }),
    );
  }
}
