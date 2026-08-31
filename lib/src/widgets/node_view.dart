import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../model/graph_node.dart';
import '../theme/node_editor_theme.dart';
import 'node_box.dart';

/// Interaction state handed to the host's node builder.
@immutable
class NodeRenderState {
  const NodeRenderState({
    required this.isSelected,
    required this.isHovered,
    required this.isDragging,
    required this.isConnectionTarget,
  });

  final bool isSelected;
  final bool isHovered;
  final bool isDragging;

  /// A connection being dragged is currently hovering this node.
  final bool isConnectionTarget;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NodeRenderState &&
          other.isSelected == isSelected &&
          other.isHovered == isHovered &&
          other.isDragging == isDragging &&
          other.isConnectionTarget == isConnectionTarget;

  @override
  int get hashCode =>
      Object.hash(isSelected, isHovered, isDragging, isConnectionTarget);
}

/// Builds the body of a node. The editor supplies the frame, ports, hit
/// testing and dragging; this decides what the box looks like.
typedef NodeWidgetBuilder =
    Widget Function(
      BuildContext context,
      GraphNode node,
      NodeRenderState state,
    );

/// One node on the canvas: the host-built body and its selection outline.
///
/// Port handles are deliberately not here. They are painted by
/// [PortsPainter] above the node layer and picked geometrically, which keeps a
/// four-port node from carrying forty render objects and lets them be dropped
/// at low zoom without rebuilding anything.
class NodeView extends StatefulWidget {
  const NodeView({
    super.key,
    required this.node,
    required this.theme,
    required this.builder,
    required this.isSelected,
    required this.isDragging,
    required this.isConnectionTarget,
    required this.onContentSized,
    required this.onTap,
    required this.onDoubleTap,
    required this.onSecondaryTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final GraphNode node;
  final NodeEditorTheme theme;
  final NodeWidgetBuilder builder;

  final bool isSelected;
  final bool isDragging;
  final bool isConnectionTarget;

  final ValueChanged<Size> onContentSized;

  final void Function(bool additive) onTap;

  /// Left null when the host has no double-tap handler: registering one
  /// unconditionally would make every plain tap wait out the double-tap
  /// timeout before selection lands.
  final VoidCallback? onDoubleTap;

  final void Function(Offset globalPosition)? onSecondaryTap;

  final void Function(Offset globalPosition, bool additive) onDragStart;
  final void Function(Offset globalPosition) onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  State<NodeView> createState() => _NodeViewState();
}

class _NodeViewState extends State<NodeView> {
  bool _hovered = false;
  DateTime? _lastTapAt;

  /// Selects on the first tap, and synthesises the double tap itself.
  ///
  /// Handing `onDoubleTap` to the [GestureDetector] instead would put a
  /// [DoubleTapGestureRecognizer] in the arena, which holds every single tap
  /// for the double-tap timeout before releasing it — so selecting a node
  /// would visibly lag, while dragging one (which the pan recogniser claims
  /// immediately) would not.
  void _handleTap() {
    widget.onTap(_additivePressed);

    final onDoubleTap = widget.onDoubleTap;
    if (onDoubleTap == null) return;

    final now = DateTime.now();
    final previous = _lastTapAt;
    if (previous != null && now.difference(previous) <= kDoubleTapTimeout) {
      _lastTapAt = null;
      onDoubleTap();
    } else {
      _lastTapAt = now;
    }
  }

  bool get _additivePressed {
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed;
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final state = NodeRenderState(
      isSelected: widget.isSelected,
      isHovered: _hovered,
      isDragging: widget.isDragging,
      isConnectionTarget: widget.isConnectionTarget,
    );

    return NodeBox(
      onContentSized: widget.onContentSized,
      child: _buildContent(context, node, state),
    );
  }

  Widget _buildContent(
    BuildContext context,
    GraphNode node,
    NodeRenderState state,
  ) {
    return MouseRegion(
      cursor: node.draggable
          ? SystemMouseCursors.grab
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Report the drag from where the pointer went down, so the grabbed
        // point stays pinned under the cursor instead of trailing it by the
        // touch slop.
        dragStartBehavior: DragStartBehavior.down,
        onTap: _handleTap,
        onSecondaryTapUp: widget.onSecondaryTap == null
            ? null
            : (details) => widget.onSecondaryTap!(details.globalPosition),
        onPanStart: node.draggable
            ? (details) =>
                  widget.onDragStart(details.globalPosition, _additivePressed)
            : null,
        onPanUpdate: node.draggable
            ? (details) => widget.onDragUpdate(details.globalPosition)
            : null,
        onPanEnd: node.draggable ? (_) => widget.onDragEnd() : null,
        onPanCancel: node.draggable ? widget.onDragEnd : null,
        child: SizedBox(
          width: node.width,
          height: node.height,
          child: CustomPaint(
            foregroundPainter: state.isSelected
                ? _SelectionPainter(widget.theme)
                : null,
            child: widget.builder(context, node, state),
          ),
        ),
      ),
    );
  }
}

/// Draws the selection outline just outside the node's bounds.
///
/// A foreground painter is used rather than a border so the outline does not
/// change the node's measured size.
class _SelectionPainter extends CustomPainter {
  const _SelectionPainter(this.theme);

  final NodeEditorTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).inflate(theme.selectionInset);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, theme.selectionRadius),
      Paint()
        ..color = theme.selectionColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = theme.selectionWidth,
    );
  }

  @override
  bool shouldRepaint(_SelectionPainter oldDelegate) =>
      oldDelegate.theme != theme;
}
