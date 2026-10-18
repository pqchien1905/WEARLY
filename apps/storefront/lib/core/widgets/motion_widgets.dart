import 'package:flutter/material.dart';
import '../design/motion.dart';
import '../design/tokens.dart';

/// One finite entrance per route. No outgoing route is retained, so forms and
/// global anchors never exist twice during navigation.
class PageReveal extends StatefulWidget {
  const PageReveal({super.key, required this.child});
  final Widget child;

  @override
  State<PageReveal> createState() => _PageRevealState();
}

class _PageRevealState extends State<PageReveal>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: Motion.fast,
  );
  late final opacity = controller.drive(CurveTween(curve: Motion.curve));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      controller.value = 1;
    } else if (controller.isDismissed) {
      controller.forward();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: opacity,
    alwaysIncludeSemantics: true,
    child: widget.child,
  );
}

/// Image-only hover zoom, bounded by its frame. Focus has an independent,
/// visible outline and the same keyboard activation as a regular button.
class InteractivePhoto extends StatefulWidget {
  const InteractivePhoto({super.key, required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  State<InteractivePhoto> createState() => _InteractivePhotoState();
}

class _InteractivePhotoState extends State<InteractivePhoto> {
  bool hovered = false, focused = false;

  @override
  Widget build(BuildContext context) => Material(
    color: T.photo,
    child: InkWell(
      onTap: widget.onTap,
      onHover: (value) => setState(() => hovered = value),
      onFocusChange: (value) => setState(() => focused = value),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: AnimatedScale(
              scale: hovered && !Motion.reduced(context) ? 1.025 : 1,
              duration: Motion.duration(context),
              curve: Motion.curve,
              child: widget.child,
            ),
          ),
          if (focused)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: T.accent, width: 3),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
