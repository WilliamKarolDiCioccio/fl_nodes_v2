import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FragmentShader;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/node_editor_controller.dart';
import '../geometry/viewport_transform.dart';
import '../model/graph_node.dart';
import '../model/node_comment.dart';
import '../model/node_connection.dart';
import '../model/node_group.dart';
import '../model/port_ref.dart';
import '../painting/connection_label.dart';
import '../painting/connection_layout.dart';
import '../painting/connections_painter.dart';
import '../painting/emphasis_painter.dart';
import '../painting/grid_painter.dart';
import '../painting/grid_shader.dart';
import '../painting/overlay_painter.dart';
import '../painting/ports_painter.dart';
import '../menus/node_editor_menu_host.dart';
import '../menus/node_editor_menus.dart';
import '../minimap/minimap_config.dart';
import '../minimap/minimap_controller.dart';
import '../minimap/minimap_panel.dart';
import 'node_description_dialog.dart';
import '../theme/node_editor_theme.dart';
import 'comment_view.dart';
import 'connection_label_editor.dart';
import 'group_name_editor.dart';
import 'group_view.dart';
import 'node_editor_scope.dart';
import 'node_view.dart';

/// What a primary-button drag on empty canvas does.
///
/// Either way the view can always be panned with the middle button, with
/// space held, with a trackpad, or with a touch drag — navigation gestures are
/// never taken over by selection.
enum CanvasDragBehavior {
  /// Drag sweeps a selection rectangle, the way a desktop file manager does.
  /// Hold shift or control to add to the existing selection.
  marquee,

  /// Drag moves the view. Hold shift to sweep a selection rectangle instead.
  pan,
}

/// An interactive, pannable and zoomable node graph canvas.
///
/// The widget owns interaction only: geometry comes from the model, state from
/// the [controller], and node bodies from [nodeBuilder]. Swapping the builder
/// is enough to retarget the editor at a different domain.
///
/// ```dart
/// NodeEditor(
///   controller: controller,
///   nodeBuilder: (context, node, state) => MyCard(node: node, state: state),
/// )
/// ```
class NodeEditor extends StatefulWidget {
  const NodeEditor({
    super.key,
    required this.controller,
    required this.nodeBuilder,
    this.theme,
    this.canvasDragBehavior = CanvasDragBehavior.marquee,
    this.enableKeyboardShortcuts = true,
    this.autofocus = true,
    this.zoomSensitivity = 0.0022,
    this.onNodeTap,
    this.onNodeDoubleTap,
    this.onNodeSecondaryTap,
    this.onConnectionTap,
    this.onConnectionCreated,
    this.onConnectionDropped,
    this.onEditConnectionLabel,
    this.onCanvasTap,
    this.onCanvasSecondaryTap,
    this.onPortSecondaryTap,
    this.onConnectionSecondaryTap,
    this.contextMenus = const NodeEditorMenus(),
    this.minimap,
    this.minimapController,
  });

  final NodeEditorController controller;

  /// Builds the body of each node.
  final NodeWidgetBuilder nodeBuilder;

  /// Defaults to [NodeEditorTheme.dark] or [NodeEditorTheme.light] based on
  /// the ambient [Theme] brightness.
  final NodeEditorTheme? theme;

  final CanvasDragBehavior canvasDragBehavior;

  /// Delete, undo/redo, select-all, escape and arrow-key nudging.
  final bool enableKeyboardShortcuts;

  final bool autofocus;

  /// Zoom applied per logical pixel of scroll wheel travel.
  final double zoomSensitivity;

  final void Function(GraphNode node)? onNodeTap;
  final void Function(GraphNode node)? onNodeDoubleTap;
  final void Function(GraphNode node, Offset globalPosition)?
  onNodeSecondaryTap;
  final void Function(NodeConnection connection)? onConnectionTap;
  final void Function(NodeConnection connection)? onConnectionCreated;

  /// A connection drag released over empty canvas — the usual hook for a
  /// "create a node here" affordance.
  final void Function(PortRef source, Offset scenePosition)?
  onConnectionDropped;

  /// Asked for a new caption when the app user taps a captionable link.
  ///
  /// Only links whose [LinkPrototype] opts in are tappable this way. Return the
  /// new caption, an empty string to clear it, or null to leave it alone.
  /// Defaults to [showConnectionLabelEditor].
  final Future<String?> Function(
    BuildContext context,
    NodeConnection connection,
  )?
  onEditConnectionLabel;

  final void Function(Offset scenePosition)? onCanvasTap;
  final void Function(Offset scenePosition, Offset globalPosition)?
  onCanvasSecondaryTap;

  final void Function(PortRef port, Offset globalPosition)? onPortSecondaryTap;
  final void Function(NodeConnection connection, Offset globalPosition)?
  onConnectionSecondaryTap;

  /// The right-click menus, or null for none.
  ///
  /// Supplying one of the `onSecondaryTap` callbacks above takes that target
  /// over: the callback is called and no built-in menu opens for it, so a host
  /// that already had its own menu keeps it and does not get two.
  final NodeEditorMenus? contextMenus;

  /// The minimap panel, or null for none.
  ///
  /// Off by default, unlike [contextMenus]: a right-click already means a
  /// menu, where a panel sitting over the canvas is a thing a host has to ask
  /// for. `minimap: const MinimapConfig()` is the whole opt-in.
  final MinimapConfig? minimap;

  /// Where the panel's own state lives — its placement, its size, whether it
  /// is folded, and what it draws.
  ///
  /// The editor makes one when this is null. Supply one to persist the
  /// placement across sessions, or to drive the panel from elsewhere; a
  /// supplied controller is the host's to dispose.
  final MinimapController? minimapController;

  @override
  State<NodeEditor> createState() => NodeEditorState();
}

/// What the current press on the canvas turned out to mean.
///
/// [blocked] is a press that must not become a drag at all — a secondary
/// press, which opens a menu instead. It needs its own state rather than
/// simply staying [none], because [none] falls through to panning.
enum _CanvasGesture { none, pan, marquee, port, blocked }

class NodeEditorState extends State<NodeEditor> {
  final GlobalKey _canvasKey = GlobalKey();
  final FocusNode _focusNode = FocusNode(debugLabel: 'NodeEditor');
  final MenuController _menuController = MenuController();
  final GlobalKey<NodeEditorMenuHostState> _menuHostKey =
      GlobalKey<NodeEditorMenuHostState>();

  /// Draws the comment notes, in place of the host's `nodeBuilder`.
  ///
  /// Torn off once and held, because [_NodeSlot] compares builders by
  /// identity and a tear-off is not guaranteed identical to the last one. Read
  /// per build, it would look like a new builder every frame and hand back the
  /// rebuild isolation the slot exists for.
  late final NodeWidgetBuilder _commentBuilder = _buildComment;

  Widget _buildComment(
    BuildContext context,
    GraphNode node,
    NodeRenderState _,
  ) => CommentView(node: node, controller: _controller);

  /// Held for the same reason [_commentBuilder] is: [_MinimapSlot] compares
  /// its inputs by identity, and a closure built per frame is the one input
  /// that can never compare equal to the last one.
  late final VoidCallback _requestCanvasFocus = _focusNode.requestFocus;

  /// Made only when the host supplies none, and disposed only if made here.
  MinimapController? _ownedMinimap;

