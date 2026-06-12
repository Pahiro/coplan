import 'package:flutter/material.dart';

/// Pulsing skeleton placeholders shown while lists load — shaped like the
/// content they stand in for, instead of a centered spinner.

class _SkeletonPulse extends StatefulWidget {
  final Widget child;
  const _SkeletonPulse({required this.child});

  @override
  State<_SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<_SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    final reduceMotion = WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (reduceMotion) {
      _controller.value = 1;
    } else {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.45, end: 1.0).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
        child: widget.child,
      );
}

/// A rounded placeholder block in the skeleton tone.
class SkeletonBox extends StatelessWidget {
  final double height;
  final double? width;
  final double radius;

  const SkeletonBox({super.key, required this.height, this.width, this.radius = 12});

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

/// Card-shaped skeleton list standing in for timeline cards / expense tiles.
class SkeletonList extends StatelessWidget {
  final int count;
  final double itemHeight;
  final EdgeInsets padding;

  const SkeletonList({
    super.key,
    this.count = 5,
    this.itemHeight = 76,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 88),
  });

  @override
  Widget build(BuildContext context) => _SkeletonPulse(
        child: ListView.separated(
          padding: padding,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: count,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => SkeletonBox(
            height: itemHeight,
            // Vary widths slightly so it reads as content, not bars.
            width: null,
          ),
        ),
      );
}
