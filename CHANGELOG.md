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
