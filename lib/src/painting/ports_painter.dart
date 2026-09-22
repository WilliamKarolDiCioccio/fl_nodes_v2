import 'package:flutter/rendering.dart';

import '../geometry/node_geometry.dart';
import '../geometry/viewport_transform.dart';
import '../model/graph_node.dart';
import '../model/port_ref.dart';
import '../theme/node_editor_theme.dart';
import 'port_shape.dart';

/// Draws every port handle on screen, in one pass.
///
/// Handles used to be widgets — a `SizedBox`, a `MouseRegion`, a
/// `GestureDetector` and an animated dot each, so a four-port node carried
/// forty-odd render objects it never rebuilt and a semantics node per handle
/// describing nothing. Painting them costs a circle in a batched path.
///
/// The reason that matters is level of detail. Hiding handles when they are
/// too small to aim at is one comparison here; doing it by adding and removing
/// widgets would rebuild every node on screen at the moment the threshold is
/// crossed, which puts a stutter exactly where the user is already moving.
///
/// Hit testing deliberately does not live here — [NodeEditorLayout.portAt]
/// answers "which port is at this scene point" off the spatial index, which is
/// where that answer came from all along for deciding where a dragged wire
/// lands. Drawing and picking read the same geometry from [NodeGeometry], so
/// they cannot disagree.
class PortsPainter extends CustomPainter {
  const PortsPainter({
    required this.nodes,
    required this.sizeOf,
    required this.connectedPorts,
    required this.viewport,
    required this.theme,
    required this.revision,
    this.hovered,
    this.highlighted,
    this.lifted,
  });

  /// The nodes currently drawn, already culled by the editor.
  final List<GraphNode> nodes;

  final Size Function(GraphNode node) sizeOf;

  /// Which ports have a wire on them, by node id. A connected handle is
  /// filled; an empty one is hollow.
  final Map<String, Set<String>> connectedPorts;

  final ViewportTransform viewport;
  final NodeEditorTheme theme;

  /// [NodeEditorController.revision]: moves when geometry does.
  final int revision;

  /// The handle under the pointer, and the one a dragged wire would land on.
  final PortRef? hovered;
  final PortRef? highlighted;

  /// The nodes a [GraphEmphasis] has lifted above the focus scrim, or null
  /// when nothing is focused.
  ///
  /// Handles are drawn *above* the whole node layer, scrim included, so
  /// without this every dimmed card would keep a row of bright dots floating
  /// over the wash. Nodes outside it are skipped — and [NodeEditorLayout.portAt]
  /// skips them too, because one condition has to gate drawing and hitting
  /// alike: an invisible dot that still starts a wire is worse than one
  /// plainly not there yet, which is the same rule [NodeEditorTheme.portMinScale]
  /// already follows.
  ///
  /// A cached snapshot, so [shouldRepaint] can compare it by identity the way
  /// it compares [connectedPorts].
  final Set<String>? lifted;

  @override
  void paint(Canvas canvas, Size size) {
    if (viewport.scale < theme.portMinScale) return;

    final radius = theme.portRadius;
    final border = radius * 0.34;
    // Batched by colour, since a port may carry its own. Most graphs use one,
    // so this is a couple of paths for any number of handles.
    final fills = <Color, Path>{};
    final strokes = <Color, Path>{};
    final active = <(Offset, PortShape)>[];

    final focus = lifted;
    for (final node in nodes) {
      if (focus != null && focus.isNotEmpty && !focus.contains(node.id)) {
        continue;
      }
      final nodeSize = sizeOf(node);
      final connected = connectedPorts[node.id];
      for (final port in node.ports) {
        final centre = NodeGeometry.portPosition(node, port, nodeSize);
        final base = port.color ?? theme.portColor;
        final ref = PortRef(node.id, port.id);
        if (ref == hovered || ref == highlighted) {
          active.add((centre, theme.shapeOf(port.kind)));
          continue;
        }
        final filled = connected?.contains(port.id) ?? false;
        // Every shape is built on the same circumradius, so a row of mixed
        // shapes lines up and the hit target stays one rule for all of them
        // (`NodeEditorLayout.portAt` is still a radius).
        final shape = theme.shapeOf(port.kind);
        fills[filled ? base : theme.background] = Path.combine(
          PathOperation.union,
          fills[filled ? base : theme.background] ?? Path(),
          shape.path(centre, radius),
        );
        // Stroked on the centre line, inset by half the width, so the drawn
        // outer edge lands on `radius` the way a border inside a box does.
        strokes[base] = Path.combine(
          PathOperation.union,
          strokes[base] ?? Path(),
          shape.path(centre, radius - border / 2),
        );
      }
    }

    canvas
      ..save()
      ..transform(viewport.toMatrix4().storage);

    fills.forEach((color, path) {
      canvas.drawPath(path, Paint()..color = color);
    });
    strokes.forEach((color, path) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = border,
      );
    });

    // Drawn last and larger, so the handle being aimed at reads on top of its
    // neighbours rather than under whichever node happens to paint later.
    final grown = radius * 1.3;
    for (final (centre, shape) in active) {
      canvas.drawPath(
        shape.path(centre, grown),
        Paint()..color = theme.portHoverColor,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(PortsPainter oldDelegate) =>
      oldDelegate.revision != revision ||
      oldDelegate.viewport != viewport ||
      oldDelegate.theme != theme ||
      oldDelegate.hovered != hovered ||
      oldDelegate.highlighted != highlighted ||
      !identical(oldDelegate.connectedPorts, connectedPorts) ||
      !identical(oldDelegate.lifted, lifted);
}
