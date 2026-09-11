## Unreleased

### The host's own format version

`NodeGraphCodec.schemaVersion` (`int?`, null) and `NodeGraphCodec.schemaMigrations`
(`Map<int, GraphDocumentMigration>`, empty), stamped into a document as
`schema` and reported on `GraphDocument.schemaVersion`.

A document already carried `version`, and it governs the envelope: nodes,
connections, groups, ports — the shape this package owns. It could never govern
what a *host* means by a node's `type` or by the keys in its `data`, because
the package carries both and interprets neither. So a host that renamed a field
had no version to bump and no chain to hang a migration on: `upgrade` ran
`from` to `target` with `target` always `NodeGraphCodec.version`, which made a
host-supplied `migrations` chain unreachable rather than merely unused. The
predecessor had two axes and this is the second one back.

The two move on different clocks, which is the whole point of their being two.
Both gates run on the way in and the format's runs first — its migration
normalises the envelope the host's then walks — and `decode` refuses a
`schema` from the future the way it already refused a `version`, saying
*schema* rather than *format* so nobody goes looking on the wrong side of the
boundary. A missing `schema` reads as `legacySchemaVersion` (1): every document
written before a host declared an axis, which is all of them the first time it
does. Leaving `schemaVersion` null keeps the old behaviour exactly — a `schema`
key is then read, reported and written back untouched rather than gated, since
a build with no opinion about the host's data has no business refusing a
document over it.

`GraphDocumentMigrations.upgrade` gains `label` ('format') and `key`
('version') so a gap in either chain names its own axis. Pinned by the `schema
versions` group in `test/serialization_test.dart`, including that a document
out of range on both axes reports the format one.


### A submenu that slides instead of flipping

`NodeSubmenuButton`, used by `buildMenuChildren` for every `NodeMenuEntry`
with children in place of Material's `SubmenuButton`. Material lays a
submenu out with the delegate a menu bar uses: a panel that would run off
the bottom of the window is moved to end at the *top* of its row whenever it
fits there. For a cascade opened at a click point that leaves the panel
entirely above the row that opened it, and the pointer's path up to it
crosses the sibling rows — each of which takes focus on hover and closes the
open child. Near the bottom of the window the three-level Create menu was
unreachable by mouse.

The row is still a `MenuItemButton`, the linkage is `RawMenuAnchor`'s own —
a click elsewhere, Escape and choosing an entry still close the whole tree —
and the panel is dressed from `MenuTheme`. What is ours is the placement: to
the right of the row, top-aligned with it, slid up only as far as the window
demands and never off the row's band, flipped to the left only when there is
no room to the right. It opens on the *focus a hover brings* rather than on
the hover itself, because `MenuItemButton` reports the hover before it takes
focus and taking focus is what closes the previous row's children — which,
opened a moment earlier, would include this panel. Right on a row walks in,
left inside a panel walks out to the row, and a row nested in a panel hands
left up to that panel rather than walking focus sideways.
`submenu_placement_test.dart` pins the placement, the hover crossing, the
sibling close, the arrows and the two ways the tree closes.

### The wire stays while the Create menu is up

With `NodeEditorMenus.createOnDrop` on, the pending wire was cleared the
moment the Create menu opened at the drop point, so the person saw their wire
vanish and a menu appear — which read as the drop having failed, not as the
next step of it. `_handlePortDragEnd` now keeps the `PendingConnection` drawn,
frozen where it was let go, until the menu closes: chosen, dismissed or
clicked away. Only the drag ends at the drop — the source and target are
cleared — so a pointer over the menu cannot go on steering a wire nobody is
holding. `NodeEditorMenuHostState.open` returns whether a menu actually
opened, which is the cue. `drop_to_create_test.dart` pins both the holding and
the letting go.

### How wide a caption can get

`ConnectionLabel.maxWidth` (160) was private and is not any more. A host that
arranges its own graph cannot get the number any other way and needs it: a
caption is drawn at the midpoint of a curve, so the gap a layout leaves between
two ranks has to be at least this wide or every caption lands on a node. It is
a hard cap — the text is one line and ellipsised — so a layout can be derived
from it rather than tuned by eye.

The same argument `applyLayout` and `onMeasured` already make: the algorithm
stays out of the package, and the measurements it cannot take for itself come
out.

### Pointing at part of a graph

`NodeEditorController.emphasis` (`NodeEditorEmphasis`, empty) — a **focus**: a
set of nodes and connections that stand clear while everything else is washed
under a scrim. It is what a host needs to answer a question *about* a graph —
every route between these two nodes, everything this value reaches — without
editing the graph to say so.

