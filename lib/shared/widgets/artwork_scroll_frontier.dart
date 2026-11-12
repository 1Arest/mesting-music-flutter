import 'dart:math' as math;
import 'package:flutter/widgets.dart';

/// Layout reports the prepared extent of each lazy vertical list. Its scroll
/// physics reads this directly, without rebuilding every row on image events.
class ArtworkScrollFrontier {
  static final _owners = Expando<ArtworkScrollFrontier>();
  static ArtworkScrollFrontier? of(ScrollMetrics metrics) =>
      metrics is ScrollPosition ? _owners[metrics] : null;
  final _fences = <ScrollPosition, ({double limit, bool waiting})>{};

  void update(
    ScrollPosition position, {
    required double preparedEnd,
    required double? pendingStart,
    required double footer,
  }) {
    if (!position.hasContentDimensions ||
        position.axisDirection != AxisDirection.down) {
      return;
    }
    final viewport = position.viewportDimension;
    _owners[position] = this;
    final end = pendingStart ?? preparedEnd;
    final preparedLimit = math.max(0.0, end - viewport + footer);
    // Even when the current cache is ready, one extreme pointer update must
    // not skip its entire laid-out cache. Normal ballistic frames keep moving
    // as subsequent ready rows extend this fence. Text-only trailing controls
    // can still be reached when no artwork is pending.
    final limit = pendingStart == null
        ? math.max(preparedLimit, position.pixels + viewport * .75)
        : preparedLimit;
    _fences[position] = (limit: limit, waiting: pendingStart != null);
  }

  void retain(Set<ScrollPosition> positions) {
    _fences.removeWhere((position, _) {
      if (positions.contains(position)) return false;
      if (identical(_owners[position], this)) _owners[position] = null;
      return true;
    });
  }

  double? limit(ScrollMetrics metrics) => metrics is ScrollPosition
      ? _fences[metrics]?.limit.clamp(
          metrics.minScrollExtent,
          metrics.maxScrollExtent,
        )
      : null;
  bool waiting(ScrollMetrics metrics) =>
      metrics is ScrollPosition && (_fences[metrics]?.waiting ?? false);
  void clear() {
    for (final position in _fences.keys) {
      if (identical(_owners[position], this)) _owners[position] = null;
    }
    _fences.clear();
  }
}

/// Restrict only forward movement into unprepared content. Upward navigation,
/// pull-to-refresh and the owner's platform physics remain available.
class ArtworkFrontierPhysics extends ScrollPhysics {
  const ArtworkFrontierPhysics({this.frontier, super.parent});
  final ArtworkScrollFrontier? frontier;
  @override
  ArtworkFrontierPhysics applyTo(ScrollPhysics? ancestor) =>
      ArtworkFrontierPhysics(frontier: frontier, parent: buildParent(ancestor));
  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    final owner = frontier ?? ArtworkScrollFrontier.of(position);
    final limit = owner?.limit(position);
    if (limit != null && value > position.pixels && value > limit) {
      return value - math.max(limit, position.pixels);
    }
    return super.applyBoundaryConditions(position, value);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final owner = frontier ?? ArtworkScrollFrontier.of(position);
    final limit = owner?.limit(position);
    if (limit != null &&
        owner!.waiting(position) &&
        velocity >= 0 &&
        position.pixels >= limit - .5) {
      return null;
    }
    return super.createBallisticSimulation(position, velocity);
  }
}
