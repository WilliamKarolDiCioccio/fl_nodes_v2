import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show Matrix4;

/// Maps scene (graph) coordinates to screen coordinates and back.
///
/// `screen = scene * scale + offset`
@immutable
class ViewportTransform {
  const ViewportTransform({this.offset = Offset.zero, this.scale = 1.0});

  static const ViewportTransform identity = ViewportTransform();

  final Offset offset;
  final double scale;

  Offset toScreen(Offset scenePoint) => scenePoint * scale + offset;

  Offset toScene(Offset screenPoint) => (screenPoint - offset) / scale;

  Rect sceneRectToScreen(Rect rect) =>
      Rect.fromPoints(toScreen(rect.topLeft), toScreen(rect.bottomRight));

  Rect screenRectToScene(Rect rect) =>
      Rect.fromPoints(toScene(rect.topLeft), toScene(rect.bottomRight));

  /// The portion of the scene currently visible in a viewport of [size].
  Rect visibleSceneRect(Size size) => screenRectToScene(Offset.zero & size);

  Matrix4 toMatrix4() => Matrix4.identity()
    ..translateByDouble(offset.dx, offset.dy, 0, 1)
    ..scaleByDouble(scale, scale, 1, 1);

  /// Returns a transform zoomed to [newScale] while keeping the scene point
  /// under [focalScreenPoint] pinned in place.
  ViewportTransform zoomedAt(Offset focalScreenPoint, double newScale) {
    final scenePoint = toScene(focalScreenPoint);
    return ViewportTransform(
      offset: focalScreenPoint - scenePoint * newScale,
      scale: newScale,
    );
  }

  ViewportTransform translated(Offset screenDelta) =>
      ViewportTransform(offset: offset + screenDelta, scale: scale);

  ViewportTransform copyWith({Offset? offset, double? scale}) =>
      ViewportTransform(
        offset: offset ?? this.offset,
        scale: scale ?? this.scale,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ViewportTransform &&
          other.offset == offset &&
          other.scale == scale;

  @override
  int get hashCode => Object.hash(offset, scale);

  @override
  String toString() =>
      'ViewportTransform(offset: $offset, scale: ${scale.toStringAsFixed(3)})';
}
