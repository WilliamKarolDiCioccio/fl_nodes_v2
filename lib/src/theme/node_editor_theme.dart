import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../geometry/connection_path.dart' show ConnectionStyle;
import '../model/node_port.dart' show PortKind;
import '../painting/port_shape.dart' show PortShape;

/// Visual configuration for the canvas chrome: grid, connections, ports,
/// selection affordances and zoom limits.
///
/// Node bodies are drawn by the host's builder and are deliberately not
/// themed here.
@immutable
class NodeEditorTheme {
  const NodeEditorTheme({
    required this.background,
    required this.gridLine,
    required this.gridLineMajor,
    required this.connectionColor,
    required this.selectedConnectionColor,
    required this.hoveredConnectionColor,
    required this.pendingConnectionColor,
    required this.invalidConnectionColor,
    required this.portColor,
    required this.portHoverColor,
    required this.portBorderColor,
    required this.selectionColor,
    required this.marqueeColor,
    this.showGrid = true,
    this.gridSpacing = 24,
    this.gridMajorEvery = 5,
    this.connectionWidth = 2,
    this.selectedConnectionWidth = 3,
    this.connectionCurvature = 0.5,
    this.connectionStyle = ConnectionStyle.curved,
    this.connectionStub = 24,
    this.connectionCornerRadius = 8,
    this.waypointAlignSnap = 6,
    this.controlPortShape = PortShape.triangle,
    this.dataPortShape = PortShape.circle,
    this.portRadius = 6,
    this.portHitRadius = 11,
    this.portMinScale = 0.25,
    this.waypointRadius = 4.5,
    this.waypointHitRadius = 9,
    this.selectionWidth = 2,
    this.selectionRadius = const Radius.circular(10),
    this.selectionInset = 3,
    this.minScale = 0.15,
    this.maxScale = 3.0,
    this.snapToGrid = 0,
    this.connectionHitTolerance = 9,
    this.connectionArrowSpacing = 140,
    this.connectionArrowMaxCount = 4,
    this.scrimOpacity = 0.62,
    this.emphasisInset = 7,
    this.emphasisRadius = const Radius.circular(14),
    this.scrimColor,
  });

  factory NodeEditorTheme.dark({Color accent = const Color(0xFF7C9CF5)}) {
    return NodeEditorTheme(
      background: const Color(0xFF15171C),
      gridLine: const Color(0x14FFFFFF),
      gridLineMajor: const Color(0x24FFFFFF),
      connectionColor: const Color(0xFF6B7386),
      selectedConnectionColor: accent,
      hoveredConnectionColor: const Color(0xFF9AA3B8),
      pendingConnectionColor: accent,
      invalidConnectionColor: const Color(0xFFE05A6B),
      portColor: const Color(0xFF8B93A7),
      portHoverColor: accent,
      portBorderColor: const Color(0xFF15171C),
      selectionColor: accent,
      marqueeColor: accent,
    );
  }

  factory NodeEditorTheme.light({Color accent = const Color(0xFF3B62D9)}) {
    return NodeEditorTheme(
      background: const Color(0xFFF6F7FA),
      gridLine: const Color(0x11000000),
      gridLineMajor: const Color(0x1F000000),
      connectionColor: const Color(0xFF9AA1B2),
      selectedConnectionColor: accent,
      hoveredConnectionColor: const Color(0xFF6C7488),
      pendingConnectionColor: accent,
      invalidConnectionColor: const Color(0xFFD1435B),
      portColor: const Color(0xFF7E869B),
      portHoverColor: accent,
      portBorderColor: const Color(0xFFF6F7FA),
      selectionColor: accent,
      marqueeColor: accent,
    );
  }

  final Color background;
  final Color gridLine;
  final Color gridLineMajor;
  final bool showGrid;

  /// Scene-space distance between minor grid lines.
  final double gridSpacing;

  /// Every n-th grid line is drawn with [gridLineMajor].
  final int gridMajorEvery;

  final Color connectionColor;
  final Color selectedConnectionColor;
  final Color hoveredConnectionColor;

  /// Colour of the curve being dragged out of a port.
  final Color pendingConnectionColor;

  /// Colour of that curve while it is over an invalid drop target.
  final Color invalidConnectionColor;

  final double connectionWidth;
  final double selectedConnectionWidth;

  /// Fraction of the endpoint distance used for the bezier control arms.
  final double connectionCurvature;

  /// Curved or right-angled, for every wire on the canvas.
  ///
  /// One choice for the whole canvas rather than one per wire: which reads
  /// better is a question about the graph and its reader. The waypoints
  /// mean the same under both, so switching moves no data.
  final ConnectionStyle connectionStyle;

  /// How far an orthogonal wire runs straight out of a port before it may
  /// turn, in scene units.
  final double connectionStub;

