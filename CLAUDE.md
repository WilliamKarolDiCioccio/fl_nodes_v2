# Working on fl_nodes_v2

A node graph editor for Flutter. Standalone package; it will be consumed as a
git submodule by the apps that use it, `ripple_effect` first.

## Environment

**`flutter` and `dart` are not on PATH.** The toolchain is pinned in `.fvmrc`
to 3.41.9 and reached through FVM. Either works:

```sh
fvm flutter test
export PATH="$HOME/fvm/versions/3.41.9/bin:$PATH"
```

A bare `dart` is either missing or a different SDK than the package is pinned
to. `.pre-commit-config.yaml` goes through `fvm` for exactly this reason.

```sh
pre-commit install          # once per clone
pre-commit run --all-files  # sweep the tree
```

The hooks run format, analyze and both test suites — the package's and the
example's — on any Dart change. The example is not a sample; it is the only
thing that exercises the editor end to end.

## Verifying a change

```sh
cd packages/fl_nodes_v2
fvm flutter analyze && fvm flutter test
cd example && fvm flutter analyze && fvm flutter test
fvm flutter test benchmark/node_editor_benchmark.dart   # model, 5000 nodes
fvm flutter test benchmark/widget_benchmark.dart        # one frame of interaction
fvm flutter run -d linux                                # nothing replaces looking
```

`dart format` is checked, never applied by a hook — a hook that rewrites a file
under you turns one failed commit into two.

## House style

Tests: local factory closures at the top of `main()`, `addTearDown(controller.dispose)`,
`reason:` on anything non-obvious, no mocks, helpers declared before first use.
British spelling in prose ("serialisation", "normalises", "colour").

Comments earn their place by saying *why*, especially where the obvious
implementation is wrong. Doc comments on public API; a `///` on a field that
just restates its name is noise.

CHANGELOG entries state the change **and its rationale**, name the symbol in
backticks with its default in parentheses, carry measured numbers wherever a
performance claim is made, and close by naming the test that pins the new
behaviour.

## The one architectural decision

fl_nodes, the predecessor, isolated rebuilds with a `MultiChildRenderObject`.
It worked and it fought the framework: native channel synchronisation broke,
which made text fields inside nodes impossible.

The same isolation is available one layer up. **`Element.updateChild`
short-circuits when `child.widget == newWidget`** — identity, for a default
`Widget`. Hand back the *same widget instance* and the subtree is skipped
without building. That is the whole basis of `_NodeSlot` in
`lib/src/widgets/node_editor.dart`: one slot per on-screen node holding its
`NodeView` instance and its callbacks, handing the same instance back when its
inputs are unchanged.

**The callbacks must live in the slot.** A closure is the one input that cannot
be compared against the last one, so a closure rebuilt per frame makes every
node look different and gives the whole thing back.

### The trap a host falls into

**Do not rebuild `NodeEditor` on every controller notification.** It listens for
itself. Wrapping it in a `ListenableBuilder` on the same controller hands it a
fresh `nodeBuilder` every frame and every node rebuilds. The demo did exactly
this and it cost 59 ms a frame at 500 drawn nodes where it now costs 5. Wrap the
parts that read controller state, not the editor. `example/lib/main.dart` has a
comment at the seam saying so; leave it there.

`test/rebuild_isolation_test.dart` pins this. Watch it: the isolation is
invisible when it breaks — everything still works, just slowly.

| per frame, 36 nodes drawn | before | after |
| --- | --- | --- |
| Node bodies built while dragging one node | 26 | 1 |
| Node bodies built while panning | 36 | 0 |
| Node bodies built when the selection changes | 36 | 2 |

## Why things are painted rather than built

Connections, port handles, the grid and the overlays are painters. Beyond the
obvious cost, this is what makes **level of detail a paint-time condition**: an
`if` inside a painter rather than widgets coming and going. Doing LOD with
widgets means rebuilding every node on screen at the threshold, which stutters
exactly when the user is moving.

