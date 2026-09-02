import 'dart:ui' show Color, Rect;

import '../controller/node_editor_controller.dart';
import '../model/graph_node.dart';

/// The scene-space geometry the minimap draws, rebuilt only when the graph
/// moves.
///
/// Modelled on `ConnectionLayout`, and keyed on the same thing for the same
/// reason: `NodeEditorController.revision` moves for edits and geometry but
/// deliberately *not* for the camera, so panning and zooming the canvas
/// invalidate nothing here and only the projection is recomputed.
///
/// The rects are kept in **scene** space rather than map space. Map space
/// depends on the panel's size and on the zoom cap, both of which change
/// without the graph changing, and caching against the wrong thing is how a
/// cache turns into a stale-geometry bug.
///
/// **Colours are deliberately not cached.** A node's colour comes from the
/// selection and from its group, and the selection changes without `revision`
/// moving — the same trap `ConnectionLayout` documents for captions, where a
/// cached label kept reading `Out 0` after the port had been renamed. A colour
/// lookup is a map read; a stale colour is a bug found in a screenshot three
/// weeks later.
class MinimapScene {
  int _revision = -1;
  bool _synced = false;

  List<(GraphNode, Rect)> _nodes = const <(GraphNode, Rect)>[];
  List<(Color, Rect)> _groups = const <(Color, Rect)>[];
  Rect? _contentBounds;

  int _syncs = 0;

  /// Every node with its scene rect, in the graph's own order.
  List<(GraphNode, Rect)> get nodes => _nodes;

  /// Every group frame with its colour, in scene space.
  List<(Color, Rect)> get groups => _groups;

  /// Bounding box of the whole document, group frames included, or null when
  /// there is nothing in it.
  Rect? get contentBounds => _contentBounds;

  /// How many times the geometry has actually been rebuilt.
  ///
  /// The isolation the cache exists for is invisible when it breaks —
  /// everything still draws, just at the cost of walking the document on every
  /// scroll tick — so a test watches this number rather than the pixels.
  int get syncCount => _syncs;

  /// Cheap when nothing moved: compares one revision counter.
  ///
  /// Called from `paint` rather than from a build, because the panel widget is
  /// cached by identity and deliberately does not rebuild on a camera tick.
  void sync(NodeEditorController controller) {
    if (_synced && _revision == controller.revision) return;
    _revision = controller.revision;
    _synced = true;
    _syncs++;

    final graph = controller.graph;
    final layout = controller.layout;

    _nodes = <(GraphNode, Rect)>[
      for (final node in graph.nodes.values)
        (node, node.rect(layout.sizeOf(node))),
    ];
    _groups = <(Color, Rect)>[
      for (final group in graph.groups.values)
        if (layout.boundsOfGroup(group) case final Rect frame)
          (group.effectiveColor, frame),
    ];
    _contentBounds = graph.contentBounds(layout.sizeOf);
  }

  /// Forget everything, for a panel pointed at a different document.
  void invalidate() {
    _synced = false;
    _revision = -1;
    _nodes = const <(GraphNode, Rect)>[];
    _groups = const <(Color, Rect)>[];
    _contentBounds = null;
  }
}
