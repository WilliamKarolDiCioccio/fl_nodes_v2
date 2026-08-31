part of 'node_editor_controller.dart';

/// The view onto the scene: pan, zoom, framing.
///
/// Camera changes deliberately do not bump [NodeEditorController.revision].
/// Scene-space geometry — connection paths above all — survives panning and
/// zooming untouched, and rebuilding it on every scroll tick is the single
/// most expensive thing a naive node editor does.
class NodeEditorCamera {
  NodeEditorCamera(this._controller, ViewportTransform viewport)
    : _viewport = viewport;

  final NodeEditorController _controller;

  ViewportTransform _viewport;

  double _minScale = 0.05;
  double _maxScale = 8.0;

  ViewportTransform get viewport => _viewport;

  set viewport(ViewportTransform value) {
    final clamped = value.copyWith(
      scale: value.scale.clamp(_minScale, _maxScale),
    );
    if (clamped == _viewport) return;
    _viewport = clamped;
    _controller._notify();
  }

  double get minScale => _minScale;
  double get maxScale => _maxScale;

  /// Applied by the editor from its theme so programmatic zoom obeys the same
  /// limits as pinch and scroll.
  ///
  /// Deliberately silent: the editor calls this while mounting or updating,
  /// and notifying then would mark already-built ancestors dirty. The caller
  /// is about to rebuild regardless.
  void setScaleLimits(double min, double max) {
    if (min == _minScale && max == _maxScale) return;
    _minScale = min;
    _maxScale = max;
    final clamped = _viewport.scale.clamp(min, max);
    if (clamped != _viewport.scale) {
      _viewport = _viewport.copyWith(scale: clamped);
    }
  }

  void panBy(Offset screenDelta) {
    if (screenDelta == Offset.zero) return;
    viewport = _viewport.translated(screenDelta);
  }

  /// Multiplies the zoom, keeping [focalScreenPoint] pinned when given.
  void zoomBy(double factor, {Offset? focalScreenPoint}) =>
      setScale(_viewport.scale * factor, focalScreenPoint: focalScreenPoint);

  void setScale(double scale, {Offset? focalScreenPoint}) {
    final target = scale.clamp(_minScale, _maxScale);
    if (target == _viewport.scale) return;
    viewport = focalScreenPoint == null
        ? _viewport.copyWith(scale: target)
        : _viewport.zoomedAt(focalScreenPoint, target);
  }

  void reset() => viewport = ViewportTransform.identity;

  /// Frames the whole graph inside a viewport of [viewportSize].
  void fitToContent(
    Size viewportSize, {
    EdgeInsets padding = const EdgeInsets.all(48),
    double maxScale = 1.0,
  }) {
    final bounds = _controller._graph.contentBounds(_controller.layout.sizeOf);
    if (bounds == null || viewportSize.isEmpty) return;

    final available = Size(
      math.max(1, viewportSize.width - padding.horizontal),
      math.max(1, viewportSize.height - padding.vertical),
    );
    final double fitted = math.min(
      available.width / math.max(bounds.width, 1.0),
      available.height / math.max(bounds.height, 1.0),
    );
    final double scale = fitted
        .clamp(_minScale, math.min(_maxScale, maxScale))
        .toDouble();

    _setCentered(bounds.center, scale, viewportSize);
  }

  /// Centres the view on a scene point without changing the zoom.
  void centerOn(Offset sceneCenter, Size viewportSize) =>
      _setCentered(sceneCenter, _viewport.scale, viewportSize);

  /// Centres the view on the whole graph without changing the zoom.
  ///
  /// Unlike [fitToContent] this only moves the camera, so a canvas somebody
  /// has deliberately zoomed into comes back to the content at the zoom they
  /// chose rather than at whatever framing happens to fit.
  void centerOnContent(Size viewportSize) {
    final bounds = _controller._graph.contentBounds(_controller.layout.sizeOf);
    if (bounds == null || viewportSize.isEmpty) return;
    _setCentered(bounds.center, _viewport.scale, viewportSize);
  }

  /// Centres the view on a node without changing the zoom.
  void centerOnNode(String id, Size viewportSize) {
    final node = _controller._graph.nodes[id];
    if (node == null) return;
    _setCentered(
      node.rect(_controller.layout.sizeOf(node)).center,
      _viewport.scale,
      viewportSize,
    );
  }

  void _setCentered(Offset sceneCenter, double scale, Size viewportSize) {
    viewport = ViewportTransform(
      offset:
          Offset(viewportSize.width / 2, viewportSize.height / 2) -
          sceneCenter * scale,
      scale: scale,
    );
  }
}
