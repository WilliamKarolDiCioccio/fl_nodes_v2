# fl_nodes_v2

A node graph editor for Flutter. The package supplies the canvas — geometry,
wiring, selection, navigation, undo, execution — and lets your app decide what
a node looks like.

It is the spiritual successor to
[fl_nodes](https://github.com/WilliamKarolDiCioccio/fl_nodes): the same ideas,
rebuilt so that **a node body is an ordinary widget**. fl_nodes isolated
rebuilds with a custom multi-child render object, which bought node count at the
price of the node itself — a render object painting its own content cannot host
a text field, a platform view, or anything needing the framework's own
machinery. Here the isolation is done at the element level instead, so nodes
stay widgets and text fields, sliders, dropdowns and forms all work inside one.

Everything *around* the nodes — connections, port handles, the grid, the
selection overlays — is painted.

```sh
cd example && flutter run
```

## Install

```yaml
dependencies:
  fl_nodes_v2:
    git:
      url: https://github.com/WilliamKarolDiCioccio/fl_nodes_v2.git
```

```dart
import 'package:fl_nodes_v2/fl_nodes_v2.dart';
```

## Quickstart

Two nodes and a wire between them:

```dart
final controller = NodeEditorController(
  graph: NodeGraph(
    nodes: <GraphNode>[
      GraphNode(
        id: 'start',
        type: 'scene',
        position: const Offset(0, 0),
        data: <String, Object?>{'title': 'Opening'},
        ports: const <NodePort>[NodePort.output(id: 'next')],
      ),
      GraphNode(
        id: 'end',
        type: 'scene',
        position: const Offset(320, 40),
        ports: const <NodePort>[NodePort.input(id: 'in')],
      ),
    ],
    connections: const <NodeConnection>[
      NodeConnection(
        id: 'c1',
        from: PortRef('start', 'next'),
        to: PortRef('end', 'in'),
      ),
    ],
  ),
);

NodeEditor(
  controller: controller,
  theme: NodeEditorTheme.dark(),
  nodeBuilder: (context, node, state) => MyCard(node: node, state: state),
);
```

`nodeBuilder` is the extension point. It receives the node and a
`NodeRenderState` (`isSelected`, `isHovered`, `isDragging`,
`isConnectionTarget`) and returns any widget.

> **One rule worth knowing up front.** Do not wrap `NodeEditor` in a
> `ListenableBuilder` on its own controller. It already listens for itself, and
> rebuilding it hands it a fresh `nodeBuilder` closure every frame — which is
> the one input it cannot compare, so every node rebuilds. Wrap the parts that
> read controller state, not the editor.

## Concepts

### The model

Four value types, all immutable:

| | |
| --- | --- |
| `NodeGraph` | nodes and connections, edited copy-on-write |
| `GraphNode` | `id`, `type`, `position`, `width`, optional `height`, `ports`, and a free-form `data` map |
| `NodePort` | `id`, direction, `kind`, optional `dataType`, `label`, `anchor`, `maxConnections` |
| `NodeConnection` | a `PortRef` at each end, plus `type`, `label`, `color`, `data` |

`type` and `data` are yours. The package never interprets them; your
`nodeBuilder` switches on `type` and reads `data`.

### The controller

`NodeEditorController` owns the graph and every edit to it — `addNode`,
`updateNode`, `removeNodes`, `moveNodes`, `applyLayout`, `connect`,
`removeConnections`, `replaceGraph`, `nextId`. Everything else is a named
subsystem:

| | |
| --- | --- |
| `controller.history` | `undo`, `redo`, `canUndo`, transactions |
| `controller.selection` | `nodeIds`, `connectionIds`, `selectNodes`, `selectAll`, `deleteSelected` |
| `controller.camera` | `viewport`, `panBy`, `zoomBy`, `setScale`, `fitToContent`, `centerOn`, `centerOnNode` |
| `controller.layout` | `sizeOf`, `nodeAt`, `portAt`, `nodesIn`, `boundsOf`, `onMeasured` |
| `controller.clipboard` | `copy`, `cut`, `paste`, `duplicate` |
| `controller.project` | the open document: `save`, `load`, `open`, `reset`, `isDirty` |
| `controller.runner` | `run`, `cancel`, `stateOf` |

There is no compatibility layer: `controller.undo()` does not exist, only
`controller.history.undo()`.

### Node bodies

Node bodies are ordinary widgets, so text fields, checkboxes, sliders, images,
scrollables and popup menus all work inside a node — the demo's **Form** node is
built from exactly those. Interactive children sit deeper in the tree than the
node's drag recogniser and win the gesture arena against it, and scroll events
go through `GestureBinding.pointerSignalResolver`, so a list inside a node
scrolls instead of zooming the canvas.

Two things when wiring a form into the graph:

- **Canvas shortcuts are gated on focus.** They fire only while the canvas
  itself holds primary focus, never while something inside a node does — a text
  field leaves `Backspace` unhandled once it has nothing left to delete, and
  that event would otherwise bubble up and delete the node being edited.
- **Wrap continuous edits in a transaction.** Write on every keystroke so the
  canvas stays in sync, but bracket the session with `beginTransaction()` /
  `commitTransaction()` so it collapses into one undo step rather than one per
  character. `example/lib/form_node_body.dart` does this on focus change for the
  text field and on `onChangeStart`/`onChangeEnd` for the slider.

A body holding its own controllers should be a `StatefulWidget` and adopt model
changes in `didUpdateWidget` when it is not focused, so undo and redo are
reflected without stealing the caret.

### Sizing

Nodes declare a `width`. `height` is optional:

- **Declared** — the node is exactly that tall. Use this when port positions
  must line up with rows inside the card, since the row offsets are then known
  up front.
- **Omitted** — the node sizes to its content and the measured height is
  reported back, so connection endpoints follow. Measurement costs one extra
  frame; `controller.layout.hasUnmeasuredNodes` reports when extents are
  provisional.

### Ports

Ports sit on a node edge, spread evenly along their side by default. `anchor`
pins one to an exact spot instead, normalised to the node's bounds — which is
how the demo gives each branch of a condition its own output:

```dart
NodePort.output(id: 'branch_0', anchor: Offset(1, rowCentre / cardHeight))
```

Handles are **painted, not built**, and `NodeEditorLayout.portAt` answers which
one a point is over. Drawing and hit testing read the same geometry, so a handle
and the curve landing on it cannot disagree. Below
`NodeEditorTheme.portMinScale` (0.25) handles are neither drawn nor hittable —
one rule for both, because a dot too small to see is also too small to aim at.

The trade is that a host cannot supply its own handle widget; style them through
the theme and `NodePort.color`.

### Connection rules

By default the editor refuses same-direction pairs, self-connections,
duplicates, anything over a port's `maxConnections`, and any pair whose kinds or
types disagree. `connectionValidator` adds domain rules:

```dart
NodeEditorController(
  connectionValidator: (graph, from, to) =>
      NodeEditorController.portsCompatible(fromPort, toPort) && myRule(...),
);
```

A custom validator *replaces* the default, so call `portsCompatible` yourself if
you still want the kind and type checks.

**Kinds and types.** A port is `PortKind.data` or `PortKind.control`. Data
carries a value; control carries the flow of execution. They never join.

```dart
NodePort.output(id: 'then', kind: PortKind.control),
NodePort.input(id: 'name', dataType: 'string'),
NodePort.input(id: 'anything'),   // untyped: a wildcard
```

`dataType` is a tag you choose, not a Dart `Type` — ports are serialised and
`Type.toString()` is not stable under obfuscation. A null on either end matches
anything, so adding a type to one side of an existing graph never invalidates a
wire on its own. It is a **wiring constraint only**: nothing compares a runtime
value against it, because a string cannot.

Everything defaults to `PortKind.data` with no type, so a graph that mentions
neither behaves as though they did not exist.

**Direction** is shown by markers spaced along the curve rather than by a head
at the receiving port, each taking the curve's own slope.
`NodeEditorTheme.connectionArrowSpacing` (140) is the gap aimed for, rounded to
fit and clamped to `1..connectionArrowMaxCount` (4).

### Prototypes

A prototype is not a template stamped out once — it is a **reduction rule**.
Given what a node's fields say and how it is wired *right now*, it returns the
ports, fields and height that node should have, and the controller rewrites the
node to match. Ports become derived state rather than something the document
authors by hand.

That is what lets ports appear on demand: one input per placeholder in a format
string, one more exit each time the last free one is wired.

```dart
final printNode = NodePrototype(
  type: 'print',
  label: 'Print',                    // also its opt-in to the Create menu
  icon: Icons.print,
  category: 'Debug',
  description: 'Writes its formatted text to the log.',
  fields: const <FieldFamily>[
    StaticFieldFamily(
      id: 'text',
      fields: <NodeField>[NodeField(key: 'format', defaultValue: 'Hello, {0}!')],
    ),
  ],
  ports: <PortFamily>[
    DynamicPortFamily(
      id: 'args',
      build: (context) => <NodePort>[
        for (final slot in slotsIn(context.fieldOr<String>('format', '')))
          NodePort.input(id: 'arg_$slot', label: '{$slot}'),
      ],
    ),
  ],
);

NodeEditorController(prototypes: NodePrototypeRegistry(<NodePrototype>[printNode]));
```

Prototypes are optional. Without a registry the controller behaves exactly as it
would otherwise, and a node whose `type` no prototype claims is never touched.

**Families** are the unit of ownership, so a node can have a fixed input and a
variadic output with only the second re-deriving:

| | |
| --- | --- |
| `StaticPortFamily` | A constant list, still owned — re-materialised every pass, so renaming a label in the prototype reaches nodes that already exist. |
| `DynamicPortFamily` | Rebuilt from the node's fields and links on every pass. |
| *foreign* | A port carrying no `family`. Yours; never rewritten or removed. |

If a generated port has the same id as a hand-authored one, the generated port
adopts it — that is how you point a prototype at a document whose ports were
written by hand.

A builder must **settle**: given its own output it must return the same thing
again. Resolution runs passes until the node stops changing, bounded by
`maxPasses`.

`label`, `icon`, `category`, `description` and `defaultWidth` are presentation
only and take no part in resolution — they are what the editor's Create menu
lists and its Description item shows.

### Execution

A prototype's `onExecute` is what its node *does*; `controller.runner` walks the
graph and calls them.

```dart
NodePrototype(
  type: 'greet',
  onExecute: (context) async {
    final name = context.input<String>('name') ?? context.fieldOr('name', '');
    context.emit('greeting', 'Hello, $name');
    context.flow('then');
  },
);

final run = await controller.runner.run();
if (!run.succeeded) report(run.error, run.failedNodeId);
```

**Running never touches the document.** No node moves, the revision does not
change, nothing lands in undo and the project does not become dirty. Values live
in the run, keyed by the output port that produced them — which is also why a
run is immune to edits made while it is in flight: it works from a snapshot.

`run()` throws `StateError` if one is already going; `cancel()` stops it. An
exception from an executor is **not** rethrown — it comes back as `run.error`
with `run.failedNodeId`, because a result you can inspect beats an error thrown
out of an async subsystem.

**Control flow.** Execution starts at every node with a control output and
nothing wired into its control input, in node-id order — or at the ids you pass
as `from`. A node with no executor hands the flow on through its single control
output; with more than one it stops and says so rather than guessing which
branch an if/else meant. Branches run **depth first**.

Control flow is a **pulse**: two branches converging on a node run it twice.
There is no implicit join, because a barrier waiting for every incoming edge
deadlocks on the arm a condition never fires. A node that wants to wait counts
tokens in `context.state`, which persists across that node's turns within one
run — the same place a loop keeps its counter. `maxSteps` bounds the run.

**Data flow.** A node declaring no control ports at all is a **pure data node**:
evaluated when something asks for its output, not when the flow arrives.

```dart
context.input<String>('name')   // null when nothing is wired
context.hasInput('name')        // null is a legal value; absence is not
context.inputs('name')          // every wire, in connection id order
```

Its result is reused until one of its own inputs is rewritten, so a value
recomputed inside a loop is recomputed and a constant is not. A node that is not
a function of its inputs — `random()`, `now()` — sets `pure: false`.

`GraphRun` carries `trace`, `runCounts`, per-node `states`, `values` keyed by
`PortRef`, and `diagnostics` — the things that would otherwise be silent: a node
that ran twice, a data input with several wires, a read from a producer that had
not run, a graph with no entry point.

### Comments

A comment is a note the app user writes on the canvas: a text field in a grey
slab, with a ring of padding wide enough to grab.

```dart
final id = controller.addComment(
  position: scenePosition,
  text: 'this branch is deliberate',
);
```

It is an ordinary `GraphNode` of a reserved type, not a model of its own. That
is the whole design — paint order, selection, dragging, the marquee, cut and
paste, undo and the document format are things a node already has and a note
needs unchanged. So a note floats above the nodes when you click it, sweeps
into a marquee, copies, pastes and saves without a single case for it anywhere.

The editor draws them itself and never hands one to your `nodeBuilder`, so you
neither have to know the type exists nor can be surprised by one arriving. They
are deliberately unthemed and look the same in a light app and a dark one: a
note is the user's own annotation, not part of the graph's visual language.

`NodeComment` is the seam. `NodeComment.isComment(node)` and
`NodeComment.textOf(node)` read one; `graph.comments` and `graph.contentNodes`
partition `graph.nodes` for the places that care — running the graph, counting
it, exporting it. Notes carry no ports, so nothing can be wired to one and the
runner leaves them alone.

Typing folds into one undo step per run. `controller.setCommentText` records
only the first change of a run; `endCommentEdit` closes it, and so does any
other edit, so `Ctrl+Z` can never step back past something that happened while
the caret was elsewhere.

### Groups

A group is a named frame drawn behind a set of nodes. Select some and press
`Ctrl+G`.

```dart
controller.selection.selectNodes(<String>['a', 'b']);
final id = controller.groupSelection();
```

**A group owns no geometry.** Its rectangle is the bounding box of whatever it
holds plus `NodeGroup.padding`, recomputed as those nodes move — which is why
this is its own model rather than a node of a reserved type the way a comment
is. Membership is explicit, not geometric: dragging a node over a frame does
not put it in.

The frame paints immediately below the lowest of its own members, and no
lower — under the nodes it holds without sinking beneath whatever else is
stacked under them. **It takes no pointer events at all.** The space inside a
frame is still canvas: clicks there sweep a marquee, and clicking a node does
what it always did. Everything a group can be asked to do goes through its
handle, in the frame's top-left.

| Action | |
| --- | --- |
| `Ctrl+G` on nodes | Frame them |
| `Ctrl+G` on a group plus ungrouped nodes | Widen that frame |
| Drag the handle | Move every member, in one undo step — the frame and its contents come to the front |
| Click the handle | Select the group — not its nodes |
| Double-click the handle | Rename |
| Handle dropdown | Recolour from `NodeGroup.palette`, or back to neutral |
| Right-click the handle | Cut, Copy, Delete with contents, Disband, Rename, Colour |
| `Del` on a selected group | Delete the frame **and its contents** |

`groupSelection()` returns null rather than guessing when the selection cannot
be framed: nothing selected, more than one group in it, or a node that already
belongs to a different group. Moving a node between groups is deliberately not
offered — disband the old frame first, or one keystroke would rewrite a group
the user was not looking at.

`selection.groupIds` is separate from `selection.nodeIds`, and
`selection.nodeIdsWithGroups` is what "act on the selection" means once a frame
can be in it.

### Minimap

An optional panel over the canvas showing the whole document small, with
everything outside the current view washed grey. Off by default:

```dart
NodeEditor(
  controller: controller,
  nodeBuilder: buildCard,
  minimap: const MinimapConfig(),
)
```

**It is a readout and never moves the camera.** The drag belongs to the panel
instead, so it can be pushed off whatever you are working on — a minimap you
cannot move is a minimap sitting on top of your graph. That also makes it
cheap: it never touches the controller, so nothing it does rebuilds a node.

| Action | |
| --- | --- |
| Drag the action bar | Move the panel |
| Drag the corner grip | Resize it |
| Gear | Zoom cap, size, what is drawn, idle opacity |
| ✕ | Fold to the bar; the same button unfolds it |

The map fits the whole document, capped by `MinimapController.maxScale` (0.2)
so a three-node graph does not render as three enormous slabs. The cap only
ever binds downward, so it can never push content off the map.

Nodes take their group's colour, notes the note grey and selected nodes the
theme's selection colour. The package has no per-node colour by design, so a
host that colours by its own node vocabulary supplies one:

```dart
MinimapConfig(
  nodeColor: (node) => switch (node.type) {
    'trigger' => const Color(0xFF5BC48A),
    'output' => const Color(0xFFB57BD8),
    _ => null, // fall back to the group, or to the neutral
  },
)
```

The panel's placement, size, folded state and settings live on a
`MinimapController`. The editor makes one when you supply none; own one to
persist where the panel was left.

### Context menus

Right-click a node, a port, a wire or the canvas. Menus are built from
`MenuAnchor`, so they inherit your app's `MenuTheme`.

| Target | Entries |
| --- | --- |
| Node | Cut, Copy, Delete, Group, Description |
| Port | Cut links |
| Wire | Go to source, Go to destination, Delete |
| Group | Cut, Copy, Delete with contents, Disband, Rename, Colour ▸ |
| Canvas | Center view, Reset zoom, Paste, Create ▸, Add comment, Project ▸ |

Create ▸ lists every prototype that declares a `label`, grouped by `category`.
Description shows a prototype's `description`, read-only. Open and Save are
disabled until `controller.project` has a `source` and a `sink`.

Entries are data, so a host filters the defaults rather than rebuilding them:

```dart
NodeEditor(
  contextMenus: NodeEditorMenus(
    createOnDrop: true,
    build: (request, defaults) => <NodeMenuEntry>[
      ...defaults,
      if (request.target case NodeMenuNodeTarget(:final node))
        NodeMenuEntry(label: 'Run from here', onSelected: () => run(node.id)),
    ],
  ),
);
```

`contextMenus: null` turns them off. Supplying `onNodeSecondaryTap`,
`onPortSecondaryTap`, `onConnectionSecondaryTap` or `onCanvasSecondaryTap` takes
that one target over, so a host with its own menu keeps it and does not get two.

`createOnDrop` (off by default) makes a wire dropped on empty canvas offer
Create ▸ at that point and wire up what it makes, in one undo step. It replaces
`onConnectionDropped` rather than joining it.

### Undo and the clipboard

Every mutation records a snapshot; multi-frame gestures wrap themselves in a
transaction so a drag is one step.

```dart
controller.history.beginTransaction();
// ...many moveNodes calls...
controller.history.commitTransaction();
```

`copy` takes the selected nodes and the wires **between** them — a connection to
a node left behind is not part of what was copied, and reattaching it on paste
would silently rewire the document. `paste` gives fresh ids, runs one resolution
pass, lands as one undo step, and returns what actually survived:

```dart
controller.clipboard.copy();
final pasted = controller.clipboard.paste();   // the ids that survived
controller.clipboard.duplicate();              // buffer untouched
```

Give the controller a `NodeGraphCodec` and every copy is *also* written to the
system clipboard as JSON, which is what carries a selection between windows:

```dart
NodeEditorController(prototypes: prototypes, codec: NodeGraphCodec(prototypes: prototypes));
await controller.clipboard.pasteFromSystem();  // falls back to the buffer
```

Without a codec the package never touches `flutter/services`.

### Serialisation

The package does no I/O. `NodeGraphCodec` converts a `GraphDocument` to and from
a `Map<String, Object?>` made only of JSON values.

```dart
const codec = NodeGraphCodec();
final json = codec.encode(GraphDocument(
  graph: controller.graph,
  viewport: controller.camera.viewport,
));
final document = codec.decode(json);   // throws here, or not at all
```

**Decode never touches a controller.** It returns a document or throws, so a
malformed file cannot leave an editor blank. Failures carry a path —
`nodes[3].ports[1].anchor`, not `type 'String' is not a subtype of type 'num'`.

For an app where the editor *is* the document, `controller.project` holds the
codec, the metadata and the two callbacks that decide where documents live:

```dart
controller.project
  ..meta = const <String, Object?>{'title': 'Lead routing'}
  ..appVersion = 'my-app/1.0.0'
  ..sink = (json) => writeFile(json)        // Future<bool>
  ..source = () => readFile();              // Future<Map<String, Object?>?>

await controller.project.save();
final document = await controller.project.load();
```

`load` decodes before it replaces anything, so an unreadable document leaves the
open one on screen. `save` returns what the sink reported: false is a save the
user backed out of, not a failure. `isDirty` compares graph identity, so undoing
back to the saved state reports clean again.

Non-JSON values need a `PayloadCodec`, registered with a tag so both directions
dispatch on the same recorded string. Documents carry an integer `version`; one
newer than the build is refused rather than parsed hopefully, and older ones are
lifted by pure `Map`-to-`Map` migrations.

A document carries a **second** version, and it is the host's:

```dart
const codec = NodeGraphCodec(
  schemaVersion: 3,
  schemaMigrations: <int, GraphDocumentMigration>{
    1: (document) => …,   // version 1 of *your* data, as version 2
    2: (document) => …,
  },
);
```

`version` governs the envelope — nodes, connections, groups, ports, the shape
this package owns. `schema` governs what *you* mean by a node's `type` and by
the keys in its `data`, which the package carries and never interprets. So a
field you rename or two you fold into one is a `schema` bump, and this package
cutting a format version does not oblige you to write a migration for it. Both
gates run on the way in, the format's first; a missing `schema` reads as 1, and
leaving `schemaVersion` null means a `schema` key is carried through untouched
rather than gated.

### Theming

`NodeEditorTheme.dark()` / `.light()`, or build one field by field. It covers
colours, the grid, connection width and curvature, port radius and
`portMinScale`, selection and marquee styling, scale limits, `snapToGrid`, hit
tolerances and the direction markers. Omit `theme` and the editor picks dark or
light from the ambient `Theme` brightness.

## Interaction

| Gesture | Result |
| --- | --- |
| Drag canvas | Sweep a selection rectangle, updating live |
| Shift / ctrl + drag canvas | Sweep, adding to the current selection |
| Middle-drag, space + drag, touch drag, trackpad | Pan |
| Scroll / pinch | Zoom about the pointer |
| Drag node | Move it — selecting it first is not required |
| Drag a selected node | Move the whole selection |
| Drag port → port | Create a connection |
| Drag port → node body | Connect to that node's first compatible port |
| Drag port → empty canvas | `onConnectionDropped`, or Create ▸ with `createOnDrop` |
| Click connection | Select it |
| Drag a comment's padding | Move it — the text field takes any press on itself |
| Drag a group's handle | Move every node in it |
| `Ctrl+G` | Frame the selection, or widen the frame in it |
| Right-click anything | Its context menu |
| `Del`, `Ctrl+Z`/`Ctrl+Shift+Z`, `Ctrl+A`, `Esc`, arrows | Delete, undo/redo, select all, cancel, nudge |
| `Ctrl+C`/`Ctrl+X`/`Ctrl+V`/`Ctrl+D` | Copy, cut, paste, duplicate |

`canvasDragBehavior: CanvasDragBehavior.pan` swaps the first two rows — canvas
drag pans and shift opts into the rubber band. Navigation is never taken over
by selection either way: a touch drag always pans, so the rubber band is a
pointer-device affordance only.

A click selects, a drag moves. Pressing a node and dragging moves it straight
away, selecting it on the way. The secondary button never drives a drag — it
opens menus and nothing else.

## Layers

Each layer is usable on its own, so graph logic and layout can be unit tested
without pumping a widget.

| Layer | Types | Depends on Flutter? |
| --- | --- | --- |
| Model | `NodeGraph`, `GraphNode`, `NodePort`, `NodeConnection`, `NodeGroup`, `PortRef` | geometry only |
| Geometry | `ViewportTransform`, `NodeGeometry`, `ConnectionPath`, `ConnectionRouter`, `MinimapProjection` | geometry only |
| Prototype | `NodePrototype`, `PortFamily`, `FieldFamily`, `NodePrototypeRegistry` | geometry only |
| Serialisation | `NodeGraphCodec`, `GraphDocument`, `PayloadCodecs` | geometry only |
| Controller | `NodeEditorController` and its subsystems, `SpatialHashGrid`, `MinimapController` | `ChangeNotifier` |
| View | `NodeEditor`, `NodeView`, `ConnectionLayout`, painters, `NodeEditorTheme`, `MinimapConfig` | yes |

## Example

`example/` is a workflow editor covering every feature: seven node types, a form
node built from real Flutter inputs, derived ports, link captions, an inspector
panel, comments, groups, the minimap, JSON save and load, execution, and stress
graphs up to 5000 nodes.

```sh
cd example && flutter run
```

## Not included yet

- Node resizing handles and grouping. Comments size themselves to their text;
  nothing on the canvas can be resized by hand.
- Resolution cannot change a node's `position`, `width` or `draggable`.
  `NodePrototype.defaultWidth` seeds `instantiate` but is not enforced after.

## License

MIT. See [LICENSE](LICENSE).