- `GraphEmphasis` (`nodes`, `connections`, `scrim`) — a value type. Membership
  lifts; the value tints. A null tint lifts a node without painting a halo
  behind it, and lifts a wire without overriding its colour.
- `emphasis.value = …` replaces the focus wholesale, `clear()` drops it, and an
  equal value is a **no-op** — a host that recomputes the same answer every
  tick costs no repaint.
- `emphasis.revision` is the O(1) invalidation key, exactly as
  `selection.revision` is, and `emphasis.lifted` is a cached snapshot so paint
  order and hover picking do not allocate.
- `NodeEditorTheme` gains `scrimColor` (null), `scrimOpacity` (0.62),
  `emphasisInset` (7) and `emphasisRadius` (`Radius.circular(14)`). A null
  `scrimColor` derives from `background`, so a focus dims *towards the canvas*
  in either brightness rather than towards black in one of them.

**`nodes` and `connections` are two maps rather than one**, and that is the
shape the first consumer actually needed: a run of flow that passes through a
node the host does not want to show is expressed by tinting the wires either
side of it and leaving the node out, so the coloured run reads as continuous
across a card that is still dimmed.

**It lives on the controller and not on the `NodeEditor` widget**, for a reason
that only shows up once it is wrong. `NodeEditorLayout.nodeAt` and
`nodesInPaintOrder` rank through one function, and a widget-level input could
have reordered what is *drawn* without reordering what a press *lands on* —
which is the drift the layout's own doc comment already warns about. Putting it
on the controller also means the editor's existing listener does the repaint,
so a host never has to rebuild `NodeEditor` to show a focus, which is the one
thing this package asks a host not to do.

**A focus wins outright over the selection.** While anything is lifted, the
selection is ignored for paint order: a selected node floating above the scrim
is precisely what the scrim promises will not happen, and a union of the two
would let one stray click undo the whole effect.

It is **not** in the document, **not** in the undo history, and **never
reaches** `guard` or `onEdit` — assigning a focus is not an edit, for the same
reason a selection is not one. It is pruned after every mutation *and* after
undo and redo, because a focus is not in the graph and nothing else would drop
a halo painted around a node that has gone.

Two details worth knowing before touching the rendering:

- **The lifted wires are redrawn above the scrim rather than recoloured in
  place.** `ConnectionsPainter` draws every curve below the whole node layer,
  so a forced colour applied there would be washed out by the scrim. The new
  `EmphasisPainter` sits inside the node layer's own stack, immediately below
  the first lifted card, and re-strokes them from `ConnectionLayout`'s cache —
  already warm, so nothing is computed twice. `arrowheadsPath` and
  `arrowheadSize` moved out of `ConnectionsPainter` so both painters draw the
  same triangle.
- **A handle under the scrim is neither drawn nor grabbable.** `PortsPainter`
  paints above the whole node layer, so a dimmed card would otherwise keep a
  row of bright dots floating over the wash; `NodeEditorLayout.portAt` skips
  the same nodes, because one condition has to gate drawing and hitting alike —
  the rule `portMinScale` already follows.

The halo is painted **behind** the card, which is what makes this a
package-level feature at all: a host's node widget is opaque and untouched,
`NodeRenderState` gains nothing, and `_NodeSlot`'s comparison is unchanged, so
none of the rebuild isolation is at risk. There is a test that showing a focus
builds no node body at all.

Connection captions are **not** redrawn above the scrim; they stay under it,
which is why the default scrim is 0.62 rather than opaque. A focus that erased
its surroundings would answer "which routes are these" by throwing away the
board they run across.

Pinned by `test/emphasis_test.dart`, including the two that state the rules
above: a selected-but-unlifted node does not rise, and `portAt` answers null
for a node under the scrim.

### Somewhere to hang an automatic layout

The package still ships no arrangement of its own and is not going to: which
picture a graph should make is a question about what the nodes *mean*, and only
the host knows that. What a host cannot get for itself is the two ends of the
job, and both are here now.

- `NodeEditorController.applyLayout` (`GraphLayout`, `recordHistory: true`) —
  hands an algorithm the graph and the measured size of every node, and places
  whatever it answers in **one** edit, so a re-layout is a single undo step and
  a single repaint rather than one per node. Nodes the layout does not name are
  left alone, so arranging a selection is just a smaller map. Returns whether
  anything moved — false when the layout named nobody, named only nodes already
  in place, or when `guard` refused.