  /// What a control handle and a data handle are drawn as.
  ///
  /// Two shapes rather than one, because the two pins do different jobs and a
  /// reader should be able to tell which is which without tracing a wire —
  /// the same argument the port *colour* already makes, one step louder. The
  /// default pairs a triangle with a dot; a host that wants the old row of
  /// identical dots sets both to [PortShape.circle].
  ///
  /// Per kind and not per port: which shape reads as which kind is a question
  /// about the canvas, the way [connectionStyle] is.
  final PortShape controlPortShape;
  final PortShape dataPortShape;

  /// The shape [kind] is drawn as under this theme.
  PortShape shapeOf(PortKind kind) =>
      kind == PortKind.control ? controlPortShape : dataPortShape;

  /// The radius of an orthogonal wire's corners, in scene units.
  final double connectionCornerRadius;

  /// How close a dragged waypoint has to come to lining up with its
  /// neighbour, in screen pixels, before it is pulled onto that line.
  ///
  /// Orthogonal only: a handle is a corner there, and a corner one pixel
  /// off its neighbour's row draws a one-pixel jog. Zero turns it off.
  final double waypointAlignSnap;

  /// Screen-space slop when picking a connection.
  final double connectionHitTolerance;

  /// Scene distance aimed for between the direction arrows on a connection.
  ///
  /// The count is rounded to fit the curve's length and clamped to
  /// `1..connectionArrowMaxCount`, so a short wire still says which way it
  /// points and a long one across the canvas does not turn into a dotted line.
  final double connectionArrowSpacing;

  final int connectionArrowMaxCount;

  final Color portColor;
  final Color portHoverColor;
  final Color portBorderColor;

  /// Drawn radius of a port handle, in scene units.
  final double portRadius;

  /// Touch target radius of a port handle, in scene units.
  final double portHitRadius;

  /// Below this zoom, handles stop being drawn *and* stop being hittable.
  ///
  /// One rule for both on purpose: a handle too small to see is also too small
  /// to aim at — at 15% zoom the whole target is under two pixels across — and
  /// a dot that is invisible but still starts a wire is worse than one that is
  /// simply not there yet.
  ///
  /// Handles are painted rather than built, so crossing this costs a repaint
  /// and nothing else. Doing the same by adding and removing widgets would
  /// rebuild every node on screen at the threshold, which is a stutter exactly
  /// where the user is already moving.
  final double portMinScale;

  /// Drawn radius of a waypoint handle on a routed wire, in scene units.
  ///
  /// Smaller than a port on purpose: a handle is a mark on a wire, not a
  /// place to start one, and the two must not read as the same thing.
  final double waypointRadius;

  /// Touch target radius of a waypoint handle, in scene units.
  final double waypointHitRadius;

  final Color selectionColor;
  final double selectionWidth;
  final Radius selectionRadius;

  /// How far the selection outline sits outside the node's bounds.
  final double selectionInset;

  final Color marqueeColor;

  /// The wash drawn over everything a [GraphEmphasis] does not lift.
  ///
  /// Null derives it from [background] at [scrimOpacity], which is what makes
  /// a focus dim *towards the canvas* in either brightness rather than towards
  /// black in one of them.
  final Color? scrimColor;

  /// How opaque the derived [scrimColor] is.
  ///
  /// Deliberately short of covering: a focus that erased its surroundings
  /// would answer "which routes are these" by throwing away the board they run
  /// across, and a connection caption underneath still has to be readable.
  final double scrimOpacity;

  /// How far an emphasis halo sits outside the node's bounds.
  final double emphasisInset;

  /// How round an emphasis halo's corners are.
  ///
  /// Its own value rather than a node radius, because the package has none:
  /// how round a card is belongs to whatever the host draws, so the halo says
  /// how round *it* is and a host tunes the two to agree.
  final Radius emphasisRadius;

  /// The scrim actually painted: [scrimColor] when given, else [background]
  /// faded to [scrimOpacity].
  Color get resolvedScrim =>
      scrimColor ?? background.withValues(alpha: scrimOpacity);

  final double minScale;
  final double maxScale;

  /// Grid size that dragged nodes snap to; 0 disables snapping.
  final double snapToGrid;

