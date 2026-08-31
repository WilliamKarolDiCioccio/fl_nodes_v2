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
`selection.nodeIdsWithGroups` is the expansion, and only delete, cut, copy and
drag use it. `selectAll` leaves groups out on purpose — including them would
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
