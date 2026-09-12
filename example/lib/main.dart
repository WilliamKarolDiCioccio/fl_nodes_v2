import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

import 'inspector_panel.dart';
import 'prototype_nodes.dart';
import 'sample_graph.dart';
import 'workflow_node.dart';
import 'workflow_node_card.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Disable the native browser context menu if running on Web
  if (kIsWeb) {
    await BrowserContextMenu.disableContextMenu();
  }

  runApp(const NodeEditorDemoApp());
}

class NodeEditorDemoApp extends StatefulWidget {
  const NodeEditorDemoApp({super.key});

  @override
  State<NodeEditorDemoApp> createState() => _NodeEditorDemoAppState();
}

class _NodeEditorDemoAppState extends State<NodeEditorDemoApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Node Editor Demo',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B62D9)),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C9CF5),
          brightness: Brightness.dark,
        ),
      ),
      home: WorkflowEditorPage(
        isDark: _themeMode == ThemeMode.dark,
        onToggleBrightness: () => setState(() {
          _themeMode = _themeMode == ThemeMode.dark
              ? ThemeMode.light
              : ThemeMode.dark;
        }),
      ),
    );
  }
}

class WorkflowEditorPage extends StatefulWidget {
  const WorkflowEditorPage({
    super.key,
    required this.isDark,
    required this.onToggleBrightness,
  });

  final bool isDark;
  final VoidCallback onToggleBrightness;

  @override
  State<WorkflowEditorPage> createState() => _WorkflowEditorPageState();
}

class _WorkflowEditorPageState extends State<WorkflowEditorPage> {
  final GlobalKey<NodeEditorState> _editorKey = GlobalKey<NodeEditorState>();
  late final NodeEditorController _controller;

  bool _showGrid = true;
  bool _snapToGrid = false;

  /// Off by default: a wire let go by accident should cost nothing.
  bool _createOnDrop = false;
  bool _showMinimap = true;

  /// Owned here rather than left to the editor, so the panel comes back where
  /// it was left when the minimap is switched off and on again.
  final MinimapController _minimap = MinimapController();
  CanvasDragBehavior _dragBehavior = CanvasDragBehavior.marquee;

  @override
  void initState() {
    super.initState();
    _controller = NodeEditorController(
      graph: buildSampleGraph(),
      // The format and fan-out nodes arrive holding only their fields; their
      // ports are derived from those, here and on every later edit.
      prototypes: workflowPrototypes,
      // The same codec the Document menu saves with. Handing it over is what
      // puts a copied selection on the system clipboard, so it can be pasted
      // into a second window of this app.
      codec: _codec,
    );
    // The demo has no file picker, so its storage is the system clipboard.
    // A real host swaps these two callbacks for a file, a database or an
    // upload; nothing else about saving changes.
    _controller.project
      ..meta = const <String, Object?>{'title': 'Lead routing'}
      ..appVersion = 'workflow-demo/1.0.0'
      ..sink = (json) async {
        await Clipboard.setData(
          ClipboardData(text: const JsonEncoder.withIndent('  ').convert(json)),
        );
        return true;
      }
      ..source = () async {
        final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
        if (text == null || text.isEmpty) return null;
        final json = jsonDecode(text);
        if (json is! Map) {
          throw const FormatException('expected a JSON object');
        }
        return Map<String, Object?>.from(json);
      };
    // Everything a run does, as it does it. The demo keeps the record and
    // prints each line; a real host would draw a debugger from the same
    // events. Payloads stay withheld, which is the default and the point: a
    // trace that is printed is a trace that can be pasted somewhere.
    _controller.runner.onEvent = (event) {
      _trace.call(event);
      debugPrint(_describe(event));
    };
    // The first layout pass is what tells us how big auto-height nodes are, so
    // framing the graph waits for it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
  }

  final GraphRunRecorder _trace = GraphRunRecorder();