  MinimapController get _minimap =>
      widget.minimapController ?? (_ownedMinimap ??= MinimapController());

  final _MinimapSlot _minimapSlot = _MinimapSlot();

  /// Where the minimap panel currently is, in canvas-local coordinates.
  ///
  /// Reported by the panel rather than recomputed here, because resolving it
  /// means knowing the config's alignment and the clamp — and two copies of
  /// that arithmetic is how a guard stops guarding.
  Rect? _minimapRect;

  void _setMinimapRect(Rect rect) => _minimapRect = rect;

  /// True where a pointer at [localPosition] is over the minimap.
  ///
  /// [MouseRegion.opaque] and [HitTestBehavior.opaque] stop *siblings lower in
  /// the stack*; they do not stop **ancestors**, and every annotation along
  /// the hit-test path still gets its callback. The [Listener] and
  /// [MouseRegion] wrapping this canvas are both ancestors of the panel, so
  /// the panel cannot shadow them and the editor has to ask.
  bool _overMinimap(Offset localPosition) =>
      widget.minimap != null &&
      (_minimapRect?.contains(localPosition) ?? false);

  NodeEditorTheme? _resolvedTheme;

  /// Null until the grid shader compiles, and permanently null where fragment
  /// shaders are unavailable; the painter falls back to CPU lines either way.
  FragmentShader? _gridShader;

  // Canvas gesture state.
  _CanvasGesture _canvasGesture = _CanvasGesture.none;
  Offset _lastFocalPoint = Offset.zero;
  double _gestureStartScale = 1;
  int _pointerButtons = 0;
  Offset? _marqueeAnchor;
  Rect? _marquee;
  bool _marqueeAdditive = false;

  /// Selection the marquee started from, so an additive sweep adds to it
  /// instead of replacing it on the first frame.
  Set<String> _marqueeBase = const <String>{};

  /// Screen-space travel before a press is treated as a sweep rather than a
  /// click. Without it, every click on the canvas would run a zero-area
  /// selection and fight with the tap handler.
  static const double _marqueeSlop = 3;

  PointerDeviceKind? _pointerKind;

  /// Where the pointer actually went down.
  ///
  /// A scale gesture reports its start where it *won the arena*, which is a
  /// touch slop away from the press once a tap recogniser has competed for it.
  /// Anchoring the rubber band there would leave it visibly detached from the
  /// point the user clicked.
  Offset? _pointerDownPosition;

  // Trackpad pan/zoom state.
  double _panZoomStartScale = 1;
  Offset _panZoomLastPan = Offset.zero;

  // Node drag state.
  Set<String> _draggingNodeIds = const <String>{};
  Offset? _nodeDragOrigin;
  Map<String, Offset> _nodeDragStartPositions = const <String, Offset>{};

  // Connection drag state.
  PortRef? _pendingSource;
  PortRef? _pendingTarget;
  PendingConnection? _pending;

  String? _hoveredConnectionId;
  PortRef? _hoveredPort;

  Size _viewportSize = Size.zero;

  /// One [_NodeSlot] per node currently on screen, holding its widget and its
  /// callbacks so both survive a rebuild of the canvas around them.
  final Map<String, _NodeSlot> _slots = <String, _NodeSlot>{};
  int _slotGeneration = 0;

  Map<String, Set<String>> _connectedPortsCache = const <String, Set<String>>{};
  Map<String, NodeConnection>? _connectedPortsSource;

  /// Scene-space connection paths, rebuilt only when the graph moves.
  final ConnectionLayout _connections = ConnectionLayout();

  NodeEditorController get _controller => widget.controller;
  ViewportTransform get _viewport => _controller.camera.viewport;
  NodeEditorTheme get _theme => _resolvedTheme!;

  /// Screen-space picking slop converted to scene units, so the target stays
  /// the same physical size at any zoom.
  double get _connectionTolerance =>
      _theme.connectionHitTolerance / _viewport.scale;

  @override
  void initState() {
    super.initState();
    _loadGridShader();
  }

  Future<void> _loadGridShader() async {
    await GridShader.load();
    if (!mounted) return;
    final shader = GridShader.createShader();
    if (shader == null) return;
    setState(() => _gridShader = shader);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveTheme();
  }

