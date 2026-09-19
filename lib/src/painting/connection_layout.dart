import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show listEquals;

import '../collections/spatial_hash_grid.dart';
import '../controller/node_editor_controller.dart';
import '../geometry/connection_path.dart';
import '../geometry/connection_router.dart';
import '../model/node_connection.dart';
import '../model/node_port.dart';
import '../prototype/node_prototype_registry.dart';

/// Cached geometry for one connection, in scene coordinates.
class ConnectionGeometry {
  ConnectionGeometry({
    required this.path,
    required this.bounds,
    required this.endpoints,
    required this.connection,
    required this.labelAnchor,
    required this.arrows,
    this.caption,
  });

  final Path path;

  /// Bounds of the curve, used to cull and to reject hit tests cheaply.
  final Rect bounds;

  /// Direction markers spaced along the curve, sampled once here rather than
  /// on every paint: walking a path's metrics is not something to do per
  /// frame, and they only move when the curve does.
  final List<PathArrow> arrows;

  /// The two port positions this curve was built from.
  ///
  /// Kept so [ConnectionLayout.sync] can tell, without rebuilding anything,
  /// whether the curve still describes where its ends are.
  final ConnectionEndpoints endpoints;

  /// The connection instance this was built from, for the same reason: the
  /// caption is derived from it, and it is immutable, so an unchanged instance
  /// means an unchanged caption.
  final NodeConnection connection;

  /// Scene position of the receiving port, where the arrowhead points.
  Offset get end => endpoints.to;
  PortSide get endSide => endpoints.toSide;

  /// Midpoint of the curve, or null when nothing is captioned there.
  final Offset? labelAnchor;

  /// The caption text, resolved once here rather than on every paint.
  ///
  /// Null for a link that shows none. A captionable link with no caption yet
  /// is also null — the placeholder is the painter's business, not the cache's.
  final String? caption;
}

/// Filled direction markers for [arrows], in scene units.
///
/// Shared rather than written twice: [ConnectionsPainter] draws every wire and
/// [EmphasisPainter] redraws the lifted ones above the focus scrim, and two
/// copies of this triangle would be identical the day they were written and
/// different the first time either learned something — the same argument the
/// caches here already make about geometry.
///
/// [skip] is asked with each marker's *scene* position and drops the ones that
/// would land under something: a caption sits at the midpoint, which is
/// exactly where an odd-numbered run puts one.
Path arrowheadsPath(
  List<PathArrow> arrows,
  double size, {
  bool Function(Offset scenePosition)? skip,
}) {
  final path = Path();
  for (final arrow in arrows) {
    if (skip != null && skip(arrow.position)) continue;
    // Centred on the sample, so the head reads as sitting on the wire rather
    // than hanging off it.
    final direction = arrow.direction;
    final tip = arrow.position + direction * (size * 0.5);
    final base = arrow.position - direction * (size * 0.5);
    final across = Offset(-direction.dy, direction.dx) * (size * 0.42);
    path
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(base.dx + across.dx, base.dy + across.dy)
      ..lineTo(base.dx - across.dx, base.dy - across.dy)
      ..close();
  }
  return path;
}

/// How wide a direction marker is drawn at [scale], in scene units.
double arrowheadSize(double scale) => 9.0 * math.min(scale, 1.4) / scale;

/// Builds connection paths once and keeps them until the graph changes.
///
/// Paths are held in *scene* space on purpose. Screen-space paths would have
/// to be rebuilt on every pan and zoom, and rebuilding a bezier per connection
/// per frame is the single most expensive thing a naive node editor does — it
/// also shows up on plain mouse-over, since picking a connection needs the
/// same paths. Keeping them in scene space means the cache only turns over
/// when node geometry actually moves.
class ConnectionLayout {
  ConnectionLayout({
    this.style = ConnectionStyle.curved,
    this.curvature = ConnectionPath.defaultCurvature,
    this.stub = ConnectionPath.defaultStub,
    this.cornerRadius = ConnectionPath.defaultCornerRadius,
    this.arrowSpacing = 140,
    this.maxArrows = 4,
    double spatialCellSize = 512,
  }) : _index = SpatialHashGrid(cellSize: spatialCellSize);

