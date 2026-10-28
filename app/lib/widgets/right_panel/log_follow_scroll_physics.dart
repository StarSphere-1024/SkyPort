import 'package:flutter/widgets.dart';

/// Anchor to the layout's current end before painting, not an estimated end
/// from the previous frame. User scrolling and search navigation opt out.
class LogFollowScrollPhysics extends ScrollPhysics {
  const LogFollowScrollPhysics({required this.shouldFollow, super.parent});

  final bool Function() shouldFollow;

  @override
  LogFollowScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      LogFollowScrollPhysics(
        shouldFollow: shouldFollow,
        parent: buildParent(ancestor),
      );

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    if (shouldFollow()) return newPosition.maxScrollExtent;
    return super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
  }
}
