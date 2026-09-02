import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../controller/node_editor_controller.dart';
import '../painting/connection_layout.dart';
import '../theme/node_editor_theme.dart';
import 'minimap_config.dart';
import 'minimap_controller.dart';
import 'minimap_painter.dart';
import 'minimap_palette.dart';
import 'minimap_scene.dart';

/// The minimap, as a panel floating over the canvas.
///
/// **It is a readout and nothing else.** Nothing in here moves the camera: the
/// drag belongs to the panel, so it can be moved off whatever you are working
/// on. That is also what makes it cheap — a panel that never calls
/// [NodeEditorController] can never bump its revision, so it can never pull a
/// node body back into the rebuild.
///
/// Not exported. A host reaches it through `NodeEditor.minimap`.
class MinimapPanel extends StatefulWidget {
  const MinimapPanel({
    super.key,
    required this.controller,
    required this.minimap,
    required this.config,
    required this.theme,
    required this.connections,
    required this.viewportSize,
    required this.onMenuClosed,
    required this.onRectChanged,
  });

  final NodeEditorController controller;
  final MinimapController minimap;
  final MinimapConfig config;
  final NodeEditorTheme theme;
  final ConnectionLayout connections;

  /// Size of the canvas the panel is floating over.
  final Size viewportSize;

  /// Called when the gear menu closes, so canvas shortcuts apply again.
  final VoidCallback onMenuClosed;

  /// Where the panel ended up, for the editor's pointer guards. A plain field
  /// write on the editor's state — never a `setState`, or the panel would
  /// rebuild the canvas it is sitting on.
  final ValueChanged<Rect> onRectChanged;

  @override
  State<MinimapPanel> createState() => MinimapPanelState();
}

class MinimapPanelState extends State<MinimapPanel> {
  /// Owned here rather than by the painter, so it survives the painter being
  /// rebuilt for a new theme or a new panel size.
  final MinimapScene _scene = MinimapScene();

  late MinimapPainter _painter;
  late Widget _body;

  bool _hovered = false;
  bool _dragging = false;
  bool _menuOpen = false;

  Offset _dragAnchor = Offset.zero;
  Offset _dragFrom = Offset.zero;
  Offset _sizeAnchor = Offset.zero;
  Size _sizeFrom = Size.zero;

  /// How many times the scene geometry has been rebuilt, for the test that
  /// pins panning against it.
  @visibleForTesting
  int get debugSceneSyncs => _scene.syncCount;

  @override
  void initState() {
    super.initState();
    _buildBody();
  }

  @override
  void didUpdateWidget(MinimapPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (!identical(old.controller, widget.controller)) _scene.invalidate();
    if (!identical(old.controller, widget.controller) ||
        !identical(old.minimap, widget.minimap) ||
        !identical(old.connections, widget.connections) ||
        old.theme != widget.theme ||
        old.viewportSize != widget.viewportSize ||
        old.config.nodeColor != widget.config.nodeColor) {
      _buildBody();
    }
  }