- **The grid is a fragment shader** (`lib/shaders/grid.frag`) — one `drawRect`,
  cost per pixel rather than per line. `GridPainter` falls back to lines if it
  fails to compile.
- **Port handles** were forty-odd render objects each. `PortsPainter` batches
  them by colour; `NodeEditorLayout.portAt` answers every press. Both read
  `NodeGeometry`, so what is drawn and what is picked cannot drift apart.
  `NodeEditorTheme.portMinScale` (0.25) gates drawing *and* hitting with one
  rule — an invisible dot that still starts a wire is worse than one plainly
  not there yet.
- **Curves batch by colour** into one `Path` per colour. Direction markers are
  sampled once when the curve is built (`ConnectionGeometry.arrows`), never
  measured per frame.

## Caches, and what they key on

`ConnectionLayout` builds bezier paths once and keys on the controller's
`revision` — which moves for edits but not for viewport changes, so panning and
zooming invalidate nothing.

A drag moves the revision on every pointer event, so that alone is not enough.
Each curve also remembers its two endpoints and keeps its path when they have
not moved. **Captions are re-derived every pass regardless**: a caption comes
from a port's *label*, which lives on a node and changes without anything
moving. That bug was caught by a test showing `Expected: 'Out 7' Actual: 'Out 0'`.

`NodeEditorState._connectedPorts()` keys on the **connections map identity**,
not on `revision`. Keying on revision was a real bug: node moves bump revision,
so the memo missed on every drag frame (26.4 → 0.7 node bodies per frame). It
also reuses the previous `Set` instance for any node whose set is unchanged —
a fresh `Set` is never `identical`, and that alone rebuilt every node.

| | rebuild every frame | cached |
| --- | --- | --- |
| Connection geometry | 4055 us | 0.02 us |
| Hover pick | 2627 us | 0.5 us |
| One pass while dragging (4928 links) | 4368 us | 750 us, 2 curves rebuilt |

## Gestures

`_CanvasGesture` is `{ none, pan, marquee, port, blocked }`. **`blocked` needs
to exist**: neutral falls through to the pan branch, so a press that must not
become a drag cannot simply stay `none`.

Neither the canvas `ScaleGestureRecognizer` nor `NodeView`'s pan recogniser
filters by button — `GestureDetector` has no `allowedButtonsFilter`. Both are
gated on `_pointerButtons & kSecondaryButton` instead, following the existing
`kMiddleMouseButton` test. Before that, a right-press over a handle started a
real wire.

A port handle straddles its node's border, so **two different recognisers** see
the two halves of one dot. Every entry point re-checks `_portAt` first:
`_handleScaleStart`, `_handleNodeDragStart`, and the secondary-tap path.

Context menus anchor to a **zero-sized box at the click point**, never to the
canvas. `MenuAnchor` wraps its anchor in a `TapRegion` keyed to the menu and a
tap inside that region is not an outside tap — anchoring to the canvas made
every click count as "inside" and the menu could not be dismissed at all. A
point has no button to focus either, so the anchor focuses itself on open and
hands off to the first choosable entry; without that the arrow keys never reach
the menu and Escape reaches the canvas instead.

A wire dropped on empty canvas with `createOnDrop` on **stays drawn until the
Create menu closes**. Only the drag ends at the drop: `_pendingSource` and
`_pendingTarget` go, `_pending` stays, and `_handleMenuClosed` — the host's
`onClosed`, which also takes focus back — clears it however the menu went. A
wire that vanished as the menu appeared read as the drop having failed.

## Hooks a host can hang on

`guard` and `onEdit` on the controller, both null by default. `_mutate` is the
single funnel every edit goes through, so both live there and neither can be
bypassed by adding a method later — which is the reason the parameter is
positional and required rather than optional: a new mutator that forgets to say
what it is doing does not compile.

**`guard` is synchronous and refusing is silent.** The controller cannot hold a
graph half-changed while a dialog is open, so a host that needs to ask
something refuses, asks, and calls the mutator again. The editor has nothing to
add to a refusal — the host already knows it refused.