  /// How every wire is drawn. Fed from the theme, like the rest.
  ConnectionStyle style;
  double curvature;
  double stub;
  double cornerRadius;

  /// Scene distance aimed for between a connection's direction arrows, and the
  /// ceiling on how many one connection gets. Fed from the theme.
  double arrowSpacing;
  int maxArrows;

  /// Curve bounds, indexed so culling and hover picking do not walk every edge
  /// in the graph. Hover runs on every mouse move, so this is the hot one.
  final SpatialHashGrid _index;

  final Map<String, ConnectionGeometry> _geometry =
      <String, ConnectionGeometry>{};
  int _revision = -1;
  ConnectionStyle? _builtStyle;
  double _builtCurvature = double.nan;
  double _builtStub = double.nan;
  double _builtCornerRadius = double.nan;
  double _builtArrowSpacing = double.nan;
  int _builtMaxArrows = -1;
  NodePrototypeRegistry? _builtRegistry;

  /// Whether the settings a curve was built under still hold. All of them are
  /// baked into the cached path or its arrows, so a change to any is the one
  /// case with nothing to reuse.
  bool get _settingsHold =>
      _builtStyle == style &&
      _builtCurvature == curvature &&
      _builtStub == stub &&
      _builtCornerRadius == cornerRadius &&
      _builtArrowSpacing == arrowSpacing &&
      _builtMaxArrows == maxArrows;

  /// Number of cached connections, for diagnostics and tests.
  int get length => _geometry.length;

  /// How many times the cache has actually been rebuilt.
  int get rebuildCount => _rebuildCount;
  int _rebuildCount = 0;

  /// How many individual curves have been built, across every [sync].
  ///
  /// The one to watch: [rebuildCount] counts passes over the graph, this
  /// counts the work they did. Dragging one node in a thousand-link document
  /// should move this by the handful of links attached to it.
  int get pathBuildCount => _pathBuildCount;
  int _pathBuildCount = 0;

  ConnectionGeometry? operator [](String id) => _geometry[id];

  Iterable<MapEntry<String, ConnectionGeometry>> get entries =>
      _geometry.entries;