  @override
  void didUpdateWidget(NodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.theme != widget.theme) _resolveTheme();
    if (!identical(oldWidget.controller, widget.controller)) {
      // Everything cached below is keyed by node id, and the new document's
      // ids mean nothing to the old one. Revisions can coincide too, so the
      // path cache has to be told rather than left to notice.
      _slots.clear();
      _connectedPortsSource = null;
      _connectedPortsCache = const <String, Set<String>>{};
      _connections.invalidate();
    }
    // A host that has started supplying its own leaves ours with nothing to
    // do; one that has stopped gets a fresh one on the next read.
    if (widget.minimapController != null && _ownedMinimap != null) {
      _ownedMinimap!.dispose();
      _ownedMinimap = null;
    }
  }

  /// Cached so painters can compare themes by identity and skip repaints.
  void _resolveTheme() {
    final provided = widget.theme;
    final resolved =
        provided ??
        (Theme.of(context).brightness == Brightness.dark
            ? NodeEditorTheme.dark()
            : NodeEditorTheme.light());
    if (resolved == _resolvedTheme) return;
    _resolvedTheme = resolved;
    _connections
      ..curvature = resolved.connectionCurvature
      ..arrowSpacing = resolved.connectionArrowSpacing
      ..maxArrows = resolved.connectionArrowMaxCount;
    _controller.camera.setScaleLimits(resolved.minScale, resolved.maxScale);
  }

  @override
  void dispose() {
    _gridShader?.dispose();
    _focusNode.dispose();
    // Only ever the one made here: a host's controller outlives its editor.
    _ownedMinimap?.dispose();
    super.dispose();
  }

  // ------------------------------------------------------- coordinate space

  RenderBox? get _canvasBox =>
      _canvasKey.currentContext?.findRenderObject() as RenderBox?;

  Offset _toLocal(Offset globalPosition) =>
      _canvasBox?.globalToLocal(globalPosition) ?? globalPosition;

  Offset _toScene(Offset globalPosition) =>
      _viewport.toScene(_toLocal(globalPosition));

  // ------------------------------------------------------------ hit testing

  /// The port under [scenePoint], or null when handles are too small to aim
  /// at.
  ///
  /// Gated on the same threshold [PortsPainter] draws at, so a handle is
  /// grabbable exactly when it is visible. At 15% zoom the whole target is
  /// under two pixels across, and an invisible dot that still starts a wire is
  /// worse than one that is plainly not there yet.
  PortRef? _portAt(Offset scenePoint) {
    if (_viewport.scale < _theme.portMinScale) return null;
    return _controller.layout.portAt(scenePoint, radius: _theme.portHitRadius);
  }

  GraphNode? _nodeAt(Offset scenePoint) =>
      _controller.layout.nodeAt(scenePoint);

  /// Where a connection dragged from [source] would land, if anywhere.
  ///
  /// Falls back to the first compatible port of the node under the pointer, so
  /// dropping anywhere on a node wires it up.
  PortRef? _dropTargetAt(Offset scenePoint, PortRef source) {
    final port = _portAt(scenePoint);
    if (port != null) {
      return _controller.canConnect(source, port) ? port : null;
    }

    final node = _nodeAt(scenePoint);
    if (node == null) return null;
    return _firstCompatiblePort(node, source);
  }

  /// The first port on [node] a wire out of [source] is allowed to land on.
  ///
  /// Declaration order decides, so which port a node "catches with" is a
  /// property of its prototype rather than of where the pointer happened to
  /// be. Shared by the drop-onto-a-node path and drop-to-create.
  PortRef? _firstCompatiblePort(GraphNode node, PortRef source) {
    for (final candidate in node.ports) {
      final ref = PortRef(node.id, candidate.id);
      if (_controller.canConnect(source, ref)) return ref;
    }
    return null;
  }

  // ------------------------------------------------------- canvas gestures

  bool get _additivePressed {
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed;
  }

  /// The secondary button opens menus; it never drives a drag.
  ///
  /// Neither recogniser filters by button on its own, so without this a
  /// right-press over a handle starts a real wire, a right-drag on the canvas
  /// sweeps a selection, and a right-drag on a node moves it and pushes an
  /// undo entry — all while the menu the user asked for is trying to open.
  bool get _secondaryPressed => _pointerButtons & kSecondaryButton != 0;

  void _handleScaleStart(ScaleStartDetails details) {
    if (_secondaryPressed) {
      _canvasGesture = _CanvasGesture.blocked;
      return;
    }
    _focusNode.requestFocus();
    _lastFocalPoint = details.localFocalPoint;
    _gestureStartScale = _viewport.scale;

    // A handle sits on its node's border, so half of it hangs outside the
    // node's gesture area and lands here instead.
    final port = _portAt(
      _viewport.toScene(_pointerDownPosition ?? details.localFocalPoint),
    );
    if (port != null) {
      _canvasGesture = _CanvasGesture.port;
      _handlePortDragStart(port);
      return;
    }

    final keyboard = HardwareKeyboard.instance;
    final marqueeIsDefault =
        widget.canvasDragBehavior == CanvasDragBehavior.marquee;

    // Navigation gestures always win: a touch drag, the middle button, held
    // space, or a second finger means the user wants to move the view.
    final navigating =
        _pointerKind == PointerDeviceKind.touch ||
        _pointerButtons & kMiddleMouseButton != 0 ||
        keyboard.isLogicalKeyPressed(LogicalKeyboardKey.space) ||
        details.pointerCount > 1;

    final marquee =
        !navigating && (marqueeIsDefault || keyboard.isShiftPressed);

    if (!marquee) {
      _canvasGesture = _CanvasGesture.pan;
      return;
    }

    // Shift is the additive modifier when it is not the thing that opted into
    // the marquee in the first place.
    _marqueeAdditive =
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        (marqueeIsDefault && keyboard.isShiftPressed);
    _marqueeBase = _marqueeAdditive
        ? Set<String>.of(_controller.selection.nodeIds)
        : const <String>{};

    // The rectangle stays hidden until the press turns into a real drag.
    _canvasGesture = _CanvasGesture.marquee;
    _marqueeAnchor = _viewport.toScene(
      _pointerDownPosition ?? details.localFocalPoint,
    );
    _marquee = null;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (_canvasGesture == _CanvasGesture.blocked) return;
    if (_canvasGesture == _CanvasGesture.port) {
      _handlePortDragUpdate(_viewport.toScene(details.localFocalPoint));
      return;
    }
    if (_canvasGesture == _CanvasGesture.marquee) {
      // A second finger means the user wants to navigate, not select.
      if (details.pointerCount > 1) {
        _abandonMarquee();
        _lastFocalPoint = details.localFocalPoint;
        return;
      }

      final anchor = _marqueeAnchor;
      if (anchor == null) return;

      final travel =
          (details.localFocalPoint - _viewport.toScreen(anchor)).distance;
      if (_marquee == null && travel < _marqueeSlop) return;

      final rect = Rect.fromPoints(
        anchor,
        _viewport.toScene(details.localFocalPoint),
      );
      setState(() => _marquee = rect);
      // Selection follows the rectangle live, the way a desktop file manager
      // highlights as you sweep, rather than landing only on release.
      _controller.selection.selectNodes(<String>{
        ..._marqueeBase,
        ..._controller.layout.nodeIdsIn(rect),
      });
      return;
    }

    if (details.scale != 1.0) {
      _controller.camera.setScale(
        _gestureStartScale * details.scale,
        focalScreenPoint: details.localFocalPoint,
      );
    }
    _controller.camera.panBy(details.localFocalPoint - _lastFocalPoint);
    _lastFocalPoint = details.localFocalPoint;
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    if (_canvasGesture == _CanvasGesture.blocked) {
      _canvasGesture = _CanvasGesture.none;
      return;
    }
    if (_canvasGesture == _CanvasGesture.port) {
      _canvasGesture = _CanvasGesture.none;
      _handlePortDragEnd();
      return;
    }
    // Selection was already applied live; ending only clears the overlay.
    setState(() {
      _canvasGesture = _CanvasGesture.none;
      _marquee = null;
      _marqueeAnchor = null;
      _marqueeBase = const <String>{};
    });
  }

  /// Drops the rectangle and puts the selection back as it was.
  void _abandonMarquee() {
    if (_canvasGesture != _CanvasGesture.marquee) return;
    final base = _marqueeBase;
    setState(() {
      _canvasGesture = _CanvasGesture.pan;
      _marquee = null;
      _marqueeAnchor = null;
      _marqueeBase = const <String>{};
    });
    _controller.selection.selectNodes(base);
  }

  /// The style captions are painted in, and therefore measured in.
  TextStyle _labelStyle() => DefaultTextStyle.of(
    context,
  ).style.copyWith(fontSize: 11, color: _theme.connectionColor);

  /// The captionable link whose caption was drawn under [localPosition].
  ///
  /// Captions are canvas text, so this asks [ConnectionLabel] for the very box
  /// the painter drew rather than guessing at one.
  String? _editableCaptionAt(Offset localPosition) {
    final registry = _controller.prototypes;
    final visible = _viewport.visibleSceneRect(_viewportSize);
    final style = _labelStyle();

    for (final entry in _connections.entriesIn(visible)) {
      final connection = _controller.graph.connections[entry.key];
      if (connection == null) continue;
      if (!registry.allowsLabelEditing(connection)) continue;

      final caption = ConnectionLabel.captionFor(
        text: entry.value.caption,
        anchor: entry.value.labelAnchor,
        editable: true,
        viewport: _viewport,
        style: style,
      );
      if (caption != null && caption.rect.contains(localPosition)) {
        return entry.key;
      }
    }
    return null;
  }

  Future<void> _editConnectionLabel(String id) async {
    final connection = _controller.graph.connections[id];
    if (connection == null) return;
    _controller.selection.selectConnection(id);

    final handler = widget.onEditConnectionLabel;
    // Built before awaiting anything, so the context is never used across a gap.
    final pending = handler != null
        ? handler(context, connection)
        : showConnectionLabelEditor(
            context,
            initialValue: connection.label,
            title: _controller.prototypes.editorTitleFor(connection),
          );

    final result = await pending;
    // The graph can have moved on while the modal was open.
    if (!mounted || result == null) return;
    _controller.setConnectionLabel(id, result);
  }

  void _handleCanvasTapUp(TapUpDetails details) {
    // A tap is not a drag, so `_handleScaleStart` never runs for one and
    // nothing else on this path would take focus. Without this, clicking a
    // connection selects it and then Delete does nothing — or worse, reaches
    // whatever the host had focused before and deletes something else.
    _focusNode.requestFocus();

    // Before the curve test: a caption sits on its curve's midpoint, so the
    // curve would otherwise swallow every tap meant for the text.
    final caption = _editableCaptionAt(details.localPosition);
    if (caption != null) {
      unawaited(_editConnectionLabel(caption));
      return;
    }

    final hit = _connections.hitTest(
      _viewport.toScene(details.localPosition),
      tolerance: _connectionTolerance,
    );
    if (hit != null) {
      _controller.selection.selectConnection(hit, additive: _additivePressed);
      widget.onConnectionTap?.call(_controller.graph.connections[hit]!);
      return;
    }
    if (!_additivePressed) _controller.selection.clear();
    widget.onCanvasTap?.call(_viewport.toScene(details.localPosition));
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // Scrolling over the panel must not zoom the canvas underneath it.
    if (_overMinimap(event.localPosition)) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      final scroll = resolved as PointerScrollEvent;
      if (HardwareKeyboard.instance.isShiftPressed) {
        _controller.camera.panBy(Offset(-scroll.scrollDelta.dy, 0));
        return;
      }
      final factor = math.exp(-scroll.scrollDelta.dy * widget.zoomSensitivity);
      _controller.camera.zoomBy(factor, focalScreenPoint: scroll.localPosition);
    });
  }

  void _handlePanZoomStart(PointerPanZoomStartEvent event) {
    if (_overMinimap(event.localPosition)) return;
    _panZoomStartScale = _viewport.scale;
    _panZoomLastPan = Offset.zero;
  }

  void _handlePanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (_overMinimap(event.localPosition)) return;
    _controller.camera.panBy(event.pan - _panZoomLastPan);
    _panZoomLastPan = event.pan;
    if (event.scale != 1.0) {
      _controller.camera.setScale(
        _panZoomStartScale * event.scale,
        focalScreenPoint: event.localPosition,
      );
    }
  }

  void _handleHover(PointerHoverEvent event) {
    if (_pendingSource != null || _canvasGesture != _CanvasGesture.none) return;
    // Otherwise moving across the panel highlights ports and wires beneath it,
    // and changes the cursor over a panel that is not showing them.
    if (_overMinimap(event.localPosition)) return;
    final scene = _viewport.toScene(event.localPosition);

    // A painted handle has no MouseRegion of its own, so its hover state is
    // picked here alongside the connections'.
    final port = _portAt(scene);
    final hit = port != null
        ? null
        : _connections.hitTest(scene, tolerance: _connectionTolerance);
    if (hit == _hoveredConnectionId && port == _hoveredPort) return;
    setState(() {
      _hoveredConnectionId = hit;
      _hoveredPort = port;
    });
  }

  // --------------------------------------------------------- node gestures

  void _handleNodeTap(GraphNode node, bool additive) {
    // Clicking the node's own chrome takes focus back from anything inside it,
    // so canvas shortcuts apply again.
    _focusNode.requestFocus();
    if (additive) {
      _controller.selection.toggleNode(node.id);
    } else {
      _controller.selection.selectNode(node.id);
    }
    widget.onNodeTap?.call(node);
  }

  void _handleNodeDragStart(
    GraphNode node,
    Offset globalPosition,
    bool additive,
  ) {
    if (_secondaryPressed) return;
    _focusNode.requestFocus();

    // The handles painted on this node's border are inside its gesture area,
    // so this recogniser wins the press for them too. Ask before assuming the
    // user meant to move the node.
    final port = _portAt(_toScene(globalPosition));
    if (port != null) {
      _handlePortDragStart(port);
      return;
    }

    if (!_controller.selection.containsNode(node.id)) {
      if (additive) {
        _controller.selection.toggleNode(node.id);
      } else {
        _controller.selection.selectNode(node.id);
      }
    }

    _beginNodeDrag(globalPosition);
  }

  /// Starts moving everything selected, frames included, as one undo step.
  ///
  /// Shared by the node path and the group handle: a group drag is a node drag
  /// over a different set, and there is nothing else to it.
  void _beginNodeDrag(Offset globalPosition) {
    final ids = <String>{
      for (final id in _controller.selection.nodeIdsWithGroups)
        if (_controller.graph.nodes[id]?.draggable ?? false) id,
    };
    if (ids.isEmpty) return;

    _controller.history.beginTransaction();
    setState(() {
      _draggingNodeIds = ids;
      _nodeDragOrigin = globalPosition;
      _nodeDragStartPositions = <String, Offset>{
        for (final id in ids) id: _controller.graph.nodes[id]!.position,
      };
    });
  }

  // -------------------------------------------------------- group gestures

  void _handleGroupTap(NodeGroup group, bool additive) {
    _focusNode.requestFocus();
    if (additive) {
      _controller.selection.toggleGroup(group.id);
    } else {
      _controller.selection.selectGroup(group.id);
    }
  }

  void _handleGroupDragStart(
    NodeGroup group,
    Offset globalPosition,
    bool additive,
  ) {
    if (_secondaryPressed) return;
    _focusNode.requestFocus();
    if (!_controller.selection.containsGroup(group.id)) {
      if (additive) {
        _controller.selection.toggleGroup(group.id);
      } else {
        _controller.selection.selectGroup(group.id);
      }
    }
    _beginNodeDrag(globalPosition);
  }

  void _handleGroupSecondaryTap(NodeGroup group, Offset globalPosition) {
    if (!_controller.selection.containsGroup(group.id)) {
      _controller.selection.selectGroup(group.id);
    }
    _openMenu(
      NodeMenuGroupTarget(group, _toScene(globalPosition)),
      globalPosition,
    );
  }

  Future<void> _renameGroup(NodeGroup group) async {
    final name = await showGroupNameEditor(context, initialValue: group.name);
    if (name == null || !mounted) return;
    _controller.renameGroup(group.id, name);
  }

  void _handleNodeDragUpdate(Offset globalPosition) {
    if (_pendingSource != null) {
      _handlePortDragUpdate(_toScene(globalPosition));
      return;
    }
    final origin = _nodeDragOrigin;
    if (origin == null) return;
    // Pointer deltas arrive in screen pixels; the graph lives in scene units.
    final delta = (globalPosition - origin) / _viewport.scale;
    _controller.moveNodes(<String, Offset>{
      for (final entry in _nodeDragStartPositions.entries)
        entry.key: entry.value + delta,
    }, snap: _theme.snapToGrid);
  }

  void _handleNodeDragEnd() {
    if (_pendingSource != null) {
      _handlePortDragEnd();
      return;
    }
    if (_nodeDragOrigin == null) return;
    _controller.history.commitTransaction();
    setState(() {
      _draggingNodeIds = const <String>{};
      _nodeDragOrigin = null;
      _nodeDragStartPositions = const <String, Offset>{};
    });
  }

  // --------------------------------------------------- connection gestures

  /// Starts dragging a wire out of [ref].
  ///
  /// Called from whichever gesture won the press — the node's own recogniser
  /// when the handle sits over its body, the canvas one when it sits just
  /// outside. Handles are no longer widgets, so neither of those knows it was
  /// aiming at a port until it asks.
  void _handlePortDragStart(PortRef ref) {
    final origin = _controller.layout.portPosition(ref);
    final port = _controller.graph.nodes[ref.nodeId]?.portById(ref.portId);
    if (origin == null || port == null) return;
    setState(() {
      _pendingSource = ref;
      _pendingTarget = null;
      _pending = PendingConnection(
        origin: origin,
        pointer: origin,
        originSide: port.side,
      );
    });
  }

  void _handlePortDragUpdate(Offset scene) {
    final source = _pendingSource;
    final pending = _pending;
    if (source == null || pending == null) return;

    final target = _dropTargetAt(scene, source);
    // Only flag invalidity when the pointer is actually over something.
    final overPort = _portAt(scene) != null || _nodeAt(scene) != null;

    setState(() {
      _pendingTarget = target;
      _pending = PendingConnection(
        origin: pending.origin,
        pointer: scene,
        originSide: pending.originSide,
        isValidTarget: target != null || !overPort,
        snappedTo: target == null
            ? null
            : _controller.layout.portPosition(target),
      );
    });
  }

  void _handlePortDragEnd() {
    final source = _pendingSource;
    final target = _pendingTarget;
    final pending = _pending;

    if (source != null && target != null) {
      final id = _controller.connect(source, target);
      if (id != null) {
        widget.onConnectionCreated?.call(_controller.graph.connections[id]!);
      }
    } else if (source != null && pending != null) {
      if (_handleConnectionDrop(source, pending.pointer)) {
        // The Create menu is up at the drop point. The wire stays drawn,
        // frozen where it was let go, until the menu closes — the gesture is
        // not over from where the person sits, and a wire that vanished the
        // moment the menu appeared read as the drop having failed. Only the
        // drag ends here: the source and target go, so a pointer moving over
        // the menu cannot go on steering a wire nobody is holding.
        setState(() {
          _pendingSource = null;
          _pendingTarget = null;
        });
        return;
      }
    }
    _clearPendingConnection();
  }

  /// A wire let go with nothing under it.
  ///
  /// Either the host's hook, or — when `createOnDrop` is on — the Create menu
  /// at the drop point, which then wires up whatever it made. Never both: one
  /// gesture must not be able to produce two nodes.
  ///
  /// True when the menu was opened, which is the caller's cue to keep the
  /// wire on screen until it closes.
  bool _handleConnectionDrop(PortRef source, Offset scenePosition) {
    final menus = widget.contextMenus;
    if (menus == null || !menus.createOnDrop) {
      widget.onConnectionDropped?.call(source, scenePosition);
      return false;
    }

    final request = _menuRequest(NodeMenuCanvasTarget(scenePosition));
    final entries = menus.createEntriesFor(request, (type) {
      // One transaction, so undo takes back the node and its wire together —
      // half a dropped connection is not a state worth stopping at.
      _controller.history.beginTransaction();
      final id = NodeEditorMenus.createNode(request, type);
      final created = _controller.graph.nodes[id];
      final target = created == null
          ? null
          : _firstCompatiblePort(created, source);
      if (target != null) _controller.connect(source, target);
      _controller.history.commitTransaction();
    });

    final host = _menuHostKey.currentState;
    if (host == null) return false;
    return host.open(entries, _viewport.toScreen(scenePosition));
  }

  /// The menu has gone, however it went: chosen, dismissed, or closed by a
  /// click elsewhere.
  ///
  /// Two things, and both belong to the editor rather than to the host widget:
  /// the canvas takes focus back, since its shortcuts are gated on holding it
  /// and the menu took it; and a wire held on screen for a create-on-drop is
  /// let go of — the real wire, if one was made, is in the graph by now.
  void _handleMenuClosed() {
    _focusNode.requestFocus();
    _clearPendingConnection();
  }

  void _clearPendingConnection() {
    if (_pendingSource == null && _pending == null) return;
    setState(() {
      _pendingSource = null;
      _pendingTarget = null;
      _pending = null;
    });
  }

  // ----------------------------------------------------------------- menus

  /// Routes a secondary tap to whatever is under it.
  ///
  /// Priority is port, then node, then link, then canvas — the same order the
  /// primary path already uses, and it matters most for ports: half of a
  /// handle hangs outside its node, so the two halves of one dot arrive here
  /// from two different recognisers.
  void _handleSecondaryTap(Offset globalPosition, {GraphNode? onNode}) {
    final scene = _toScene(globalPosition);

    final port = _portAt(scene);
    if (port != null) {
      if (widget.onPortSecondaryTap != null) {
        widget.onPortSecondaryTap!(port, globalPosition);
        return;
      }
      _openMenu(NodeMenuPortTarget(port, scene), globalPosition);
      return;
    }

    if (onNode != null) {
      if (widget.onNodeSecondaryTap != null) {
        widget.onNodeSecondaryTap!(onNode, globalPosition);
        return;
      }
      // Selection-based entries are only honest if something is selected.
      // A node already in a multi-selection keeps it, so "Delete" on one of
      // five deletes five, which is what having selected them meant.
      if (!_controller.selection.containsNode(onNode.id)) {
        _controller.selection.selectNode(onNode.id);
      }
      _openMenu(NodeMenuNodeTarget(onNode, scene), globalPosition);
      return;
    }

    final connectionId = _connections.hitTest(
      scene,
      tolerance: _connectionTolerance,
    );
    final connection = connectionId == null
        ? null
        : _controller.graph.connections[connectionId];
    if (connection != null) {
      if (widget.onConnectionSecondaryTap != null) {
        widget.onConnectionSecondaryTap!(connection, globalPosition);
        return;
      }
      _controller.selection.selectConnection(connection.id);
      _openMenu(NodeMenuConnectionTarget(connection, scene), globalPosition);
      return;
    }

    if (widget.onCanvasSecondaryTap != null) {
      widget.onCanvasSecondaryTap!(scene, globalPosition);
      return;
    }
    _openMenu(NodeMenuCanvasTarget(scene), globalPosition);
  }

  void _openMenu(NodeMenuTarget target, Offset globalPosition) {
    final menus = widget.contextMenus;
    if (menus == null) return;
    _menuHostKey.currentState?.open(
      menus.entriesFor(_menuRequest(target)),
      _toLocal(globalPosition),
    );
  }

  NodeMenuRequest _menuRequest(NodeMenuTarget target) => NodeMenuRequest(
    controller: _controller,
    target: target,
    viewportSize: viewportSize,
    describeNode: _describeNode,
    renameGroup: _renameGroup,
    newProject: _newProject,
    openProject: _openProject,
    saveProject: _saveProject,
  );

  void _describeNode(GraphNode node, String description) {
    unawaited(
      showNodeDescription(
        context,
        description: description,
        title: _controller.prototypes[node.type]?.label ?? node.type,
      ),
    );
  }

  void _reportMenuError(Object error, StackTrace stackTrace) {
    final onError = widget.contextMenus?.onError;
    if (onError != null) {
      onError(error, stackTrace);
      return;
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'fl_nodes_v2',
        context: ErrorDescription('while running a context menu action'),
      ),
    );
  }

  Future<void> _newProject() async {
    // Discarding unsaved work silently, from a menu one keystroke away from
    // "Save", is the one action here that cannot be undone.
    if (_controller.project.isDirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard unsaved changes?'),
          content: const Text(
            'This document has changes that have not been saved.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    _controller.project.reset();
  }

  Future<void> _openProject() async {
    try {
      await _controller.project.load();
    } catch (error, stackTrace) {
      if (!mounted) return;
      _reportMenuError(error, stackTrace);
    }
  }

  Future<void> _saveProject() async {
    try {
      await _controller.project.save();
    } catch (error, stackTrace) {
      if (!mounted) return;
      _reportMenuError(error, stackTrace);
    }
  }

  // -------------------------------------------------------------- keyboard

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // Before anything else, and before the host's shortcut switch: the menu
    // anchors to a point rather than to the canvas, so its own Escape handling
    // is not above us in the focus chain and this key would otherwise reach
    // the canvas and clear the selection with the menu still up.
    if (_menuController.isOpen) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _menuController.close();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (!widget.enableKeyboardShortcuts) return KeyEventResult.ignored;

    // Only act when the canvas itself holds focus, never when something inside
    // a node does. A text field leaves backspace unhandled once there is
    // nothing left to delete, and the event then bubbles up here — which would
    // delete the node the field belongs to.
    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;

    final keyboard = HardwareKeyboard.instance;
    final command = keyboard.isControlPressed || keyboard.isMetaPressed;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _controller.selection.deleteSelected();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_pending != null) {
        _clearPendingConnection();
      } else if (_canvasGesture == _CanvasGesture.marquee) {
        _abandonMarquee();
      } else {
        _controller.selection.clear();
      }
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyA) {
      _controller.selection.selectAll();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyZ) {
      keyboard.isShiftPressed
          ? _controller.history.redo()
          : _controller.history.undo();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyY) {
      _controller.history.redo();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyC) {
      _controller.clipboard.copy();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyX) {
      _controller.clipboard.cut();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyV) {
      _pasteFromClipboard();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyD) {
      _controller.clipboard.duplicate();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyG) {
      _controller.groupSelection();
      return KeyEventResult.handled;
    }

    final nudge = _nudgeFor(key);
    if (nudge != null && _controller.selection.nodeIds.isNotEmpty) {
      final grid = _theme.snapToGrid > 0 ? _theme.snapToGrid : 8.0;
      final step = keyboard.isShiftPressed ? 1.0 : grid;
      _controller.translateNodes(
        _controller.selection.nodeIds.toList(),
        nudge * step,
      );
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// Asks the system clipboard first so a selection copied in another window
  /// arrives, falling back to the in-process buffer — which is all there is
  /// when the host configured no codec.
  ///
  /// A key press has nowhere to return a failure to, and dropping it would
  /// leave Ctrl+V looking broken when a document on the clipboard cannot be
  /// read. Reporting it puts the reason in the console and in front of any
  /// error handler the app installed. A host that wants to *show* the failure
  /// calls [NodeEditorClipboard.pasteFromSystem] itself and catches it.
  Future<void> _pasteFromClipboard() async {
    try {
      await _controller.clipboard.pasteFromSystem();
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'fl_nodes_v2',
          context: ErrorDescription('pasting from the system clipboard'),
        ),
      );
    }
  }

  static Offset? _nudgeFor(LogicalKeyboardKey key) => switch (key) {
    LogicalKeyboardKey.arrowLeft => const Offset(-1, 0),
    LogicalKeyboardKey.arrowRight => const Offset(1, 0),
    LogicalKeyboardKey.arrowUp => const Offset(0, -1),
    LogicalKeyboardKey.arrowDown => const Offset(0, 1),
    _ => null,
  };

  // ----------------------------------------------------------- public API

  /// The most recent size of the canvas, for callers driving
  /// [NodeEditorCamera.fitToContent] from outside.
  Size get viewportSize => _viewportSize;

  /// The cache backing connection painting and picking. Exposed for
  /// diagnostics: [ConnectionLayout.rebuildCount] shows how often paths are
  /// actually being recomputed.
  ConnectionLayout get connectionLayout => _connections;

  /// How many nodes the editor is currently holding per-node widget state for.
  ///
  /// Should track the number on screen, not the number in the document.
  @visibleForTesting
  int get debugTrackedNodeCount => _slots.length;

  /// The cached minimap panel, for the isolation test: a pan must hand back
  /// the identical widget, or the panel's chrome is being rebuilt every frame.
  @visibleForTesting
  Object? get debugMinimapPanel => _minimapSlot.view;

  /// Frames the whole graph in the current viewport.
  ///
  /// Auto-height nodes only report their real size after a layout pass, so
  /// this waits for the measurements to land before committing to a zoom —
  /// otherwise the first fit is computed against fallback heights. The retry
  /// is bounded, since a node that stays culled never reports at all.
  void fitToContent({
    EdgeInsets padding = const EdgeInsets.all(48),
    double maxScale = 1.0,
  }) {
    _pendingFitAttempts = 3;
    _attemptFit(padding, maxScale);
  }

  int _pendingFitAttempts = 0;

  void _attemptFit(EdgeInsets padding, double maxScale) {
    if (_controller.layout.hasUnmeasuredNodes && _pendingFitAttempts > 0) {
      _pendingFitAttempts--;
      // Registering a post-frame callback does not itself request a frame, and
      // an idle editor may not schedule one on its own.
      WidgetsBinding.instance
        ..addPostFrameCallback((_) {
          if (mounted) _attemptFit(padding, maxScale);
        })
        ..scheduleFrame();
      return;
    }
    _controller.camera.fitToContent(
      _viewportSize,
      padding: padding,
      maxScale: maxScale,
    );
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return NodeEditorScope(
      controller: _controller,
      theme: _theme,
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            _viewportSize = constraints.biggest;
            return _buildCanvas(constraints.biggest);
          },
        ),
      ),
    );
  }

  Widget _buildCanvas(Size size) {
    final viewport = _viewport;
    final theme = _theme;
    // Cheap when nothing moved: compares one revision counter.
    _connections.sync(_controller);

    // Culled once and shared: the node layer builds these, and the port
    // painter draws their handles over the top.
    final visible = viewport.visibleSceneRect(size);
    final drawn = _controller.layout.nodesIn(
      visible.inflate(theme.portHitRadius * 2),
    );
    // Asked for separately: a frame reaches beyond its members, and two of
    // them either side of the screen leave it crossing a viewport that neither
    // node is in.
    final groups = _controller.layout.groupsIn(visible);
    final connected = _connectedPorts();

    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _handleKeyEvent,
      child: Listener(
        onPointerDown: (event) {
          _pointerButtons = event.buttons;
          _pointerKind = event.kind;
          _pointerDownPosition = event.localPosition;
        },
        onPointerSignal: _handlePointerSignal,
        onPointerPanZoomStart: _handlePanZoomStart,
        onPointerPanZoomUpdate: _handlePanZoomUpdate,
        child: MouseRegion(
          onHover: _handleHover,
          onExit: (_) => setState(() {
            _hoveredConnectionId = null;
            _hoveredPort = null;
          }),
          cursor: switch (_canvasGesture) {
            _CanvasGesture.pan => SystemMouseCursors.grabbing,
            _ when _hoveredPort != null => SystemMouseCursors.precise,
            _ => MouseCursor.defer,
          },
          child: ClipRect(
            child: Stack(
              key: _canvasKey,
              fit: StackFit.expand,
              children: <Widget>[
                RepaintBoundary(
                  child: CustomPaint(
                    painter: GridPainter(
                      viewport: viewport,
                      theme: theme,
                      shader: _gridShader,
                    ),
                    size: size,
                  ),
                ),
                RepaintBoundary(
                  child: CustomPaint(
                    painter: ConnectionsPainter(
                      layout: _connections,
                      graph: _controller.graph,
                      revision: _controller.revision,
                      viewport: viewport,
                      theme: theme,
                      selectedIds: _controller.selection.connectionIds,
                      selectionRevision: _controller.selection.revision,
                      hoveredId: _hoveredConnectionId,
                      labelStyle: _labelStyle(),
                      prototypes: _controller.prototypes,
                    ),
                    size: size,
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: _handleCanvasTapUp,
                  onSecondaryTapUp: (details) =>
                      _handleSecondaryTap(details.globalPosition),
                  onScaleStart: _handleScaleStart,
                  onScaleUpdate: _handleScaleUpdate,
                  onScaleEnd: _handleScaleEnd,
                ),
                _buildNodeLayer(size, viewport, theme, drawn, groups),
                // Above the nodes: a handle sits on its node's border and has
                // to read over the card, including over a neighbour that
                // happens to overlap it.
                RepaintBoundary(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: PortsPainter(
                        nodes: drawn,
                        sizeOf: _controller.layout.sizeOf,
                        connectedPorts: connected,
                        viewport: viewport,
                        theme: theme,
                        revision: _controller.revision,
                        hovered: _hoveredPort,
                        highlighted: _pendingTarget,
                        // Handles draw above the whole node layer, scrim
                        // included, so a dimmed card would otherwise keep a
                        // row of bright dots floating over the wash.
                        lifted: _controller.emphasis.lifted,
                      ),
                      size: size,
                    ),
                  ),
                ),
                IgnorePointer(
                  child: CustomPaint(
                    painter: OverlayPainter(
                      viewport: viewport,
                      theme: theme,
                      pending: _pending,
                      marquee: _marquee,
                    ),
                    size: size,
                  ),
                ),
                // Last, so its zero-sized anchor sits above the layers the
                // menu opens over. The menu itself renders in an overlay.
                NodeEditorMenuHost(
                  key: _menuHostKey,
                  controller: _menuController,
                  onClosed: _handleMenuClosed,
                ),
                // After the menu host, because a Stack hit-tests back to
                // front and the panel wants its presses. Costs nothing to be
                // last: that host is a zero-sized anchor whose menu renders in
                // the route overlay, above every layer regardless of order.
                if (widget.minimap case final MinimapConfig minimap)
                  _minimapSlot.build(this, minimap, size),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The node layer is a single scaled [Stack] whose local coordinates *are*
  /// scene coordinates for the visible region.
  ///
  /// Sizing it to the visible scene rect (rather than to the viewport) matters:
  /// a box only delivers pointer events within its own bounds, so a
  /// viewport-sized stack would leave panned-to nodes visible but dead.
  Widget _buildNodeLayer(
    Size size,
    ViewportTransform viewport,
    NodeEditorTheme theme,
    List<GraphNode> drawn,
    List<(NodeGroup, Rect)> groups,
  ) {
    final origin = viewport.visibleSceneRect(size).topLeft;
    final generation = ++_slotGeneration;

    // A frame paints immediately below the lowest of its own members, and no
    // lower: it has to sit under the nodes it holds without sinking beneath
    // whatever else the canvas has stacked underneath them.
    final rank = <String, int>{
      for (final (index, node) in drawn.indexed) node.id: index,
    };
    final under = <int, List<(NodeGroup, Rect)>>{};
    for (final entry in groups) {
      int? lowest;
      for (final id in entry.$1.nodeIds) {
        final index = rank[id];
        if (index != null && (lowest == null || index < lowest)) lowest = index;
      }
      // No member drawn at all means the frame is only visible because it
      // reaches past them — nothing of its own is on screen to be above.
      (under[lowest ?? 0] ??= <(NodeGroup, Rect)>[]).add(entry);
    }

    // Where the focus scrim goes: immediately below the first lifted node, so
    // everything under it is washed and everything from there up stands clear.
    // Before that index's group bucket rather than after, so a frame whose
    // lowest member is lifted rises with it — groups are not emphasised
    // individually, and a frame left behind its own contents reads as a bug.
    final lifted = _controller.emphasis.lifted;
    final focusAt = lifted.isEmpty
        ? -1
        : drawn.indexWhere((node) => lifted.contains(node.id));

    final children = <Widget>[];
    for (var index = 0; index <= drawn.length; index++) {
      if (index == focusAt) {
        children.add(
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: EmphasisPainter(
                  emphasis: _controller.emphasis.value,
                  emphasisRevision: _controller.emphasis.revision,
                  lifted: drawn.sublist(focusAt),
                  sizeOf: _controller.layout.sizeOf,
                  connections: _connections,
                  origin: origin,
                  scale: viewport.scale,
                  theme: theme,
                  revision: _controller.revision,
                ),
              ),
            ),
          ),
        );
      }
      for (final (group, frame)
          in under[index] ?? const <(NodeGroup, Rect)>[]) {
        children.add(
          Positioned(
            key: ValueKey<String>('group:${group.id}'),
            left: frame.left - origin.dx,
            top: frame.top - origin.dy,
            width: frame.width,
            height: frame.height,
            child: GroupView(
              group: group,
              theme: theme,
              isSelected: _controller.selection.containsGroup(group.id),
              onTap: (additive) => _handleGroupTap(group, additive),
              onSecondaryTap: (at) => _handleGroupSecondaryTap(group, at),
              onRename: () => _renameGroup(group),
              onColorPicked: (color) =>
                  _controller.setGroupColor(group.id, color),
              onDragStart: (at, additive) =>
                  _handleGroupDragStart(group, at, additive),
              onDragUpdate: _handleNodeDragUpdate,
              onDragEnd: _handleNodeDragEnd,
            ),
          ),
        );
      }
      if (index == drawn.length) break;

      final node = drawn[index];
      final slot = _slots.putIfAbsent(node.id, () => _NodeSlot(this, node.id));
      slot.generation = generation;
      children.add(
        Positioned(
          // The key belongs on the Stack's direct child. Paint order
          // reorders this list whenever the selection changes, and an
          // unkeyed Positioned would be matched by slot — rebuilding
          // the node beneath it from scratch, destroying its state and
          // cancelling any gesture it was in the middle of.
          key: slot.key,
          left: node.position.dx - origin.dx,
          top: node.position.dy - origin.dy,
          child: slot.build(node, theme),
        ),
      );
    }
    _slots.removeWhere((_, slot) => slot.generation != generation);

    final visible = viewport.visibleSceneRect(size);
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: Transform.scale(
          scale: viewport.scale,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: visible.width,
            height: visible.height,
            child: Stack(clipBehavior: Clip.none, children: children),
          ),
        ),
      ),
    );
  }

  /// Which ports currently have a wire on them, for every node at once.
  ///
  /// Asking per node per frame walked that node's connections and allocated a
  /// fresh set every time — and a fresh set is never identical to the last
  /// one, which alone would defeat the reuse [_NodeSlot] depends on.
  ///
  /// Keyed on the connection map rather than on the revision, because moving a
  /// node bumps the revision while leaving that map untouched: keying on the
  /// revision would hand out fresh sets on every frame of a drag, which is
  /// precisely the case this exists for.
  Map<String, Set<String>> _connectedPorts() {
    final connections = _controller.graph.connections;
    if (identical(_connectedPortsSource, connections)) {
      return _connectedPortsCache;
    }
    _connectedPortsSource = connections;
    final previous = _connectedPortsCache;
    final map = <String, Set<String>>{};
    for (final connection in connections.values) {
      (map[connection.from.nodeId] ??= <String>{}).add(connection.from.portId);
      (map[connection.to.nodeId] ??= <String>{}).add(connection.to.portId);
    }
    // Hand back the *previous* set wherever a node's wiring did not actually
    // change. Drawing one wire rewrites this map, and a fresh set for every
    // node would then rebuild every node on screen to say the same thing.
    for (final id in map.keys) {
      final before = previous[id];
      final now = map[id]!;
      if (before != null &&
          before.length == now.length &&
          before.containsAll(now)) {
        map[id] = before;
      }
    }
    return _connectedPortsCache = map;
  }
}