**Neither hook sees undo or redo.** `history.undo()` sets `_graph` directly and
calls `_afterJump`; it does not go through `_mutate`. That is correct rather
than an oversight: undo restores a graph the hooks already saw, and a host that
vetoed a delete would otherwise be unable to redo one it had allowed. It does
mean a host tracking whether a particular node still exists has to *listen* as
well as guard — `ripple_effect` does exactly that for the node a paused
campaign is checkpointed on.

The guard is consulted before prototypes are resolved. Resolving first would
mean a refused edit had already done the expensive half of the work against a
graph about to be discarded.

**`applyLayout` and `onMeasured` are the auto-layout seam, and the algorithm is
deliberately not here.** Which picture a graph should make is a question about
what the nodes mean, and this package does not know. What it can supply is the
two things a host cannot get for itself — the size each node is really drawn
at, and one edit that places the lot.

`applyLayout` **ignores `draggable` where `moveNodes` honours it.** That is the
whole reason it is a second method rather than a flag on the first: the flag
says whether a *pointer* may push a node, which is a different question from
whether an arrangement may place one, and a read-only canvas — where nothing is
draggable — is exactly where an automatic layout is most wanted. A flag threaded
through `moveNodes` would read at every call site as if it were a choice.

It goes through `_mutate` like everything else, which has one consequence worth
knowing before debugging it: **a host that freezes a canvas with
`guard = (_) => false` freezes its own arrangement too.** Arrange first and
freeze after, or make the guard read a field the host can lower for the length
of a rebuild. `applyLayout` returns false rather than pretending, which is what
makes that visible instead of mysterious.

`ConnectionLabel.maxWidth` is public for the same reason and is the third of
these: a caption sits at the midpoint of a curve and is capped at that width,
so the gap a layout leaves between ranks is *derivable* rather than tuned by
eye. A host guessing it draws captions over its own nodes.

`onMeasured` finishes the sentence `hasUnmeasuredNodes` starts. Knowing to wait
is no use without being told the wait is over, and `notifyListeners` cannot say
it — it fires for every edit and every measurement, so a host watching it
re-asks each time and has to remember the previous answer. It fires on the
transition, after the notification rather than before it: a host that arranges
from there mutates the graph, and doing that midway through announcing a
measurement would have listeners reading a graph that is about to move.

## Emphasis

`controller.emphasis` is a **focus**: a set of nodes and connections that stand
clear of a scrim washed over everything else. It is how a host answers a
question *about* the graph — every route between two nodes, everything one
value reaches — without editing the graph to say it.

**It is beside `selection`, and for the same three reasons.** No undo entry, no
serialisation, no trip through `_mutate`: it is where the user is looking
rather than something they authored. `guard` cannot refuse it, which is the
point — a read-only canvas is exactly where a focus is most wanted.

**Why it is on the controller and not on `NodeEditor`.** `layout.nodeAt` and
`layout.nodesInPaintOrder` rank through one function. A widget-level input
could reorder what is *painted* without reordering what a press *lands on*,
which is the drift the layout already warns about. The other half of it: the
editor listens to the controller already, so a host never has to rebuild
`NodeEditor` to show a focus — the one thing this package asks a host not to do,
and there is a test that a focus builds no node body.

**A focus wins outright over the selection** in `_raised`. Union was the
obvious implementation and is wrong: a selected node floating above the scrim
is exactly what the scrim promises will not happen, so one stray click would
undo the effect.

**Two maps, not one.** `nodes` and `connections` are independent because the
first consumer needed a run of flow that passes *through* a node it does not
want to show: tint the wires either side, leave the node out, and the coloured
run reads as continuous across a card that is still dimmed. Membership lifts,
the value tints, and a null value lifts without tinting.

Three things about the rendering, each already paid for:

