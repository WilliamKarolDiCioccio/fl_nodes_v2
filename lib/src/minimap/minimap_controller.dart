import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';

/// The minimap panel's own state: where it sits, how big it is, whether it is
/// folded away, and what it draws.
///
/// A notifier of its own rather than state on the editor, for two reasons.
/// Moving the panel must not notify `NodeEditorController` — the editor listens
/// for itself, and a notify there rebuilds the whole canvas for something no
/// node cares about. And a host that wants the placement to survive a restart
/// can own one of these and write it into its own document; the editor makes
/// one when it is given none, so the opt-in stays a single line.
///
/// Every setter follows `NodeEditorCamera.viewport`'s idiom: compare, assign,
/// notify. There is no revision counter, because nothing here is expensive
/// enough to need one.
class MinimapController extends ChangeNotifier {
  MinimapController({
    Offset? position,
    Size size = defaultSize,
    bool minimised = false,
    double maxScale = defaultMaxScale,
    bool showConnections = true,
    bool showGroups = true,
    bool showComments = true,
    double idleOpacity = defaultIdleOpacity,
  }) : _position = position,
       _size = size,
       _minimised = minimised,
       _maxScale = _clampScale(maxScale),
       _showConnections = showConnections,
       _showGroups = showGroups,
       _showComments = showComments,
       _idleOpacity = idleOpacity.clamp(0.0, 1.0);

  static const Size defaultSize = Size(240, 160);
  static const double defaultMaxScale = 0.2;
  static const double defaultIdleOpacity = 0.28;

  /// Height of the action bar, which is also the panel's height when folded.
  static const double barHeight = 26;

  Offset? _position;
  Size _size;
  bool _minimised;
  double _maxScale;
  bool _showConnections;
  bool _showGroups;
  bool _showComments;
  double _idleOpacity;

  /// Top-left of the panel in the editor's screen space, or null while it is
  /// still where `MinimapConfig.alignment` put it.
  ///
  /// Deliberately *not* written by the clamp that keeps the panel inside a
  /// viewport that shrank: a window narrowed and widened again then puts the
  /// panel back where it was put, rather than where the narrow window shoved
  /// it. Null also means a resized window keeps an untouched panel in its
  /// corner instead of stranding it mid-canvas.
  Offset? get position => _position;

  set position(Offset? value) {
    if (value == _position) return;
    _position = value;
    notifyListeners();
  }

  Size get size => _size;

  set size(Size value) {
    final clamped = Size(math.max(1, value.width), math.max(1, value.height));
    if (clamped == _size) return;
    _size = clamped;
    notifyListeners();
  }

  /// Folded to the action bar alone, with no map drawn.
  bool get minimised => _minimised;

  set minimised(bool value) {
    if (value == _minimised) return;
    _minimised = value;
    notifyListeners();
  }

  void toggleMinimised() => minimised = !_minimised;

  /// Ceiling on the map's scene-to-map scale.
  ///
  /// Without it a three-node graph fitted to the panel renders as three
  /// enormous slabs and the map says nothing about shape. It is only ever a
  /// ceiling — fitting takes the smaller of the two — so it can never push
  /// content off the map.
  double get maxScale => _maxScale;

  set maxScale(double value) {
    final clamped = _clampScale(value);
    if (clamped == _maxScale) return;
    _maxScale = clamped;
    notifyListeners();
  }

  bool get showConnections => _showConnections;

  set showConnections(bool value) {
    if (value == _showConnections) return;
    _showConnections = value;
    notifyListeners();
  }

  bool get showGroups => _showGroups;

  set showGroups(bool value) {
    if (value == _showGroups) return;
    _showGroups = value;
    notifyListeners();
  }

  bool get showComments => _showComments;

  set showComments(bool value) {
    if (value == _showComments) return;
    _showComments = value;
    notifyListeners();
  }

  /// How solid the panel is while nothing is hovering it.
  double get idleOpacity => _idleOpacity;

  set idleOpacity(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if (clamped == _idleOpacity) return;
    _idleOpacity = clamped;
    notifyListeners();
  }

  static double _clampScale(double value) =>
      value.isFinite ? value.clamp(0.01, 1.0) : defaultMaxScale;
}