/// One node's widget and the callbacks that drive it, kept across rebuilds.
///
/// Anything on the controller changing rebuilds the whole canvas: a pan, a
/// selection, one node moving. Handing back the *same* [NodeView] instance for
/// a node none of that touched makes `Element.updateChild` short-circuit, so
/// the host's body — an arbitrarily expensive subtree, possibly with text
/// fields in it — is left alone. That only works if the callbacks are stable
/// too, which is the other half of what this holds: a closure rebuilt per
/// frame would make every node look changed.
class _NodeSlot {
  _NodeSlot(this._editor, this.nodeId) : key = ValueKey<String>(nodeId);

  final NodeEditorState _editor;
  final String nodeId;
  final ValueKey<String> key;

  /// Build pass this slot was last used in. Slots whose node scrolled out of
  /// the cull rect are dropped rather than accumulating for the session.
  int generation = -1;

  // The inputs the cached view was built from.
  GraphNode? _node;
  NodeEditorTheme? _theme;
  bool _selected = false;
  bool _dragging = false;
  bool _connectionTarget = false;
  NodeWidgetBuilder? _builder;
  bool _hasDoubleTap = false;
  bool _hasSecondaryTap = false;
  Widget? _view;

  /// Looked up when a gesture fires rather than captured, so a stale node
  /// cannot be handed to the host after the graph moved on.
  GraphNode? get _liveNode => _editor._controller.graph.nodes[nodeId];