- `NodeEditorLayout.onMeasured` (`VoidCallback?`, null) — fired the moment
  `hasUnmeasuredNodes` goes false.

**`applyLayout` ignores `draggable` where `moveNodes` honours it**, and that is
the point of it rather than an inconsistency: the flag says whether a *pointer*
may push a node about, which is a different question from whether an
arrangement may place one — and a read-only canvas, where nothing is draggable,
is exactly where an automatic layout is most wanted. `moveNodes` is still the
gesture path and still refuses.

`onMeasured` exists because `hasUnmeasuredNodes` was only half a sentence. It
already told a caller to wait; nothing told it the wait was over. The
controller's own notifications cannot say so — they fire for every edit and
every measurement, so a host watching them re-asks on each one and has to
remember the previous answer. This fires once, on the transition, which is
where a layout that depends on real extents wants to run. A graph whose nodes
all declare a height never has anything to wait for and never fires it.

Pinned by `test/graph_layout_test.dart`, including the two that state the
difference: an arrangement places a `draggable: false` node, and `moveNodes`
still refuses the same one.

### Telling the host what changed, and letting it say no

Two hooks on `NodeEditorController`, both null by default so nothing changes
for a host that ignores them:

- `guard` (`GraphEditGuard?`, null) — asked before every edit; returning false
  abandons it, leaving the graph untouched, no undo step recorded and `onEdit`
  unfired. Consulted at the very top of `_mutate`, before prototypes are
  resolved, so a refused edit costs nothing rather than resolving against a
  graph that is then thrown away.
- `onEdit` (`GraphEditListener?`, null) — told after every edit that landed.
  `ChangeNotifier` already says *that* the graph changed; this says **what**,
  which is the difference between a host diffing two graphs and reading one
  field.

Both take a `GraphEdit`: a `GraphEditKind` plus the node, connection and group
ids it touched. The kinds are deliberately coarse — `addNodes`, `updateNodes`,
`removeNodes`, `moveNodes`, `connect`, `disconnect`, `labelConnection`,
`group`, `comment`, `replace` — because a host wants to know whether something
*went away*, not to carry a case per controller method.

`guard` is **synchronous**, and that is the contract rather than a limitation:
an edit is a frame's work and the controller cannot hold a graph half-changed
while a dialog is open. A host that needs to ask a question refuses, asks, and
re-issues the edit once it has an answer. `graph_edit_test.dart` pins that
round trip.

**Undo and redo do not pass through either hook.** They restore a graph the
hooks already saw on the way in, and a host that had refused a delete would
otherwise be unable to redo one it had allowed — so `history.undo()` bypasses
`_mutate` entirely and the test says so. A host that must catch every way a
node can leave the graph listens as well as guarding.

`graph_edit_test.dart` covers all sixteen cases; the existing 400 tests are
unchanged.

## 0.1.0