  void _buildBody() {
    _painter = MinimapPainter(
      controller: widget.controller,
      minimap: widget.minimap,
      connections: widget.connections,
      scene: _scene,
      theme: widget.theme,
      viewportSize: widget.viewportSize,
      nodeColor: widget.config.nodeColor,
    );
    _body = RepaintBoundary(
      child: Stack(
        children: <Widget>[
          Positioned.fill(child: CustomPaint(painter: _painter)),
          Positioned(
            right: 0,
            bottom: 0,
            child: _MinimapGrip(
              color: MinimapPalette.forCanvas(widget.theme.background).edge,
              onStart: _onResizeStart,
              onUpdate: _onResizeUpdate,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- geometry

  Size get _viewport => widget.viewportSize;

  /// The panel's drawn size: what the controller says, clamped to the config's
  /// limits and then to the canvas, because a panel larger than the canvas it
  /// floats over cannot be used.
  Size _panelSize() {
    final config = widget.config;
    final size = widget.minimap.size;
    return Size(
      _clampExtent(
        size.width,
        config.minSize.width,
        config.maxSize.width,
        _viewport.width,
      ),
      _clampExtent(
        size.height,
        config.minSize.height,
        config.maxSize.height,
        _viewport.height,
      ),
    );
  }

  static double _clampExtent(
    double value,
    double min,
    double max,
    double available,
  ) {
    final ceiling = math.max(1.0, math.min(max, available));
    final floor = math.min(min, ceiling);
    return value.clamp(floor, ceiling);
  }

  Offset _initialPosition(Size panel) {
    final available = widget.config.margin.deflateRect(Offset.zero & _viewport);
    return widget.config.alignment.inscribe(panel, available).topLeft;
  }

  /// Clamped at *read* time and never written back.
  ///
  /// Writing during build would notify mid-build. And leaving the stored value
  /// alone means a window narrowed and widened again puts the panel back where
  /// it was put, rather than where the narrow window shoved it.
  Offset _resolvedPosition(Size panel) =>
      _clampPosition(widget.minimap.position ?? _initialPosition(panel), panel);

  Offset _clampPosition(Offset wanted, Size panel) => Offset(
    wanted.dx.clamp(0.0, math.max(0.0, _viewport.width - panel.width)),
    wanted.dy.clamp(0.0, math.max(0.0, _viewport.height - panel.height)),
  );

  // ------------------------------------------------------------- gestures

  void _onDragStart(DragStartDetails details) {
    _dragAnchor = details.globalPosition;
    _dragFrom = _resolvedPosition(_panelSize());
    setState(() => _dragging = true);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final panel = _panelSize();
    widget.minimap.position = _clampPosition(
      _dragFrom + (details.globalPosition - _dragAnchor),
      panel,
    );
  }

  void _onDragEnd() {
    if (_dragging) setState(() => _dragging = false);
  }

  void _onResizeStart(DragStartDetails details) {
    _sizeAnchor = details.globalPosition;
    _sizeFrom = _panelSize();
    setState(() => _dragging = true);
  }

  void _onResizeUpdate(DragUpdateDetails details) {
    final delta = details.globalPosition - _sizeAnchor;
    final config = widget.config;
    // Anchored at the top-left, so `position` is untouched and the grip stays
    // under the cursor.
    widget.minimap.size = Size(
      _clampExtent(
        _sizeFrom.width + delta.dx,
        config.minSize.width,
        config.maxSize.width,
        _viewport.width,
      ),
      _clampExtent(
        _sizeFrom.height + delta.dy,
        config.minSize.height,
        config.maxSize.height,
        _viewport.height,
      ),
    );
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.minimap,
    builder: _build,
    // Held apart from the builder: the map and its grip are rebuilt only when
    // `didUpdateWidget` says something real changed, so a panel drag rebuilds
    // one Positioned and one Column and nothing else.
    child: _body,
  );

  Widget _build(BuildContext context, Widget? body) {
    final minimap = widget.minimap;
    final palette = MinimapPalette.forCanvas(widget.theme.background);
    final panel = _panelSize();
    final position = _resolvedPosition(panel);
    final height = minimap.minimised
        ? MinimapController.barHeight
        : panel.height;

    widget.onRectChanged(position & Size(panel.width, height));

    return Stack(
      // Deliberately full-bleed with one positioned child. `RenderStack` has
      // no `hitTestSelf`, so a press beside the panel falls straight through
      // to the canvas underneath; and putting the `Positioned` in here rather
      // than at the editor's own `Stack` is what lets the panel move itself on
      // a drag without rerunning the editor's build.
      children: <Widget>[
        Positioned(
          left: position.dx,
          top: position.dy,
          width: panel.width,
          height: height,
          child: MouseRegion(
            // Opaque, unlike the host-side shortcuts overlay that had to be
            // `opaque: false`. That one is a third of the canvas and purely
            // decorative, so presses have to reach the marquee underneath.
            // This box is exactly the panel and wants its presses, and nothing
            // decorative reaches past it.
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: AnimatedOpacity(
              // Held solid while dragging — a fast drag outruns the pointer
              // out of the box — and while the gear is open.
              opacity: (_hovered || _dragging || _menuOpen)
                  ? 1
                  : minimap.idleOpacity,
              duration: const Duration(milliseconds: 160),
              child: Material(
                key: const ValueKey<String>('minimap.frame'),
                color: palette.surface,
                clipBehavior: Clip.hardEdge,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: palette.edge),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _MinimapBar(
                      config: widget.config,
                      minimap: minimap,
                      palette: palette,
                      onDragStart: _onDragStart,
                      onDragUpdate: _onDragUpdate,
                      onDragEnd: _onDragEnd,
                      onMenuOpened: () => setState(() => _menuOpen = true),
                      onMenuClosed: () {
                        setState(() => _menuOpen = false);
                        widget.onMenuClosed();
                      },
                    ),
                    if (!minimap.minimised) Expanded(child: body!),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The action bar: a grip, the title, the gear and the fold button.
///
/// **It carries no tap recogniser at all**, and that is deliberate rather than
/// an omission. `GroupView`'s handle had to synthesise its own double tap
/// because it needed `onTap` *and* a nested menu, and a
/// [DoubleTapGestureRecognizer] in the arena holds every single tap until the
/// timeout — including the taps meant for the menu. This bar needs neither, so
/// no tap recogniser ever enters the arena and the gear gets a clean press. Do
/// not add "double-click the bar to fold it" without reading that story first.
class _MinimapBar extends StatelessWidget {
  const _MinimapBar({
    required this.config,
    required this.minimap,
    required this.palette,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onMenuOpened,
    required this.onMenuClosed,
  });

  final MinimapConfig config;
  final MinimapController minimap;
  final MinimapPalette palette;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onMenuOpened;
  final VoidCallback onMenuClosed;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // From where the pointer went down, so the panel stays under the
        // cursor rather than trailing it by the touch slop — the same reason
        // the group handle does it.
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: onDragStart,
        onPanUpdate: onDragUpdate,
        onPanEnd: (_) => onDragEnd(),
        onPanCancel: onDragEnd,
        child: Container(
          height: MinimapController.barHeight,
          color: palette.bar,
          child: Row(
            children: <Widget>[
              const SizedBox(width: 6),
              Icon(Icons.drag_indicator, size: 15, color: palette.ink),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  config.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Spacer(),
              _MinimapSettingsMenu(
                config: config,
                minimap: minimap,
                palette: palette,
                onOpened: onMenuOpened,
                onClosed: onMenuClosed,
              ),
              _BarButton(
                // Folding, not closing. The glyph changes with the state
                // because an X on an already-folded panel reads as "close",
                // which is the one thing it does not do.
                icon: minimap.minimised ? Icons.open_in_full : Icons.close,
                tooltip: minimap.minimised ? 'Restore' : 'Minimise',
                color: palette.ink,
                onPressed: minimap.toggleMinimised,
              ),
              const SizedBox(width: 2),
            ],
          ),
        ),
      ),
    );
  }
}

/// A bar affordance.
///
/// `canRequestFocus: false` throughout the panel: `canvas_focus_test.dart`
/// exists because a shortcut reaching the wrong widget is worse than one
/// reaching nothing, and a button here quietly holding focus would send Delete
/// somewhere other than the canvas.
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      borderRadius: BorderRadius.circular(4),
      canRequestFocus: false,
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Icon(icon, size: 15, color: color),
      ),
    ),
  );
}

/// The gear, shaped exactly like `GroupView`'s colour menu — which is already
/// known to work nested inside a pan-handling detector.
class _MinimapSettingsMenu extends StatelessWidget {
  const _MinimapSettingsMenu({
    required this.config,
    required this.minimap,
    required this.palette,
    required this.onOpened,
    required this.onClosed,
  });

  final MinimapConfig config;
  final MinimapController minimap;
  final MinimapPalette palette;
  final VoidCallback onOpened;
  final VoidCallback onClosed;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      onOpen: onOpened,
      onClose: onClosed,
      menuChildren: <Widget>[
        SubmenuButton(
          menuChildren: <Widget>[
            for (final (label, scale) in MinimapConfig.zoomCapPresets)
              _Choice(
                label: label,
                selected: minimap.maxScale == scale,
                onPressed: () => minimap.maxScale = scale,
              ),
          ],
          child: const Text('Zoom cap'),
        ),
        SubmenuButton(
          menuChildren: <Widget>[
            for (final (label, size) in config.sizePresets)
              _Choice(
                label: label,
                selected: minimap.size == size,
                onPressed: () => minimap.size = size,
              ),
          ],
          child: const Text('Size'),
        ),
        SubmenuButton(
          menuChildren: <Widget>[
            // Node rects are not offered: they are the map.
            _Choice(
              label: 'Connections',
              selected: minimap.showConnections,
              onPressed: () =>
                  minimap.showConnections = !minimap.showConnections,
            ),
            _Choice(
              label: 'Group frames',
              selected: minimap.showGroups,
              onPressed: () => minimap.showGroups = !minimap.showGroups,
            ),
            _Choice(
              label: 'Comments',
              selected: minimap.showComments,
              onPressed: () => minimap.showComments = !minimap.showComments,
            ),
          ],
          child: const Text('Show'),
        ),
        SubmenuButton(
          menuChildren: <Widget>[
            for (final (label, opacity) in MinimapConfig.opacityPresets)
              _Choice(
                label: label,
                selected: minimap.idleOpacity == opacity,
                onPressed: () => minimap.idleOpacity = opacity,
              ),
          ],
          child: const Text('When idle'),
        ),
      ],
      builder: (context, menu, _) => InkWell(
        borderRadius: BorderRadius.circular(4),
        canRequestFocus: false,
        onTap: () => menu.isOpen ? menu.close() : menu.open(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Icon(Icons.settings, size: 15, color: palette.ink),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => MenuItemButton(
    leadingIcon: Icon(
      Icons.check,
      size: 16,
      // Kept in the layout rather than removed, so the labels do not shuffle
      // sideways as choices change.
      color: selected ? null : Colors.transparent,
    ),
    onPressed: onPressed,
    child: Text(label),
  );
}

/// The resize grip, in the corner opposite the action bar.
///
/// A `Stack` sibling *after* the map, never nested inside the bar's detector,
/// so the two drags never contend in the same arena.
class _MinimapGrip extends StatelessWidget {
  const _MinimapGrip({
    required this.color,
    required this.onStart,
    required this.onUpdate,
  });

  static const double size = 14;

  final Color color;
  final GestureDragStartCallback onStart;
  final GestureDragUpdateCallback onUpdate;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeDownRight,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onPanStart: onStart,
      onPanUpdate: onUpdate,
      child: CustomPaint(
        size: const Size.square(size),
        painter: _GripPainter(color),
      ),
    ),
  );
}

class _GripPainter extends CustomPainter {
  const _GripPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (final inset in <double>[3, 7]) {
      canvas.drawLine(
        Offset(size.width - 2, size.height - inset),
        Offset(size.width - inset, size.height - 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GripPainter old) => old.color != color;
}