  void _onContentSized(Size size) =>
      _editor._controller.layout.reportMeasuredSize(nodeId, size);

  void _onTap(bool additive) {
    final node = _liveNode;
    if (node != null) _editor._handleNodeTap(node, additive);
  }

  void _onDoubleTap() {
    final node = _liveNode;
    if (node != null) _editor.widget.onNodeDoubleTap?.call(node);
  }

  void _onSecondaryTap(Offset globalPosition) {
    final node = _liveNode;
    // A handle painted on this node's border is inside its gesture area, so
    // this recogniser wins the press for it too — the same question
    // `_handleNodeDragStart` has to ask before assuming a drag meant the node.
    if (node != null) {
      _editor._handleSecondaryTap(globalPosition, onNode: node);
    }
  }

  void _onDragStart(Offset globalPosition, bool additive) {
    final node = _liveNode;
    if (node != null) {
      _editor._handleNodeDragStart(node, globalPosition, additive);
    }
  }

  Widget build(GraphNode node, NodeEditorTheme theme) {
    final editor = _editor;
    final selected = editor._controller.selection.containsNode(nodeId);
    final dragging = editor._draggingNodeIds.contains(nodeId);
    final isTarget = editor._pendingTarget?.nodeId == nodeId;
    // A note is the editor's own to draw. The host's builder never sees one,
    // so a host neither has to know the type exists nor can be handed a node
    // it has no case for.
    final builder = NodeComment.isComment(node)
        ? editor._commentBuilder
        : editor.widget.nodeBuilder;
    final hasDoubleTap = editor.widget.onNodeDoubleTap != null;
    // Menus mean the node always wants the press: without a handler the
    // detector stays opaque and swallows the click instead of letting the
    // canvas see it.
    final hasSecondaryTap =
        editor.widget.onNodeSecondaryTap != null ||
        editor.widget.contextMenus != null;

    final cached = _view;
    if (cached != null &&
        identical(_node, node) &&
        identical(_theme, theme) &&
        identical(_builder, builder) &&
        _selected == selected &&
        _dragging == dragging &&
        _connectionTarget == isTarget &&
        _hasDoubleTap == hasDoubleTap &&
        _hasSecondaryTap == hasSecondaryTap) {
      return cached;
    }

    _node = node;
    _theme = theme;
    _selected = selected;
    _dragging = dragging;
    _connectionTarget = isTarget;
    _builder = builder;
    _hasDoubleTap = hasDoubleTap;
    _hasSecondaryTap = hasSecondaryTap;

    return _view = RepaintBoundary(
      child: NodeView(
        node: node,
        theme: theme,
        builder: builder,
        isSelected: selected,
        isDragging: dragging,
        isConnectionTarget: isTarget,
        onContentSized: _onContentSized,
        onTap: _onTap,
        onDoubleTap: hasDoubleTap ? _onDoubleTap : null,
        onSecondaryTap: hasSecondaryTap ? _onSecondaryTap : null,
        onDragStart: _onDragStart,
        onDragUpdate: _editor._handleNodeDragUpdate,
        onDragEnd: _editor._handleNodeDragEnd,
      ),
    );
  }
}

