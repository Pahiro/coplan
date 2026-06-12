import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

export 'package:flutter_staggered_animations/flutter_staggered_animations.dart'
    show AnimationLimiter;

/// Shared motion primitives for the M3 polish pass. All durations stay in the
/// 200–300 ms band and respect the system reduce-motion setting.

/// An [IndexedStack] whose incoming tab plays a fade-through entrance
/// (fade + slight scale-up) when the index changes, while every tab keeps its
/// state alive — unlike a real switcher, nothing is disposed.
class FadeThroughIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;

  const FadeThroughIndexedStack({
    super.key,
    required this.index,
    required this.children,
  });

  @override
  State<FadeThroughIndexedStack> createState() =>
      _FadeThroughIndexedStackState();
}

class _FadeThroughIndexedStackState extends State<FadeThroughIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
    value: 1,
  );

  @override
  void didUpdateWidget(FadeThroughIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index &&
        !MediaQuery.of(context).disableAnimations) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween(begin: 0.98, end: 1.0).animate(curved),
        child: IndexedStack(index: widget.index, children: widget.children),
      ),
    );
  }
}

/// Wraps a list item in the standard staggered entrance (fade + 24px rise).
/// Pass the item's [position] in the list. No-op under reduce motion.
Widget staggeredItem(BuildContext context,
    {required int position, required Widget child}) {
  if (MediaQuery.of(context).disableAnimations) return child;
  return AnimationConfiguration.staggeredList(
    position: position,
    duration: const Duration(milliseconds: 300),
    child: SlideAnimation(
      verticalOffset: 24,
      child: FadeInAnimation(child: child),
    ),
  );
}

/// Cross-fades (with a slight scale) between children when [child]'s key
/// changes — used for small state chips like the day-owner badge.
class CrossFadeSwitcher extends StatelessWidget {
  final Widget child;
  const CrossFadeSwitcher({super.key, required this.child});

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: ScaleTransition(
              scale: Tween(begin: 0.95, end: 1.0).animate(a), child: c),
        ),
        child: child,
      );
}