First release. A node graph editor for Flutter, and the spiritual successor to
[fl_nodes](https://github.com/WilliamKarolDiCioccio/fl_nodes) — same ideas,
rebuilt around one change of approach.

fl_nodes isolated rebuilds with a `MultiChildRenderObject`. It worked, but it
fought the framework: native channel synchronisation broke, which made text
fields inside nodes impossible and put a ceiling on what a node body could be.
The same isolation turns out to be available one layer up, at the *element*
level — `Element.updateChild` short-circuits when handed the identical widget
instance, so a per-node widget slot skips the subtree without building it.
Node bodies stay ordinary widgets. Text fields, sliders, popup menus and forms
all work inside a node.

### The graph

- Immutable `NodeGraph` of `GraphNode`s, `NodePort`s and `NodeConnection`s,
  edited copy-on-write through a `NodeEditorController`.
- Ports declare a `PortKind` (`data` or `control`) and an optional `dataType`;
  the default validator refuses to wire across either.
- Subsystems on the controller, each a `part` of it: `history`, `selection`,
  `camera`, `layout`, `clipboard`, `project`, `runner`.

### Prototypes

A prototype is a reduction rule, not a template stamped out once. Given what a
node's fields say and how it is wired right now, it returns the ports, fields
and height that node should have, and resolution rewrites the node to match.

- Ports become derived state: one input per placeholder in a format string, one
  more exit each time the last free one is wired.
- Static and dynamic families, with foreign ports left alone so a prototype can
  be pointed at a document whose ports were authored by hand.
- Presentation lives here too — `label`, `icon`, `category`, `description`,
  `defaultWidth` — which is what the editor's own menus read.

### Execution

- `controller.runner.run()` walks control flow depth-first and pulls data
  inputs on demand, memoised per run against a monotonic stamp.
- Control flow is a pulse: two branches converging on a node run it twice.
- `NodeExecutionContext.enteredVia` (null) names the control input the flow
  arrived on, so a node with more than one can behave differently on each. Some
  cannot be written without it — a loop's `continue` and `break` are one node
  doing opposite things, and the runner previously pushed only the destination
  node id and dropped the port. Null means nothing flowed in: the node was a
  root of the run, or it was pulled because something wanted its value. Pinned
  by `runner_test.dart`'s "a node is told which control input the flow arrived
  on" and "a root and a pulled node arrived through nothing".
- Runtime values live in a run-scoped map. Execution never touches the
  document, never bumps `revision` and never marks the project dirty.
- Returns a `GraphRun` — trace, values, diagnostics, failure — rather than
  throwing out of an async subsystem.

### Interaction

- Pan, zoom, marquee select, node drag, port-to-port wiring, connection
  captions, keyboard shortcuts and undo.
- Context menus on node, port, wire and canvas, built from `MenuAnchor` so they
  inherit the app's `MenuTheme`. Entries are data, and a build hook hands hosts
  the defaults to filter rather than a blank sheet.
- The secondary button never drives a drag — it opens menus and nothing else.
- A tap on the canvas takes focus, so selecting a wire and pressing Delete
  removes it. A tap is not a drag, so the scale recogniser never starts, and
  nothing else on that path claimed focus — which mattered more than a shortcut
  going unheard: the key event went to whatever the *host* had focused instead,
  and an editor embedded beside a file tree could answer Delete by deleting a
  file. Pinned by `test/canvas_focus_test.dart`.
- Optional drop-to-create: a wire let go on empty canvas offers the Create menu
  there and wires up what it makes, in one undo step.
- Comments, as free-standing notes sharing the nodes' paint order.
- Groups, as named frames behind a set of nodes, made with `Ctrl+G`.

### Comments

- `controller.addComment` leaves a note on the canvas: a real text field in a
  grey slab, with a ring of padding wide enough to grab it by.
- A note is an ordinary `GraphNode` of a reserved type rather than a model of
  its own, so paint order, selection, dragging, the marquee, cut and paste,
  undo and the document format all apply to it unchanged, with no cases for it
  anywhere. `NodeComment` reads one; `graph.comments` and `graph.contentNodes`
  partition `graph.nodes` for the places that care.
- The editor draws them itself and never hands one to the host's `nodeBuilder`.
  They are deliberately unthemed and identical in a light app and a dark one: a
  note is the app user's own annotation, not part of the graph's visual
  language.
- Typing folds into one undo step per run — `setCommentText` records only the
  first change, and `endCommentEdit` or any other edit closes the run, so undo
  can never step back past something that happened while the caret was
  elsewhere.

### Groups

- `Ctrl+G` frames the selected nodes; pressing it again with the frame and
  further nodes selected widens it. `controller.groupSelection` returns null
  rather than guessing when the selection cannot be framed — nothing selected,
  two frames in it, or a node that already belongs to a different one. Moving a
  node between groups is deliberately not offered: one keystroke would
  otherwise rewrite a group the user was not looking at.
- A `NodeGroup` owns no geometry. Its frame is its members' bounding box plus
  `NodeGroup.padding`, derived every time, which is why this is its own model
  where a comment is a node. Membership is explicit and exclusive; a group is
  pruned when its last member goes.
- The frame paints immediately below the lowest of its own members and no
  lower, and takes no pointer events: the space inside one is still canvas.
  Everything a group does goes through its handle — drag to move every member
  in one step, double-click to rename, a fixed palette in the dropdown, and a
  context menu carrying `Disband` beside `Delete with contents`.
- `selection.groupIds` sits beside `nodeIds` and `connectionIds`;
  `selection.nodeIdsWithGroups` is what acting on the selection means once a
  frame can be in it.
- **A selected group floats to the front, its members with it.** Paint order
  ranks a node through `nodeIdsWithGroups` rather than through the selection
  alone, so picking a frame up lifts everything in it over whatever it was
  under — and the frame follows, being bucketed beneath its lowest-ranked
  member. Without it a group dragged across other nodes vanishes underneath
  them and has to be moved somewhere else before you can reach what it is now
  covering. `NodeEditorLayout.nodeAt` ranks the same way, or what is drawn on
  top is not what a click lands on. Pinned by `group_test.dart`'s "selecting a
  group floats it and its members to the front" and "dragging the handle brings
  the group forward"; "an unselected group outranks nothing" is the guard that
  keeps a frame from sitting over the node you just clicked.

### Minimap

- **`NodeEditor.minimap`** (null) draws a minimap panel over the canvas, as the
  last child of the editor's own `Stack` rather than something a host positions
  itself: it has to paint above the node layer and take presses the marquee
  must never see, and a host solving that twice would solve it differently the
  second time. Off by default, unlike `contextMenus` — a right-click already
  means a menu, where a panel sitting over the canvas is a thing you ask for.
  `minimap: const MinimapConfig()` is the whole opt-in. Pinned by
  `minimap_test.dart`'s "there is no panel unless the host asks for one".
- **It is a readout and nothing else.** No click-to-jump and no drag-to-pan:
  the drag belongs to the *panel*, so it can be moved off whatever you are
  working on, and a panel you cannot move is a panel sitting on top of your
  graph. That is also what makes it free — it never calls
  `NodeEditorController`, so it can never bump `revision`, and dragging,
  resizing or folding it rebuilds no node body at all. Pinned by
  `rebuild_isolation_test.dart`'s "dragging the panel rebuilds no node bodies
  at all" and the three numbers of the isolation table re-run with it drawn.
- **`MinimapController`** (`size` 240x160, `maxScale` 0.2, `idleOpacity` 0.28)
  holds everything the app user can change, so a host can persist the placement
  into its own document; the editor makes one when given none and disposes only
  the one it made. The defaults live there rather than on `MinimapConfig`
  because two homes for one default is how a setting somebody restored gets
  silently overwritten by a config seed on the next launch.
- The map fits the whole document, **capped** by
  `MinimapController.maxScale` — without it three nodes fitted to the panel render as three enormous
  slabs and the map says nothing about shape. The cap can only ever bind
  *downward*: fitting takes the smaller of the two, so capping leaves slack on
  both axes and can never push content off the map. There is deliberately no
  matching floor, since a five-thousand-node graph legitimately needs 0.001.
  Pinned by "the zoom cap stops a small graph filling the map" and "the cap can
  never push content off the map".
- Everything outside the viewport is washed over with **four rects rather than
  a difference path**. The wash is translucent, so bands that overlap
  composite twice and show as a darker cross through the panel; `minimapShadeBands`
  slices the complement so it is covered exactly once, with no `Path` allocated
  on a repaint that happens on every scroll tick. Pinned by "the bands tile the
  map around the viewport and never overlap".
- A node takes its **group's** colour, a note the note grey, a selected node the
  theme's selection colour, and a host may override the lot with
  `MinimapConfig.nodeColor` — the package has no per-node colour by design, so
  that callback is the same seam `nodeBuilder` is. Selection outranks the host:
  otherwise a selected node is indistinguishable from an unselected one of the
  same type, on the one panel whose job is telling you where you are. Pinned by
  "the selection outranks the host, which outranks the group".
- The **close button minimises rather than closing**, folding the panel to its
  action bar; the same button restores it. With the minimap opt-in there is
  nothing else that would bring it back. Pinned by "the close button minimises
  rather than closing".
- `MinimapPainter` is the only painter in the package taking a `repaint`
  listenable, because it is the only one that can: every input it reads is on a
  `ChangeNotifier`, where the four canvas painters depend on editor state only
  a rebuild can deliver. Together with the panel's cached widget instance, a
  scroll tick repaints one layer and rebuilds no widget. Pinned by "the panel
  widget survives a pan".
- Scrolling, trackpad panning and hovering **over** the panel no longer reach
  the canvas underneath. An opaque `MouseRegion` stops siblings, not ancestors,
  and the editor's pointer plumbing is entirely ancestral — so the guard is on
  the editor rather than on the panel. Pinned by "scrolling over the panel does
  not zoom the canvas" and "hovering the panel does not pick a port beneath it".

### Rendering

- Connections, ports, grid and overlays are painted, not built. Level of detail
  is then a condition inside a painter rather than widgets coming and going, so
  crossing a threshold is a repaint instead of a rebuild storm.
- Per-node widget slots, an incremental connection layout keyed on endpoint
  identity, a spatial hash for hit testing and culling, and a fragment shader
  for the grid with a CPU fallback.

### Serialisation

- `NodeGraphCodec` reads and writes a versioned JSON document; only what cannot
  be derived is stored, so ports come back from the prototypes. A group naming
  a node the document does not carry loses that member rather than failing the
  load — a frame around four of five nodes is still a frame.
- Pluggable payload codecs, map-to-map migrations, and a `project` subsystem
  that keeps I/O behind a host-supplied source and sink.
