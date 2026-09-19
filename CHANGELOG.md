# Changelog

What a host can do with each version, newest first. The reasoning behind a
change lives beside the code in `CLAUDE.md`; this file only says what changed.

## 0.4.0

### Wires

- **Wires can be routed through waypoints.** Double-click a wire to add a
  handle on the curve, drag the handle to route the wire, double-click it to
  remove it; the wire's context menu offers *Add waypoint here*, *Remove
  waypoint* and *Clear waypoints*. `NodeConnection.waypoints`
  (`List<Offset>`, `const []`), with `setConnectionWaypoints`,
  `insertWaypoint`, `moveWaypoint` and `removeWaypoint` on the controller and
  `GraphEditKind.routeConnection` for `guard` and `onEdit`. A drag that moves
  both ends of a wire carries its route; `applyLayout` clears the routes of
  the wires it moves; a copy pastes with its route. Written to the document
  as an optional `waypoints` key, without a format version bump — an older
  build reads the wire and drops the route on its next save.
  `NodeEditorTheme.waypointRadius` (4.5) and `waypointHitRadius` (9);
  `NodeMenuConnectionTarget` gains `waypoint` and `insertion`.
- **Wires can be drawn in right angles.** `NodeEditorTheme.connectionStyle`
  (`ConnectionStyle`, `curved`) — `orthogonal` draws every wire as
  axis-aligned legs with rounded corners; a waypoint is then a corner, and a
  dragged handle snaps onto the row or column of its neighbours
  (`waypointAlignSnap`, 6 screen px). `connectionStub` (24) is how far a wire
  runs straight out of a port before it may turn, `connectionCornerRadius`
  (8) the arc at each corner. Neither style routes around cards.
  `ConnectionPath.build` takes `style`, `via`, `stub` and `cornerRadius`;
  `ConnectionPath.nearestOnRoute`, `ConnectionSpan`, `CubicSegment`,
  `PolylineSpan`, `RoutePoint` and `OrthogonalRoute` are public.
- **A drag held against the edge of the canvas scrolls it**, for a wire, a
  node, a group or a waypoint handle. `NodeEditor.edgeScroll`
  (`EdgeScrollConfig?`, `const EdgeScrollConfig()`) with `margin` (40) and
  `speed` (600 px/s), both in screen pixels; `null` turns it off.

### Nodes

- **A node body is told which of its ports are wired.**
  `NodeRenderState.connectedPorts` (`Set<String>`, `const {}`) and
  `isWired(portId)`, so a body can show an editor for a value only while no
  wire supplies it. Drawing a wire rebuilds the two bodies it touches and no
  others.
- **Every node carries metadata of its own.** `GraphNode.metadata`
  (`Map<String, Object?>`, `const {}`), beside `data` rather than in it, so a
  prototype's pruning of `data` cannot take a user's notes away.
  `copyWith(metadata:)`, `NodeEditorController.setNodeMetadata(id, map)`
  (reported as `updateNodes`; an equal map is not an edit). Written to the
  document only when non-empty, without a format version bump.

## 0.3.0

The first release since 0.1.0. `0.2.0` was never published; documents stamped
`fl_nodes_v2/0.2.0` were written by an unreleased build in between.

### Watching a run

- `NodeEditorRunner.onEvent` (`GraphRunListener?`, null) is handed a
  `GraphRunEvent` for every step of a run — `RunStarted`, `NodeStarted`,
  `NodeFinished`, `MemoHit`, `DiagnosticRaised`, `LogEmitted`, `RunFinished`
  — a sealed hierarchy, fired synchronously before the notification that
  follows. A listener that throws is reported and the run goes on.
- `NodeEditorRunner.tracePayloads` (`bool`, false) decides whether a
  `GraphTraceValue` carries the value on the wire; off, it is a
  `WithheldPayload` that still names the ports and the `dataType` tag. A wire
  nothing was written on is `AbsentPayload`.
- `NodeExecutionContext.log(message, {level, data})` lands on `GraphRun.log`
  and reaches the listener as `LogEmitted`.
- `GraphRun.id` climbs per run; every event carries it, its `sequence` and
  `at`. `GraphRunRecorder` is a list-backed listener for tests and demos.

### Documents