  /// One line per event. The switch is exhaustive, so a new kind of event is
  /// a compile error here rather than a line that never prints.
  static String _describe(GraphRunEvent event) {
    final at = '${event.at.inMilliseconds}ms'.padLeft(7);
    return switch (event) {
      RunStarted(:final roots, :final pullOnly) =>
        '$at run #${event.runId} from ${roots.join(', ')}'
            '${pullOnly ? ' (data only)' : ''}',
      NodeStarted(
        :final nodeId,
        :final step,
        :final enteredVia,
        :final inputs,
      ) =>
        '$at > $nodeId#$step'
            '${enteredVia == null ? '' : ' via $enteredVia'}'
            '${inputs.isEmpty ? '' : ' reading ${inputs.join(', ')}'}',
      NodeFinished(
        :final nodeId,
        :final outcome,
        :final outputs,
        :final flowed,
      ) =>
        '$at < $nodeId ${outcome.name}'
            '${outputs.isEmpty ? '' : ' wrote ${outputs.join(', ')}'}'
            '${flowed.isEmpty ? '' : ' -> ${flowed.join(', ')}'}',
      MemoHit(:final nodeId) => '$at = $nodeId (memo)',
      DiagnosticRaised(:final diagnostic) => '$at ! $diagnostic',
      LogEmitted(:final entry) => '$at   $entry',
      RunFinished(:final run) => '$at $run',
    };
  }

  @override
  void dispose() {
    _controller.dispose();
    _minimap.dispose();
    super.dispose();
  }

  void _fit() => _editorKey.currentState?.fitToContent();

  NodeEditorTheme get _editorTheme {
    final base = widget.isDark
        ? NodeEditorTheme.dark()
        : NodeEditorTheme.light();
    return base.copyWith(showGrid: _showGrid, snapToGrid: _snapToGrid ? 16 : 0);
  }

  /// Places a new node at the centre of the current view.
  ///
  /// The switch over node types that used to live here is gone: every type is
  /// a registered prototype now, so the registry knows how to build one and
  /// the editor's own "Create" menu builds the same node this does.
  void _addNode(String type, {Offset? scenePosition}) {
    final size = _editorKey.currentState?.viewportSize ?? const Size(800, 600);
    final position =
        scenePosition ??
        _controller.camera.viewport.toScene(
              Offset(size.width / 2, size.height / 2),
            ) -
            const Offset(CardMetrics.width / 2, 40);

    final id = _controller.nextId(type);
    _controller.addNode(
      _controller.prototypes.instantiate(type, id: id, position: position),
    );
    _controller.selection.selectNode(id);
  }

  /// The same note the canvas menu's "Add comment" makes, from the toolbar.
  void _addComment() {
    final size = _editorKey.currentState?.viewportSize ?? const Size(800, 600);
    final centre = _controller.camera.viewport.toScene(
      Offset(size.width / 2, size.height / 2),
    );
    _controller.selection.selectNode(
      _controller.addComment(position: centre - const Offset(130, 40)),
    );
  }

  void _loadGraph(NodeGraph graph) {
    _controller.project.reset(graph);
    _fit();
  }

  /// The document codec, told which prototypes are in play.
  ///
  /// It uses them only to decide what it may leave *out* — a caption the
  /// fan-out recomputes, for one. Reading never needs them.
  static final NodeGraphCodec _codec = NodeGraphCodec(
    prototypes: workflowPrototypes,
  );

