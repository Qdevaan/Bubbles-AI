import 'package:flutter/material.dart';

import '../services/device_perf_tier.dart';
import 'motion_scope.dart';

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
    final perfTier = DevicePerfTier.instance.tier;
    final shimmerDuration = perfTier == PerfTier.low
        ? const Duration(milliseconds: 900)
        : const Duration(milliseconds: 1500);
    _ctrl = AnimationController(
      vsync: this,
      duration: shimmerDuration,
    )..repeat(reverse: perfTier == PerfTier.low);
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
    final reduce = MotionScope.reduceMotion(context);

    // Low-tier and reduce-motion devices fall back to a cheap opacity pulse —
    // a single AnimatedBuilder driving `Container.color.opacity` costs an
    // order of magnitude less than the per-frame gradient interpolation.
    if (reduce) {
      final pulse = Tween<double>(begin: 0.4, end: 0.85).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
      );
      return AnimatedBuilder(
        animation: pulse,
        builder: (_, __) => Container(
          width: widget.width,
          height: widget.height,
          margin: widget.margin,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            color: Color.lerp(baseColor, highlightColor, pulse.value),
          ),
        ),
      );
    }

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

/// List-tile skeleton — leading avatar + two text lines + trailing pill.
class SkeletonListTile extends StatelessWidget {
  final EdgeInsets padding;
  final bool showTrailing;

  const SkeletonListTile({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    this.showTrailing = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          const SkeletonLoader.circle(size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonLoader.line(width: 180, height: 14),
                SizedBox(height: 6),
                SkeletonLoader.line(width: 120, height: 12),
              ],
            ),
          ),
          if (showTrailing)
            const SkeletonLoader(width: 48, height: 20, borderRadius: 999),
        ],
      ),
    );
  }
}

/// Vertical column of [SkeletonListTile]s for list-style screens.
class SkeletonList extends StatelessWidget {
  final int count;
  final EdgeInsets padding;

  const SkeletonList({
    super.key,
    this.count = 6,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: padding,
      itemCount: count,
      itemBuilder: (_, __) => const SkeletonListTile(),
    );
  }
}

/// Chat message bubble skeletons — alternating left/right rows.
class SkeletonChatBubbles extends StatelessWidget {
  final int count;
  const SkeletonChatBubbles({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      itemCount: count,
      itemBuilder: (_, i) {
        final mine = i.isOdd;
        final w = 180.0 + ((i * 23) % 80);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment:
                mine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!mine) ...const [
                SkeletonLoader.circle(size: 28),
                SizedBox(width: 8),
              ],
              SkeletonLoader(width: w, height: 48, borderRadius: 18),
              if (mine) ...const [
                SizedBox(width: 8),
                SkeletonLoader.circle(size: 28),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Profile-form skeleton — centered avatar + stacked text fields.
class SkeletonProfileForm extends StatelessWidget {
  final int fieldCount;
  const SkeletonProfileForm({super.key, this.fieldCount = 4});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: SkeletonLoader.circle(size: 96)),
          const SizedBox(height: 24),
          for (int i = 0; i < fieldCount; i++) ...[
            const SkeletonLoader.line(width: 80, height: 12),
            const SizedBox(height: 8),
            const SkeletonLoader(height: 48, borderRadius: 14),
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 8),
          const SkeletonLoader(height: 52, borderRadius: 16),
        ],
      ),
    );
  }
}

/// Analytics-tab skeleton — header bar, chart block, then stat cards.
class SkeletonAnalyticsView extends StatelessWidget {
  const SkeletonAnalyticsView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        SkeletonLoader.line(width: 160, height: 18),
        SizedBox(height: 12),
        SkeletonLoader(height: 180, borderRadius: 20),
        SizedBox(height: 16),
        SkeletonLoader.line(width: 120, height: 14),
        SizedBox(height: 8),
        SkeletonCardGroup(count: 3),
        SizedBox(height: 12),
        SkeletonLoader.line(width: 140, height: 14),
        SizedBox(height: 8),
        SkeletonLoader(height: 120, borderRadius: 20),
      ],
    );
  }
}

/// Horizontal scrolling cards skeleton — matches carousel/shop layouts.
class SkeletonHorizontalCards extends StatelessWidget {
  final int count;
  final double cardWidth;
  final double height;
  final EdgeInsets padding;

  const SkeletonHorizontalCards({
    super.key,
    this.count = 4,
    this.cardWidth = 140,
    this.height = 168,
    this.padding = const EdgeInsets.symmetric(horizontal: 4),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) => SkeletonLoader(
          width: cardWidth,
          height: height,
          borderRadius: 20,
        ),
      ),
    );
  }
}

/// Dropdown-style form skeleton — header lines + tall rounded field + button.
class SkeletonDropdownForm extends StatelessWidget {
  const SkeletonDropdownForm({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          SkeletonLoader.line(width: 200, height: 22),
          SizedBox(height: 12),
          SkeletonLoader.line(width: double.infinity, height: 14),
          SkeletonLoader.line(width: 240, height: 14),
          SizedBox(height: 32),
          SkeletonLoader(height: 56, borderRadius: 16),
          SizedBox(height: 24),
          SkeletonLoader(height: 52, borderRadius: 16),
        ],
      ),
    );
  }
}

/// Splash-style skeleton — large rounded square (logo placeholder) + caption.
class SkeletonSplash extends StatelessWidget {
  const SkeletonSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SkeletonLoader(width: 96, height: 96, borderRadius: 24),
          SizedBox(height: 24),
          SkeletonLoader.line(width: 160, height: 14),
          SizedBox(height: 8),
          SkeletonLoader.line(width: 100, height: 12),
        ],
      ),
    );
  }
}