- `NodeGraphCodec.schemaVersion` (`int?`, null) and `schemaMigrations`
  (`Map<int, GraphDocumentMigration>`, empty) — the host's own version axis
  for what a node's `type` and `data` mean, stamped as `schema` and gated
  the way `version` is. A missing `schema` reads as 1; a null `schemaVersion`
  carries the key through untouched.
- `GraphDocumentMigrations.upgrade` gains `label` and `key`, so a gap in
  either chain names its axis.

### Nodes

- **A node's corner can be dragged** when its prototype says
  `NodePrototype.resizable` (`bool`, false), within `minWidth`, `maxWidth`
  and `maxHeight`. The height set this way is a floor, `GraphNode.minHeight`
  (`double?`, null), written to the document once set; ports stay on their
  rows (`NodeEditorLayout.anchorSizeOf`). One undo step per drag.
- `NodeEditorController.applyLayout(GraphLayout, {recordHistory})` places a
  whole arrangement in one edit, ignoring `draggable`; returns whether
  anything moved. `NodeEditorLayout.onMeasured` (`VoidCallback?`, null)
  fires once when every node has been measured.
- `NodeEditorController.guard` (`GraphEditGuard?`, null) can refuse an edit
  before it lands; `onEdit` (`GraphEditListener?`, null) is told what landed,
  as a `GraphEdit` with a `GraphEditKind` and the ids it touched. Undo and
  redo pass through neither.
- `NodeEditorController.emphasis` — a focus: a `GraphEmphasis` of nodes and
  connections that stand clear of a scrim washed over everything else,
  outside the document and the undo history. `NodeEditorTheme.scrimColor`
  (null, derived from `background`), `scrimOpacity` (0.62), `emphasisInset`
  (7), `emphasisRadius` (`Radius.circular(14)`).
- `ConnectionLabel.maxWidth` (160) is public, so a layout can leave room for
  a caption.

### Menus

- Submenus are `NodeSubmenuButton`: a cascade opens to the right of its row,
  slides up only as far as the window demands, and never flips above the
  row it opened from. The whole tree opens one way, `CascadeSide`, chosen
  from its widest chain.
- With `createOnDrop` on, the wire stays drawn while the Create menu is up
  and goes when the menu closes.
- The minimap's gear and fold buttons sit against the panel's edge.

## 0.1.0

First release: a node graph editor for Flutter, the successor to
[fl_nodes](https://github.com/WilliamKarolDiCioccio/fl_nodes), rebuilt so
that a node body is an ordinary widget — text fields, sliders and forms all
work inside one.

- Immutable `NodeGraph` of `GraphNode`s, `NodePort`s and `NodeConnection`s,
  edited through a `NodeEditorController` with `history`, `selection`,
  `camera`, `layout`, `clipboard`, `project` and `runner` subsystems.
- Ports declare a `PortKind` (`data` or `control`) and an optional
  `dataType`; the default validator refuses to wire across either.
- Prototypes as reduction rules: given a node's fields and wiring, they
  return the ports, fields and height it should have. Static and dynamic
  port families; foreign ports left alone.
- Execution: `controller.runner.run()` walks control flow depth-first and
  pulls data inputs on demand, memoised per run; `NodeExecutionContext.enteredVia`
  names the control input the flow arrived on; a `GraphRun` carries the
  trace, values, diagnostics and failure.
- Pan, zoom, marquee select, node drag, port-to-port wiring, connection
  captions, keyboard shortcuts and undo. Context menus on node, port, wire
  and canvas, built from `MenuAnchor` with entries as data and a build hook.
  Optional drop-to-create.
- Comments: free-standing notes sharing the nodes' paint order, typed edits
  folding into one undo step per run.
- Groups: named frames behind a set of nodes (`Ctrl+G`), moved by their
  handle, floating to the front with their members when selected.
- Minimap: `NodeEditor.minimap` (`MinimapConfig?`, null) draws a movable,
  foldable readout over the canvas; `MinimapController` holds its size,
  `maxScale` (0.2) and `idleOpacity` (0.28) for a host to persist.
- Rendering: connections, ports, grid and overlays painted rather than
  built; per-node widget slots, an incremental connection layout, a spatial
  hash for hit testing and culling, a fragment-shader grid with a CPU
  fallback.
- `NodeGraphCodec` reads and writes a versioned JSON document with
  pluggable payload codecs and map-to-map migrations; a `project` subsystem
  keeps I/O behind a host-supplied source and sink.