- **The lifted wires are redrawn above the scrim, not recoloured in place.**
  `ConnectionsPainter` is layer 1 and the whole node layer is layer 3, so every
  wire is *under* a scrim painted inside that layer — a forced colour there
  would simply be washed out. `EmphasisPainter` sits in the node layer's own
  stack immediately below the first lifted card and re-strokes them from
  `ConnectionLayout`'s cache, which was built for the layer underneath and is
  already warm. `arrowheadsPath`/`arrowheadSize` are shared with
  `ConnectionsPainter` rather than copied.
- **The halo is painted behind the card**, which is what makes any of this
  possible at the package level: a host's node widget is opaque and untouched,
  so `NodeRenderState` and `_NodeSlot`'s comparison tuple both gain nothing.
  The theme carries `emphasisRadius` rather than reading a node radius, because
  the package has none — how round a card is belongs to the host.
- **A handle under the scrim is neither drawn nor grabbable.** `PortsPainter`
  paints above the whole node layer, so a dimmed card would otherwise keep a
  row of bright dots on top of the wash; `layout.portAt` skips the same nodes,
  because one condition gates drawing *and* hitting — the rule `portMinScale`
  already follows.

`emphasis._prune` runs after every mutation **and** in `_afterJump`. Undo and
redo do not pass through `_mutate`, and a focus is not in the document, so
nothing else would take a halo off a node that has gone.

Connection captions are deliberately **not** redrawn above the scrim, which is
why the default `scrimOpacity` is 0.62 rather than opaque. A focus that erased
its surroundings would answer "which routes are these" by throwing away the
board they run across.

## Comments

A comment is a `GraphNode` of a reserved type (`NodeComment.type`), not a model
of its own. That was the decision, and it is the one worth remembering: paint
order, selection, dragging, the marquee, the clipboard, undo and the codec are
all things a node already has and a note needs *unchanged*. A parallel entity
would have meant a second copy of each, kept in step by hand — and the request
was for notes that share the nodes' z-order, which is free this way and
fiddly the other.

What that costs, and where it is paid:

- `graph.nodes` holds notes too. `graph.comments` / `graph.contentNodes`
  partition it for callers that mean one or the other.
- The runner is safe *by accident and by design*: a note declares no ports, and
  a node with no control ports is `isPureData`, so it sits outside the flow and
  nothing pulls it.
- Prototype resolution skips it — `resolve` does `if (prototype == null)
  continue`, and nothing may register that type.
- `_NodeSlot` swaps in the editor's own builder for a note, so the host's
  `nodeBuilder` never sees one. The builder is a field, not a tear-off read per
  build: the slot compares builders by identity.

The look is hardcoded in `comment_view.dart` and does not read the theme. That
is the ask, not an oversight — a note that picked up the accent colour would
read as one more kind of node. The colours are opaque for a reason: a
translucent slab composites to near-black on the dark canvas and near-white on
the light one, and no single ink colour is readable on both.

**Typing coalesces into one undo step per run**, or `Ctrl+Z` is useless for
anything else. `setCommentText` records only when `_commentBeingTyped` is not
already this note; `_mutate` clears that flag whenever any edit lands and
`_afterJump` clears it on undo and redo, so a run can never swallow an edit
that happened while the caret was elsewhere. `endCommentEdit` is the explicit
close, called when the field loses focus and from `dispose` — a plain field
write, which is what makes it safe from `dispose`, where a commit that
notified would rebuild widgets mid-layout.

The ring of padding is the only drag surface, and that is load-bearing rather
than cosmetic: the text field's recognisers are deeper in the hit-test path and
take any press that lands on them. `comment_test.dart` pins both halves — the
padding drags, the field does not.

## Groups

A group is **not** a node of a reserved type, and the contrast with comments is
the thing to remember. A comment stores a position; a group *derives* one — its
frame is its members' bounding box plus `NodeGroup.padding`, recomputed on
read. Giving it a stored rect would mean rewriting the model on every frame of
every drag, and resolution is explicitly not allowed to move nodes anyway.