  /// Rebuilds if [controller] has moved on since the last call. Cheap to call
  /// every frame.
  ///
  /// A pass costs a walk over the connections; only the curves whose ends
  /// actually moved are rebuilt. That distinction is what keeps a node drag
  /// off the size of the document — the revision bumps on every pointer move,
  /// but the bezier is the expensive part and a node on the far side of the
  /// canvas has not gone anywhere.
  void sync(NodeEditorController controller) {
    if (_revision == controller.revision && _settingsHold) {
      return;
    }
    _revision = controller.revision;
    _rebuildCount++;

    final graph = controller.graph;
    final registry = controller.prototypes;
    // Curvature is baked into every path and the registry decides every
    // caption, so a change to either is the one case with nothing to reuse.
    final reusable = _settingsHold && identical(_builtRegistry, registry);
    _builtStyle = style;
    _builtCurvature = curvature;
    _builtStub = stub;
    _builtCornerRadius = cornerRadius;
    _builtArrowSpacing = arrowSpacing;
    _builtMaxArrows = maxArrows;
    _builtRegistry = registry;

    final router = ConnectionRouter(
      graph: graph,
      // Anchors, not boxes — see `NodeEditorLayout.anchorSizeOf`.
      sizeOf: controller.layout.anchorSizeOf,
      style: style,
      curvature: curvature,
      stub: stub,
      cornerRadius: cornerRadius,
    );

    if (!reusable) {
      _geometry.clear();
      _index.clear();
    } else if (_geometry.length != graph.connections.length) {
      _geometry.removeWhere((id, _) {
        if (graph.connections.containsKey(id)) return false;
        _index.remove(id);
        return true;
      });
    }

    for (final connection in graph.connections.values) {
      final ends = router.endpointsOf(connection);
      if (ends == null) {
        // A dangling connection keeps no geometry, and must not keep a stale
        // one either: it would still be drawn, and still be clickable.
        if (_geometry.remove(connection.id) != null) {
          _index.remove(connection.id);
        }
        continue;
      }

      // The caption is asked for every time. It is cheap, and it is derived
      // through the registry from the whole graph — a port's label, most
      // often, which lives on a node and so leaves the endpoints untouched
      // when it changes. Guessing it unchanged from the geometry would leave
      // a stale caption on screen.
      final caption = registry.captionOf(graph, connection);

      final cached = _geometry[connection.id];
      // The waypoints are part of the key: a handle dragged along a wire
      // moves neither of its ends, and a curve kept on the ends alone would
      // stay put under the pointer — the caption trap again, from the other
      // side.
      final samePath =
          cached != null &&
          cached.endpoints == ends &&
          listEquals(cached.connection.waypoints, connection.waypoints);
      if (samePath &&
          cached.caption == caption &&
          identical(cached.connection, connection)) {
        continue;
      }

      // The curve and its bounds depend on nothing but the two endpoints and
      // the waypoints, and they are the expensive half by an order of
      // magnitude: a node moving on the far side of the document leaves this
      // curve exactly as it was.
      final path = samePath
          ? cached.path
          : ConnectionPath.build(
              ends.from,
              ends.to,
              fromSide: ends.fromSide,
              toSide: ends.toSide,
              via: connection.waypoints,
              style: style,
              curvature: curvature,
              stub: stub,
              cornerRadius: cornerRadius,
            );
      if (!samePath) _pathBuildCount++;
      final arrows = samePath
          ? cached.arrows
          : ConnectionPath.arrowsAlong(
              path,
              spacing: arrowSpacing,
              maxCount: maxArrows,
              axisAligned: style == ConnectionStyle.orthogonal,
            );

      // A captionable link needs an anchor even before it has a caption, or
      // there would be nothing on screen to tap to give it one.
      final captioned =
          (caption?.isNotEmpty ?? false) ||
          registry.allowsLabelEditing(connection);

      final geometry = ConnectionGeometry(
        path: path,
        bounds: samePath ? cached.bounds : path.getBounds(),
        endpoints: ends,
        connection: connection,
        arrows: arrows,
        labelAnchor: captioned
            ? (samePath && cached.labelAnchor != null
                  ? cached.labelAnchor
                  : ConnectionPath.midpoint(path))
            : null,
        caption: caption,
      );
      _geometry[connection.id] = geometry;
      _index.put(connection.id, geometry.bounds);
    }
  }

  /// Drops every cached path, forcing a full rebuild on the next [sync].
  void invalidate() {
    _revision = -1;
    _builtRegistry = null;
  }

  /// Ids whose curve bounds intersect [sceneRect].
  Set<String> idsIn(Rect sceneRect) => _index.queryRect(sceneRect);

  /// Geometry for every connection whose bounds meet [sceneRect].
  Iterable<MapEntry<String, ConnectionGeometry>> entriesIn(
    Rect sceneRect,
  ) sync* {
    for (final id in _index.queryRect(sceneRect)) {
      final geometry = _geometry[id];
      if (geometry != null) {
        yield MapEntry<String, ConnectionGeometry>(id, geometry);
      }
    }
  }

  /// The closest connection within [tolerance] of [scenePoint], or null.
  ///
  /// Both are in scene units — divide a screen-space tolerance by the viewport
  /// scale before calling. The index narrows the field to the few curves whose
  /// bounds straddle the pointer; only those pay for path sampling.
  String? hitTest(Offset scenePoint, {required double tolerance}) {
    String? best;
    var bestDistance = double.infinity;

    final probe = Rect.fromCircle(center: scenePoint, radius: tolerance);
    for (final id in _index.queryRect(probe)) {
      final geometry = _geometry[id]!;
      final distance = ConnectionPath.distanceTo(
        geometry.path,
        scenePoint,
        step: tolerance * 0.75,
      );
      if (distance <= tolerance && distance < bestDistance) {
        bestDistance = distance;
        best = id;
      }
    }
    return best;
  }
}