  NodeEditorTheme copyWith({
    Color? background,
    Color? gridLine,
    Color? gridLineMajor,
    bool? showGrid,
    double? gridSpacing,
    int? gridMajorEvery,
    Color? connectionColor,
    Color? selectedConnectionColor,
    Color? hoveredConnectionColor,
    Color? pendingConnectionColor,
    Color? invalidConnectionColor,
    double? connectionWidth,
    double? selectedConnectionWidth,
    double? connectionCurvature,
    ConnectionStyle? connectionStyle,
    PortShape? controlPortShape,
    PortShape? dataPortShape,
    double? connectionStub,
    double? connectionCornerRadius,
    double? waypointAlignSnap,
    double? connectionHitTolerance,
    double? connectionArrowSpacing,
    int? connectionArrowMaxCount,
    Color? portColor,
    Color? portHoverColor,
    Color? portBorderColor,
    double? portRadius,
    double? portHitRadius,
    double? portMinScale,
    double? waypointRadius,
    double? waypointHitRadius,
    Color? selectionColor,
    double? selectionWidth,
    Radius? selectionRadius,
    Color? scrimColor,
    double? scrimOpacity,
    double? emphasisInset,
    Radius? emphasisRadius,
    double? selectionInset,
    Color? marqueeColor,
    double? minScale,
    double? maxScale,
    double? snapToGrid,
  }) {
    return NodeEditorTheme(
      background: background ?? this.background,
      gridLine: gridLine ?? this.gridLine,
      gridLineMajor: gridLineMajor ?? this.gridLineMajor,
      showGrid: showGrid ?? this.showGrid,
      gridSpacing: gridSpacing ?? this.gridSpacing,
      gridMajorEvery: gridMajorEvery ?? this.gridMajorEvery,
      connectionColor: connectionColor ?? this.connectionColor,
      selectedConnectionColor:
          selectedConnectionColor ?? this.selectedConnectionColor,
      hoveredConnectionColor:
          hoveredConnectionColor ?? this.hoveredConnectionColor,
      pendingConnectionColor:
          pendingConnectionColor ?? this.pendingConnectionColor,
      invalidConnectionColor:
          invalidConnectionColor ?? this.invalidConnectionColor,
      connectionWidth: connectionWidth ?? this.connectionWidth,
      selectedConnectionWidth:
          selectedConnectionWidth ?? this.selectedConnectionWidth,
      connectionCurvature: connectionCurvature ?? this.connectionCurvature,
      connectionStyle: connectionStyle ?? this.connectionStyle,
      controlPortShape: controlPortShape ?? this.controlPortShape,
      dataPortShape: dataPortShape ?? this.dataPortShape,
      connectionStub: connectionStub ?? this.connectionStub,
      connectionCornerRadius:
          connectionCornerRadius ?? this.connectionCornerRadius,
      waypointAlignSnap: waypointAlignSnap ?? this.waypointAlignSnap,
      connectionHitTolerance:
          connectionHitTolerance ?? this.connectionHitTolerance,
      connectionArrowSpacing:
          connectionArrowSpacing ?? this.connectionArrowSpacing,
      connectionArrowMaxCount:
          connectionArrowMaxCount ?? this.connectionArrowMaxCount,
      portColor: portColor ?? this.portColor,
      portHoverColor: portHoverColor ?? this.portHoverColor,
      portBorderColor: portBorderColor ?? this.portBorderColor,
      portRadius: portRadius ?? this.portRadius,
      portHitRadius: portHitRadius ?? this.portHitRadius,
      portMinScale: portMinScale ?? this.portMinScale,
      waypointRadius: waypointRadius ?? this.waypointRadius,
      waypointHitRadius: waypointHitRadius ?? this.waypointHitRadius,
      selectionColor: selectionColor ?? this.selectionColor,
      selectionWidth: selectionWidth ?? this.selectionWidth,
      selectionRadius: selectionRadius ?? this.selectionRadius,
      scrimColor: scrimColor ?? this.scrimColor,
      scrimOpacity: scrimOpacity ?? this.scrimOpacity,
      emphasisInset: emphasisInset ?? this.emphasisInset,
      emphasisRadius: emphasisRadius ?? this.emphasisRadius,
      selectionInset: selectionInset ?? this.selectionInset,
      marqueeColor: marqueeColor ?? this.marqueeColor,
      minScale: minScale ?? this.minScale,
      maxScale: maxScale ?? this.maxScale,
      snapToGrid: snapToGrid ?? this.snapToGrid,
    );
  }

  /// Value equality keeps painters from repainting when a host rebuilds and
  /// hands over a freshly constructed but identical theme.
  List<Object?> get _props => <Object?>[
    background,
    gridLine,
    gridLineMajor,
    showGrid,
    gridSpacing,
    gridMajorEvery,
    connectionColor,
    selectedConnectionColor,
    hoveredConnectionColor,
    pendingConnectionColor,
    invalidConnectionColor,
    connectionWidth,
    selectedConnectionWidth,
    connectionCurvature,
    connectionStyle,
    controlPortShape,
    dataPortShape,
    connectionStub,
    connectionCornerRadius,
    waypointAlignSnap,
    connectionHitTolerance,
    connectionArrowSpacing,
    connectionArrowMaxCount,
    portColor,
    portHoverColor,
    portBorderColor,
    portRadius,
    portHitRadius,
    portMinScale,
    waypointRadius,
    waypointHitRadius,
    selectionColor,
    selectionWidth,
    selectionRadius,
    scrimColor,
    scrimOpacity,
    emphasisInset,
    emphasisRadius,
    selectionInset,
    marqueeColor,
    minScale,
    maxScale,
    snapToGrid,
  ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NodeEditorTheme && listEquals(other._props, _props);

  @override
  int get hashCode => Object.hashAll(_props);
}