- Membership is exclusive and `NodeGraph.putGroup` enforces it rather than
  trusting the caller: two frames claiming one node has no sensible rendering.
- `NodeGraph` prunes membership on every `removeNodes`, and drops a group that
  empties out. The constructor prunes too — an authored or decoded group naming
  a node that is not there would leave a frame stretched around nothing.
- `layout.boundsOfGroup` reads the **spatial index**, not the nodes, so the
  frame cannot disagree with the rects picking already uses.
- `groupsIn` is asked separately from `nodesIn`: two members either side of the
  screen leave a frame crossing a viewport neither node is in.

Paint order is in `_buildNodeLayer`: node ids are ranked by their index in the
culled list, each frame is bucketed under the lowest rank among its members,
and buckets are emitted before the node at that index. A frame with no drawn
member falls to bucket 0 — nothing of its own is on screen to be above.

**A selected group floats, and so does everything in it.** `layout` ranks a
node by `selection.nodeIdsWithGroups` rather than by `containsNode`, so
selecting or dragging a frame lifts its members over whatever they were under —
and the frame follows them up for free, being bucketed beneath its
lowest-ranked member. Without that a group dragged onto other nodes disappears
under them and has to be moved somewhere else before you can click what it is
now covering. The expansion is asked for **once per sort** rather than inside
the comparator: with a group selected it allocates, and a comparator would
build it O(n log n) times. `nodeAt` ranks the same way, or what is drawn on top
is not what a click lands on.

**The frame is `IgnorePointer` and the handle is not.** That one line is what
makes "clicking a node does the usual thing" true without a single case in the
node path, and it is why the marquee still works over a group.

`GestureDetector.onDoubleTap` is **not** used on the handle, for the reason
`NodeView` already documents: a `DoubleTapGestureRecognizer` in the arena holds
every single tap for the double-tap timeout, including taps meant for the
colour menu nested inside it. The handle synthesises the double tap the same
way `_NodeViewState` does. This was caught by the colour-menu test failing to
open the menu at all.

Selecting a group deliberately does **not** select its nodes.
`selection.nodeIdsWithGroups` is the expansion, used by delete, cut, copy, drag
and paint order — and by nothing else. `selectAll` leaves groups out on purpose — including them would
delete each group's contents twice, once through the nodes and once through the
frame.

### The aliasing bug this surfaced

`NodeEditorSelection._apply` takes three sets, and callers express "keep what
you had" by passing the live internal set straight back in. It used to do
`_connectionIds..clear()..addAll(connectionIds)` — clearing the very set it was
about to read. Ctrl-clicking a node had always been silently dropping the
connection selection; adding a third set made it visible, because widening a
group stopped working. `_apply` copies all three before clearing anything, and
`controller_test.dart` pins it.

## Minimap

A readout, and everything about it follows from that. Nothing in the panel
moves the camera, so the drag is free to mean "move the panel" — which is the
gesture that matters, since a panel you cannot move sits on top of the graph
you are editing. It also means the minimap never calls the controller, never
bumps `revision`, and therefore cannot pull a node body back into the rebuild.
`rebuild_isolation_test.dart` re-runs its three numbers with the panel drawn.

Two caches, and they are the whole performance story:

- **`_MinimapSlot`** in `node_editor.dart` caches the panel's widget instance
  exactly as `_NodeSlot` caches a node's. `onMenuClosed` is a **held tear-off**
  (`_requestCanvasFocus`), never `() => _focusNode.requestFocus()` read per
  build — a closure is the one input that cannot compare equal to the last one,
  which is the same trap `_commentBuilder` documents.
- **`MinimapPainter` takes a `repaint` listenable**, the only painter here that
  does. It can because every input it reads is on a `ChangeNotifier`; the four
  canvas painters cannot, because theirs include `NodeEditorState` fields — the
  hovered port, the marquee, the pending wire — that only a rebuild delivers.
  Together the two mean a scroll tick repaints one layer and rebuilds nothing.
  Do not "tidy" the `repaint` away.