  void _report(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyAsJson() async {
    await _controller.project.save();
    _report('Workflow copied to the clipboard as JSON');
  }

  Future<void> _pasteFromJson() async {
    final GraphDocument? document;
    try {
      document = await _controller.project.load();
    } on GraphDocumentException catch (error) {
      // Loading decodes before it replaces anything, so the open document is
      // still on screen. That is the whole point of the shape.
      _report('Could not open that: ${error.message} (at ${error.location})');
      return;
    } on FormatException catch (error) {
      _report('That is not JSON: ${error.message}');
      return;
    }

    if (document == null) {
      _report('The clipboard is empty');
      return;
    }
    // Reopened where it was left; a graph-only export gets framed instead.
    if (document.viewport == null) _fit();
    _report('Workflow loaded from the clipboard');
  }

  void _copySelection() {
    if (_controller.clipboard.copy()) {
      _report('Selection copied');
    } else {
      _report('Nothing selected to copy');
    }
  }

  void _cutSelection() {
    if (_controller.clipboard.cut()) {
      _report('Selection cut');
    } else {
      _report('Nothing selected to cut');
    }
  }

  Future<void> _paste() async {
    // Reads the system clipboard, so a selection copied in another window of
    // the app arrives; falls back to this window's own buffer otherwise.
    final Set<String> pasted;
    try {
      pasted = await _controller.clipboard.pasteFromSystem();
    } on GraphDocumentException catch (error) {
      _report('Could not paste that: ${error.message} (at ${error.location})');
      return;
    }
    _report(
      pasted.isEmpty ? 'Nothing to paste' : 'Pasted ${pasted.length} nodes',
    );
  }

  Future<void> _run() async {
    _trace.clear();
    final run = await _controller.runner.run();

    if (!run.succeeded) {
      _report(
        run.cancelled
            ? 'Run cancelled'
            : 'Run failed at ${run.failedNodeId}: ${run.error}',
      );
      return;
    }
    // The greeting is the only thing in the demo that computes a value, and it
    // only computes at all because the node it feeds reads it.
    final reply = run.valueAt(const PortRef('greeting', 'out'));
    final noted = run.diagnostics.isEmpty
        ? ''
        : ' \u00b7 ${run.diagnostics.length} note'
              '${run.diagnostics.length == 1 ? '' : 's'}';
    _report(
      'Ran ${run.trace.length} steps \u00b7 reply "$reply"$noted \u00b7 '
      '${_trace.events.length} events traced',
    );
  }

  /// The node types the editor will offer, in the order it offers them.
  List<NodePrototype> get _creatable {
    final registry = _controller.prototypes;
    return <NodePrototype>[
      for (final type in registry.types)
        if (registry[type]?.label != null) registry[type]!,
    ]..sort((a, b) => a.label!.compareTo(b.label!));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: <Widget>[
          _buildToolbar(context),
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Stack(
                    children: <Widget>[
                      // Deliberately *not* inside a ListenableBuilder on the
                      // controller. The editor already listens for itself, and
                      // rebuilding it on every tick would hand it a brand-new
                      // `nodeBuilder` closure every frame — which is the one
                      // thing that stops it reusing a node's widget, and turns
                      // a drag over a large graph into a slideshow.
                      Positioned.fill(child: _buildEditor()),
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: ListenableBuilder(
                          listenable: _controller,
                          builder: (context, _) => _StatusChip(
                            controller: _controller,
                            editorKey: _editorKey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                InspectorPanel(controller: _controller),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    return NodeEditor(
      key: _editorKey,
      controller: _controller,
      theme: _editorTheme,
      canvasDragBehavior: _dragBehavior,
      nodeBuilder: (context, node, state) =>
          WorkflowNodeCard(node: node, state: state, isDark: widget.isDark),
      // Dropping a wire on empty canvas offers the Create menu there rather
      // than guessing a node type, which is what it used to do.
      contextMenus: NodeEditorMenus(
        createOnDrop: _createOnDrop,
        onError: (error, _) => _report(
          error is GraphDocumentException
              ? 'Could not read that: ${error.message} (at ${error.location})'
              : '$error',
        ),
      ),
      minimap: _showMinimap ? const MinimapConfig() : null,
      minimapController: _minimap,
      onNodeDoubleTap: _renameNode,
    );
  }

  Future<void> _renameNode(GraphNode node) async {
    final controller = TextEditingController(text: node.title);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename node'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    _controller.updateNode(
      node.id,
      (current) => current.withData(<String, Object?>{'title': name}),
    );
  }

  /// Rebuilds just [build] whenever the controller changes.
  ///
  /// The toolbar used to sit inside one of these as a whole, which meant every
  /// frame of a node drag rebuilt every button, menu and toggle on it. Only a
  /// handful of them actually read controller state; the rest are static.
  Widget _live(Widget Function() build) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => build(),
  );

  Widget _buildToolbar(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: <Widget>[
            Text('Node Editor', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 16),
            MenuAnchor(
              menuChildren: <Widget>[
                for (final prototype in _creatable)
                  MenuItemButton(
                    leadingIcon: Icon(prototype.icon, size: 18),
                    onPressed: () => _addNode(prototype.type),
                    child: Text(prototype.label!),
                  ),
              ],
              builder: (context, menu, _) => FilledButton.icon(
                onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add node'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _addComment,
              icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
              label: const Text('Comment'),
            ),
            const SizedBox(width: 8),
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => OutlinedButton.icon(
                onPressed: _controller.selection.isEmpty
                    ? null
                    : () => _controller.groupSelection(),
                icon: const Icon(Icons.select_all, size: 18),
                label: const Text('Group'),
              ),
            ),
            const SizedBox(width: 8),
            MenuAnchor(
              menuChildren: <Widget>[
                MenuItemButton(
                  onPressed: () => _loadGraph(buildSampleGraph()),
                  child: const Text('Sample workflow'),
                ),
                for (final count in const <int>[500, 2000, 5000])
                  MenuItemButton(
                    onPressed: () => _loadGraph(buildStressGraph(count)),
                    child: Text('Stress test · $count nodes'),
                  ),
              ],
              builder: (context, menu, _) => OutlinedButton.icon(
                onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                icon: const Icon(Icons.dataset_outlined, size: 18),
                label: const Text('Load'),
              ),
            ),
            const SizedBox(width: 8),
            MenuAnchor(
              menuChildren: <Widget>[
                MenuItemButton(
                  leadingIcon: const Icon(Icons.copy_all_outlined, size: 18),
                  onPressed: _copyAsJson,
                  child: const Text('Copy as JSON'),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.paste_outlined, size: 18),
                  onPressed: _pasteFromJson,
                  child: const Text('Paste from JSON'),
                ),
              ],
              builder: (context, menu, _) => OutlinedButton.icon(
                onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('Document'),
              ),
            ),
            const SizedBox(width: 8),
            MenuAnchor(
              menuChildren: <Widget>[
                MenuItemButton(
                  leadingIcon: const Icon(Icons.content_copy, size: 18),
                  onPressed: _copySelection,
                  child: const Text('Copy'),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.content_cut, size: 18),
                  onPressed: _cutSelection,
                  child: const Text('Cut'),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.content_paste, size: 18),
                  onPressed: _paste,
                  child: const Text('Paste'),
                ),
                // Built when the menu opens, not on every controller tick:
                // a menu item nobody can see does not need to keep up.
                _live(
                  () => MenuItemButton(
                    leadingIcon: const Icon(
                      Icons.control_point_duplicate,
                      size: 18,
                    ),
                    onPressed: _controller.selection.isNotEmpty
                        ? () => _controller.clipboard.duplicate()
                        : null,
                    child: const Text('Duplicate'),
                  ),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.select_all, size: 18),
                  onPressed: _controller.selection.selectAll,
                  child: const Text('Select all'),
                ),
              ],
              builder: (context, menu, _) => OutlinedButton.icon(
                onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
            ),
            const _ToolbarDivider(),
            _live(
              () => IconButton(
                tooltip: 'Undo (Ctrl+Z)',
                onPressed: _controller.history.canUndo
                    ? _controller.history.undo
                    : null,
                icon: const Icon(Icons.undo),
              ),
            ),
            _live(
              () => IconButton(
                tooltip: 'Redo (Ctrl+Shift+Z)',
                onPressed: _controller.history.canRedo
                    ? _controller.history.redo
                    : null,
                icon: const Icon(Icons.redo),
              ),
            ),
            _live(
              () => IconButton(
                tooltip: 'Run the workflow',
                onPressed: _controller.runner.isRunning ? null : _run,
                icon: const Icon(Icons.play_arrow),
              ),
            ),
            _live(
              () => IconButton(
                tooltip: 'Delete selection (Del)',
                onPressed: _controller.selection.isNotEmpty
                    ? _controller.selection.deleteSelected
                    : null,
                icon: const Icon(Icons.delete_outline),
              ),
            ),
            const _ToolbarDivider(),
            IconButton(
              tooltip: 'Zoom out',
              onPressed: () => _controller.camera.zoomBy(1 / 1.2),
              icon: const Icon(Icons.zoom_out),
            ),
            IconButton(
              tooltip: 'Zoom in',
              onPressed: () => _controller.camera.zoomBy(1.2),
              icon: const Icon(Icons.zoom_in),
            ),
            IconButton(
              tooltip: 'Fit to content',
              onPressed: _fit,
              icon: const Icon(Icons.fit_screen_outlined),
            ),
            const _ToolbarDivider(),
            _Toggle(
              icon: Icons.grid_4x4,
              tooltip: 'Show grid',
              value: _showGrid,
              onChanged: (value) => setState(() => _showGrid = value),
            ),
            _Toggle(
              icon: Icons.grid_goldenratio,
              tooltip: 'Snap to grid',
              value: _snapToGrid,
              onChanged: (value) => setState(() => _snapToGrid = value),
            ),
            _Toggle(
              icon: Icons.add_link,
              tooltip: 'Dropping a wire on empty canvas offers a new node',
              value: _createOnDrop,
              onChanged: (value) => setState(() => _createOnDrop = value),
            ),
            _Toggle(
              icon: Icons.map_outlined,
              tooltip: 'Show the minimap',
              value: _showMinimap,
              onChanged: (value) => setState(() => _showMinimap = value),
            ),
            _Toggle(
              icon: Icons.pan_tool_outlined,
              tooltip: 'Drag pans instead of selecting',
              value: _dragBehavior == CanvasDragBehavior.pan,
              onChanged: (value) => setState(() {
                _dragBehavior = value
                    ? CanvasDragBehavior.pan
                    : CanvasDragBehavior.marquee;
              }),
            ),
            IconButton(
              tooltip: 'Toggle brightness',
              onPressed: widget.onToggleBrightness,
              icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 6),
    child: SizedBox(height: 22, child: VerticalDivider(width: 1)),
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.tooltip,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String tooltip;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      isSelected: value,
      onPressed: () => onChanged(!value),
      icon: Icon(icon),
      style: IconButton.styleFrom(
        foregroundColor: value ? Theme.of(context).colorScheme.primary : null,
      ),
    );
  }
}

/// Shows what the renderer is actually doing: how much of the graph survives
/// culling, and how often the connection cache has had to rebuild.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.controller, required this.editorKey});

  final NodeEditorController controller;
  final GlobalKey<NodeEditorState> editorKey;

  @override
  Widget build(BuildContext context) {
    final graph = controller.graph;
    final zoom = (controller.camera.viewport.scale * 100).round();
    final editor = editorKey.currentState;

    var detail = '';
    if (editor != null && !editor.viewportSize.isEmpty) {
      final visible = controller.camera.viewport.visibleSceneRect(
        editor.viewportSize,
      );
      detail =
          ' \u00b7 ${controller.layout.nodesIn(visible).length} drawn'
          ' \u00b7 ${editor.connectionLayout.pathBuildCount} curves built';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${graph.nodes.length} nodes \u00b7 ${graph.connections.length} links'
        ' \u00b7 $zoom%$detail'
        '${controller.project.isDirty ? ' \u00b7 unsaved' : ''}',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