/// Caches the minimap panel's widget instance, exactly as [_NodeSlot] caches a
/// node's and for the same reason.
///
/// The editor rebuilds its whole canvas on every controller notification —
/// which includes every camera tick. Handing back the *identical*
/// [MinimapPanel] makes `Element.updateChild` short-circuit, so the panel's
/// chrome is not rebuilt while you scroll. The map still repaints: its painter
/// takes a `repaint` listenable, which is the other half of the arrangement.
class _MinimapSlot {
  MinimapConfig? _config;
  MinimapController? _minimap;
  NodeEditorTheme? _theme;
  Size? _viewportSize;
  Widget? _view;

  Widget? get view => _view;

  Widget build(NodeEditorState editor, MinimapConfig config, Size viewport) {
    final minimap = editor._minimap;
    final theme = editor._theme;

    final cached = _view;
    if (cached != null &&
        _config == config &&
        identical(_minimap, minimap) &&
        identical(_theme, theme) &&
        _viewportSize == viewport) {
      return cached;
    }

    _config = config;
    _minimap = minimap;
    _theme = theme;
    _viewportSize = viewport;

    return _view = MinimapPanel(
      key: const ValueKey<String>('minimap'),
      controller: editor._controller,
      minimap: minimap,
      config: config,
      theme: theme,
      connections: editor._connections,
      viewportSize: viewport,
      // The held tear-off, never a closure read per build.
      onMenuClosed: editor._requestCanvasFocus,
      onRectChanged: editor._setMinimapRect,
    );
  }
}