`MinimapScene` is keyed on `revision` the way `ConnectionLayout` is, and holds
**scene**-space rects: map space depends on the panel size and the zoom cap,
both of which move without the graph moving. Colours are re-derived every pass
regardless, because a node's colour comes from the selection and from its
group and the selection changes without `revision` moving — the same shape as
the caption bug `ConnectionLayout` records.

**The three guards live on the editor, not on the panel.** `MouseRegion.opaque`
and `HitTestBehavior.opaque` stop *siblings lower in the stack*; they do not
stop **ancestors**, and every annotation along the hit-test path still gets its
callback. The `Listener` and `MouseRegion` wrapping the canvas are both
ancestors of the panel, so `_handlePointerSignal`, `_handlePanZoom*` and
`_handleHover` each ask `_overMinimap` first — otherwise a scroll over the
panel zooms the canvas underneath it and a hover across it picks ports it is
not showing. The rect is reported *by* the panel rather than recomputed, since
resolving it means knowing the alignment default and the clamp, and two copies
of that arithmetic is how a guard stops guarding.

**The action bar carries no tap recogniser at all**, and that is deliberate.
`GroupView._Handle` had to synthesise its own double tap because it needed
`onTap` *and* a nested menu, and a `DoubleTapGestureRecognizer` in the arena
holds every tap until the timeout. The bar needs neither, so nothing competes
with the gear. Adding "double-click the bar to fold it" reintroduces the bug
the colour-menu test caught.

**The shade is four rects, and they are slices rather than insets.** Top and
bottom run the full width; the sides run only between them, so the complement
is covered exactly once. Four inset rects overlap at the corners, and the wash
is translucent, so overlapping bands composite twice and show as a darker cross
through the panel — a bug that looks like a rendering artefact and is
arithmetic. The runner-up was one even-odd `Path`: one draw call, but a `Path`
allocated on a repaint that happens on every scroll tick. `Path.combine` is the
one to avoid outright.

**Position is clamped at read time and never written back.** Writing during
build would notify mid-build, and leaving the stored value alone means a window
narrowed and widened again puts the panel back where it was put. A null
position means "still where `MinimapConfig.alignment` put it", which is what
keeps an untouched panel in its corner across a resize rather than stranding it
mid-canvas.

The map fits **content**, so a camera panned far into empty canvas leaves the
viewport marker off the map and the panel washes over entirely. That is honest
— you are looking at nothing — and the zoom cap gives it slack in practice,
since a capped map has empty margin around the content. The alternative is
fitting the union of the content and the visible rect, which keeps the marker
on the map at the cost of rescaling everything as you pan past the edge.

There is no cull: the whole graph is on the map by definition, so a camera tick
is O(nodes) in the painter. If that ever bites, the escape hatch is caching the
per-colour *map*-space paths keyed on `(revision, selection.revision,
projection)` — measure with `benchmark/widget_benchmark.dart` first.

## Serialisation

Ports and declared fields are derived and could be dropped from a document,
but **are stored by default**. That is only safe for a family that is a pure
function of the node's `data`: the demo's `fanOut` derives its exits from
*which exits are wired*, and on load there are no ports yet to count, so a wire
saved onto `exit_1` would find nothing to land on. `PortStorage.foreign` is the
opt-in for a host that has checked every family against that condition.

Optional values are omitted when null and the decoder guards on absence; values
with a default are **always written**, because omitting a value equal to
today's default is how changing that default later silently reinterprets every
document already written.

An unknown node type is not an error. It decodes to an ordinary `GraphNode` and
round-trips untouched — a document you cannot open is worse than a node you
cannot edit.

**There are two version axes and they are not interchangeable.** `version` is
this package's and governs the envelope: nodes, connections, groups, ports.
`schema` is the *host's* and governs what a node's `type` means and what the
keys in its `data` mean — which the package carries and never interprets, so it
is the only axis that can express a host's field being renamed or two being
folded into one. The line to hold: nothing in `lib/` may read a `schema` number
to decide anything, or the second axis has become a slower copy of the first.

The predecessor had both and the rewrite kept only the field. `app` survived as
a string that is written, read back and never interpreted, and the chain stayed
keyed on the package's integer — so `upgrade` ran `from` to `target` with
`target` always `1`, and a host-supplied `migrations` chain was unreachable
code rather than merely unused. That is what `schemaVersion` and
`schemaMigrations` put back.

Three rules the gates keep, in `decode`:

- **The format gate runs first, and so does the format migration.** The
  package's step normalises the envelope the host's step then walks; reversed,
  a host migration is handed a shape this build has already stopped believing
  in. A document out of range on both axes reports the format one, and there is
  a test that says so.
- **A missing `schema` reads as `legacySchemaVersion` (1)**, never as an error.
  Every document written before a host declared an axis has no key, which is all
  of them the first time it does — refusing those would break exactly the files
  the axis exists to carry forward.
- **A null `schemaVersion` is not the same as 1.** It means the host has no
  opinion, so a `schema` key is read, reported on the document and written back
  untouched rather than gated. `encode` prefers `document.schemaVersion` over
  the codec's for that reason, the way it already prefers `document.packageVersion`.

`_packageStamp` duplicates the version in `pubspec.yaml` by hand and nothing
checks it. Bump both together.

## Testing notes

- `testWidgets` **enables semantics by default** (`semanticsEnabled: true`); an
  app does not. This inflated one measurement by 10x. Both benchmarks pass
  `semanticsEnabled: false` with a comment saying why.
- `flutter test` **never rasterises**, so a widget benchmark can only price the
  UI thread. `example/lib/bench.dart` uses `FrameTiming` against a real window
  for the other half.
- `tester.startGesture` defaults to `PointerDeviceKind.touch`, and a touch drag
  always pans by design — a mouse-button test must pass
  `kind: PointerDeviceKind.mouse` or it is testing nothing.
- A point exactly on a node's right edge is *outside* its box; `size.contains`
  is exclusive. Press a few pixels inside.

## The trap that is not this package

On a raster complaint, **run the bare control first**:

```sh
cd example
fvm flutter run --profile -d linux -t lib/bench.dart --dart-define=MODE=bare
```

`MODE=bare` renders a single `Text`. If that is already slow, nothing here is
the reason. The usual cause on Linux is two GPUs — rendering on one, displaying
on the other, so every frame crosses PCIe and the cost is per-pixel with
nothing on screen:

```sh
xrandr --listproviders   # a "Source Output" renders, a "Sink Output" scans out
```

Measured on this machine — monitor on an RTX 4090, `prime-select` left on
`on-demand`, so GL ran on the 7800X3D's integrated GPU:

| bare window, one `Text` | raster p50 |
| --- | --- |
| 1280x720 | 1.38 ms |
| 2560x1348 | **20.28 ms** |

The fix is a system setting: `prime-select nvidia`, then log out.
`__NV_PRIME_RENDER_OFFLOAD` is for the *opposite* topology and does not work
here — the app comes up black with `Failed to create OpenGL context` while
`FrameTiming` cheerfully reports a fraction of a millisecond for drawing
nothing. **Do not trust a raster number without checking the run log for that
warning.**

## Known costs

- `NodeGraph.putNodes` copies the immutable node map: ~390 us per frame while
  dragging at 5000 nodes. Removing it means trading the immutable snapshot for
  in-place mutation with copy-on-checkpoint, and the model's guarantees with it.
- Resolution cannot change a node's `position`, `width` or `draggable`.
  Position is user state and would fight the drag path; width is a plausible
  future `resolveSize`. `NodePrototype.defaultWidth` is only a seed for
  `instantiate`.
- No node resizing handles. Comments size themselves to their text and group
  frames size themselves to their members, so nothing on the canvas is resized
  by hand.
- Groups do not nest, and a node belongs to at most one. Both are enforced in
  `putGroup` rather than left to the caller.
