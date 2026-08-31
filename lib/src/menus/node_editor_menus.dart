import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/node_editor_controller.dart';
import '../model/graph_node.dart';
import '../model/node_connection.dart';
import '../model/node_group.dart';
import '../model/port_ref.dart';
import 'node_menu_entry.dart';

/// What the app user right-clicked.
@immutable
sealed class NodeMenuTarget {
  const NodeMenuTarget(this.scenePosition);

  /// Where the click landed, in scene coordinates.
  final Offset scenePosition;
}

final class NodeMenuNodeTarget extends NodeMenuTarget {
  const NodeMenuNodeTarget(this.node, super.scenePosition);
  final GraphNode node;
}

final class NodeMenuPortTarget extends NodeMenuTarget {
  const NodeMenuPortTarget(this.port, super.scenePosition);
  final PortRef port;
}

final class NodeMenuConnectionTarget extends NodeMenuTarget {
  const NodeMenuConnectionTarget(this.connection, super.scenePosition);
  final NodeConnection connection;
}

final class NodeMenuGroupTarget extends NodeMenuTarget {
  const NodeMenuGroupTarget(this.group, super.scenePosition);
  final NodeGroup group;
}

final class NodeMenuCanvasTarget extends NodeMenuTarget {
  const NodeMenuCanvasTarget(super.scenePosition);
}

/// Everything a menu needs that the controller cannot supply on its own.
///
/// The three project actions and [describeNode] are callbacks rather than
/// direct calls because each of them wants a [BuildContext] — a confirmation,
/// a dialog, somewhere to report a failed load. The editor owns those; the
/// entry builders below stay pure, which is what lets them be tested without
/// a widget tree.
@immutable
class NodeMenuRequest {
  const NodeMenuRequest({
    required this.controller,
    required this.target,
    required this.viewportSize,
    required this.describeNode,
    required this.renameGroup,
    required this.newProject,
    required this.openProject,
    required this.saveProject,
  });

  final NodeEditorController controller;
  final NodeMenuTarget target;

  /// Needed to centre the view and to zoom about the middle of it.
  final Size viewportSize;

  final void Function(GraphNode node, String description) describeNode;

  /// Asks for a new name for a group. A dialog, so it needs a context.
  final void Function(NodeGroup group) renameGroup;
  final VoidCallback newProject;
  final VoidCallback openProject;
  final VoidCallback saveProject;

  Offset get scenePosition => target.scenePosition;
}

/// Decides the entries of a menu, given the ones the editor would have shown.
typedef NodeMenuBuilder =
    List<NodeMenuEntry> Function(
      NodeMenuRequest request,
      List<NodeMenuEntry> defaults,
    );

/// The editor's right-click menus.
///
/// Pass `contextMenus: null` to [NodeEditor] to turn them off entirely. A host
/// that supplies its own `onNodeSecondaryTap` or `onCanvasSecondaryTap` keeps
/// it — the callback wins for that target and no built-in menu opens, so
/// nothing that worked before starts showing two things at once.
@immutable
class NodeEditorMenus {
  const NodeEditorMenus({
    this.showProjectMenu = true,
    this.createOnDrop = false,
    this.build,
    this.onError,
  });

  /// Whether the canvas menu offers new / open / save / undo / redo.
  ///
  /// Open and save are individually disabled unless the host has given
  /// `controller.project` a source and a sink, so an app that wires neither
  /// gets undo and redo and nothing that pretends to work.
  final bool showProjectMenu;

  /// Whether dropping a wire on empty canvas offers the "Create" menu there.
  ///
  /// Off by default: a wire let go by accident should cost nothing. When it is
  /// on the menu replaces `NodeEditor.onConnectionDropped`, which is not
  /// called — the two would otherwise both make a node out of one gesture.
  final bool createOnDrop;

  /// Rewrites the entries just before they are shown.
  ///
  /// It receives the defaults, so adding one line is `[...defaults, mine]`
  /// rather than rebuilding the menu. Returning an empty list opens nothing.
  final NodeMenuBuilder? build;

  /// Where a failed open or save goes. Defaults to [FlutterError.reportError].
  final void Function(Object error, StackTrace stackTrace)? onError;

  /// The entries to show, defaults through [build].
  List<NodeMenuEntry> entriesFor(NodeMenuRequest request) {
    final defaults = NodeMenuEntry.tidy(defaultsFor(request));
    final hook = build;
    if (hook == null) return defaults;
    return NodeMenuEntry.tidy(hook(request, defaults));
  }

  /// The entries the editor would show, before [build] gets a say.
  List<NodeMenuEntry> defaultsFor(NodeMenuRequest request) =>
      switch (request.target) {
        NodeMenuNodeTarget(node: final node) => _nodeEntries(request, node),
        NodeMenuPortTarget(port: final port) => _portEntries(request, port),
        NodeMenuConnectionTarget(connection: final connection) =>
          _connectionEntries(request, connection),
        NodeMenuGroupTarget(group: final group) => _groupEntries(
          request,
          group,
        ),
        NodeMenuCanvasTarget() => _canvasEntries(request),
      };

  // ------------------------------------------------------------------ node

  List<NodeMenuEntry> _nodeEntries(NodeMenuRequest request, GraphNode node) {
    final controller = request.controller;
    final selection = controller.selection;
    final clipboard = controller.clipboard;
    // Right-clicking selects first, so by the time these run there is always
    // something under them.
    final hasSelection = selection.nodeIds.isNotEmpty;
    final description = controller.prototypes[node.type]?.description;

    return <NodeMenuEntry>[
      NodeMenuEntry(
        label: 'Cut',
        icon: Icons.content_cut,
        shortcut: const SingleActivator(LogicalKeyboardKey.keyX, control: true),
        onSelected: hasSelection ? () => clipboard.cut() : null,
      ),
      NodeMenuEntry(
        label: 'Copy',
        icon: Icons.copy_outlined,
        shortcut: const SingleActivator(LogicalKeyboardKey.keyC, control: true),
        onSelected: hasSelection ? () => clipboard.copy() : null,
      ),
      NodeMenuEntry(
        label: 'Delete',
        icon: Icons.delete_outline,
        shortcut: const SingleActivator(LogicalKeyboardKey.delete),
        onSelected: hasSelection ? selection.deleteSelected : null,
      ),
      const NodeMenuEntry.separator(),
      // The keystroke is the real path; this is how anyone finds out there is
      // one. Disabled rather than hidden when the selection cannot be framed,
      // so the entry teaches the rule instead of vanishing without saying why.
      NodeMenuEntry(
        label: _groupLabel(controller),
        icon: Icons.select_all,
        shortcut: const SingleActivator(LogicalKeyboardKey.keyG, control: true),
        onSelected: _canGroup(controller) ? controller.groupSelection : null,
      ),
      if (description != null && description.trim().isNotEmpty)
        NodeMenuEntry(
          label: 'Description',
          icon: Icons.info_outline,
          onSelected: () => request.describeNode(node, description),
        ),
    ];
  }

  /// "Group" for a fresh frame, "Add to group" when one is in the selection —
  /// the same command either way, named after what it is about to do.
  static String _groupLabel(NodeEditorController controller) =>
      controller.selection.groupIds.isEmpty ? 'Group' : 'Add to group';

  /// Mirrors the rules in [NodeEditorController.groupSelection]. Asked here so
  /// the entry can be greyed out rather than doing nothing when chosen.
  static bool _canGroup(NodeEditorController controller) {
    final selection = controller.selection;
    if (selection.groupIds.length > 1) return false;
    final target = selection.groupIds.isEmpty ? null : selection.groupIds.first;
    final loose = <String>[
      for (final id in selection.nodeIds)
        if (controller.graph.nodes.containsKey(id)) id,
    ];
    if (loose.isEmpty) return false;
    for (final id in loose) {
      final owner = controller.graph.groupOf(id);
      if (owner != null && owner.id != target) return false;
    }
    return true;
  }

  // ----------------------------------------------------------------- group

  List<NodeMenuEntry> _groupEntries(NodeMenuRequest request, NodeGroup group) {
    final controller = request.controller;

    return <NodeMenuEntry>[
      NodeMenuEntry(
        label: 'Cut',
        icon: Icons.content_cut,
        shortcut: const SingleActivator(LogicalKeyboardKey.keyX, control: true),
        onSelected: () => controller.clipboard.cut(),
      ),
      NodeMenuEntry(
        label: 'Copy',
        icon: Icons.copy_outlined,
        shortcut: const SingleActivator(LogicalKeyboardKey.keyC, control: true),
        onSelected: () => controller.clipboard.copy(),
      ),
      // Says what it takes with it. Deleting a frame and leaving the nodes is
      // a different command, and it is the next one down.
      NodeMenuEntry(
        label: 'Delete with contents',
        icon: Icons.delete_outline,
        shortcut: const SingleActivator(LogicalKeyboardKey.delete),
        onSelected: controller.selection.deleteSelected,
      ),
      NodeMenuEntry(
        label: 'Disband',
        icon: Icons.grid_off_outlined,
        onSelected: () => controller.disbandGroups(<String>[group.id]),
      ),
      const NodeMenuEntry.separator(),
      NodeMenuEntry(
        label: 'Rename',
        icon: Icons.edit_outlined,
        onSelected: () => request.renameGroup(group),
      ),
      NodeMenuEntry(
        label: 'Colour',
        icon: Icons.palette_outlined,
        children: <NodeMenuEntry>[
          NodeMenuEntry(
            label: 'Neutral',
            onSelected: () => controller.setGroupColor(group.id, null),
          ),
          for (final swatch in NodeGroup.palette)
            NodeMenuEntry(
              label: '#${swatch.toARGB32().toRadixString(16).substring(2)}',
              onSelected: () => controller.setGroupColor(group.id, swatch),
            ),
        ],
      ),
    ];
  }

  // ------------------------------------------------------------------ port

  List<NodeMenuEntry> _portEntries(NodeMenuRequest request, PortRef port) {
    final controller = request.controller;
    final wires = controller.graph
        .connectionsAt(port)
        .map((connection) => connection.id)
        .toList(growable: false);

    return <NodeMenuEntry>[
      NodeMenuEntry(
        label: wires.length == 1 ? 'Cut link' : 'Cut links',
        icon: Icons.link_off,
        onSelected: wires.isEmpty
            ? null
            : () => controller.removeConnections(wires),
      ),
    ];
  }

  // ------------------------------------------------------------------ link

  List<NodeMenuEntry> _connectionEntries(
    NodeMenuRequest request,
    NodeConnection connection,
  ) {
    final controller = request.controller;

    void goTo(String nodeId) {
      controller.selection.selectNode(nodeId);
      controller.camera.centerOnNode(nodeId, request.viewportSize);
    }

    // A self-connection leaves nowhere to go, and both ends would scroll to
    // the same place.
    final loops = connection.from.nodeId == connection.to.nodeId;

    return <NodeMenuEntry>[
      NodeMenuEntry(
        label: 'Go to source',
        icon: Icons.arrow_back,
        onSelected: loops ? null : () => goTo(connection.from.nodeId),
      ),
      NodeMenuEntry(
        label: 'Go to destination',
        icon: Icons.arrow_forward,
        onSelected: loops ? null : () => goTo(connection.to.nodeId),
      ),
      const NodeMenuEntry.separator(),
      NodeMenuEntry(
        label: 'Delete',
        icon: Icons.delete_outline,
        onSelected: () => controller.removeConnections(<String>[connection.id]),
      ),
    ];
  }

  // ---------------------------------------------------------------- canvas

  List<NodeMenuEntry> _canvasEntries(NodeMenuRequest request) {
    final controller = request.controller;
    final camera = controller.camera;
    final size = request.viewportSize;
    final create = _createEntries(request);

    return <NodeMenuEntry>[
      NodeMenuEntry(
        label: 'Center view',
        icon: Icons.center_focus_weak_outlined,
        onSelected: controller.graph.isEmpty
            ? null
            : () => camera.centerOnContent(size),
      ),
      NodeMenuEntry(
        label: 'Reset zoom',
        icon: Icons.youtube_searched_for,
        // About the middle of the viewport, so whatever the user was looking
        // at is still what they are looking at.
        onSelected: () => camera.setScale(
          1,
          focalScreenPoint: Offset(size.width / 2, size.height / 2),
        ),
      ),
      NodeMenuEntry(
        label: 'Paste',
        icon: Icons.paste_outlined,
        shortcut: const SingleActivator(LogicalKeyboardKey.keyV, control: true),
        onSelected: controller.clipboard.canPaste
            ? () => controller.clipboard.paste(
                scenePosition: request.scenePosition,
              )
            : null,
      ),
      const NodeMenuEntry.separator(),
      // Nothing to create is not the same as an empty submenu to open: a host
      // that has named none of its prototypes gets no Create at all.
      if (create.isNotEmpty)
        NodeMenuEntry(label: 'Create', icon: Icons.add, children: create),
      // Its own entry rather than one more line inside Create, so a host that
      // does not want notes can drop it from `build` with a `where` instead of
      // rebuilding the submenu around it.
      NodeMenuEntry(
        label: 'Add comment',
        icon: Icons.sticky_note_2_outlined,
        onSelected: () => controller.selection.selectNode(
          controller.addComment(position: request.scenePosition),
        ),
      ),
      if (showProjectMenu)
        NodeMenuEntry(
          label: 'Project',
          icon: Icons.folder_outlined,
          children: _projectEntries(request),
        ),
    ];
  }

  /// The "Create" entries alone, with a custom action per node type.
  ///
  /// The drop-to-create path shows the same list but has to wire the new node
  /// up afterwards, and that is the only difference between the two.
  List<NodeMenuEntry> createEntriesFor(
    NodeMenuRequest request,
    void Function(String type) onCreate,
  ) => _createEntries(request, onCreate);

  /// One entry per prototype that has been given a [NodePrototype.label],
  /// grouped by category when any of them names one.
  List<NodeMenuEntry> _createEntries(
    NodeMenuRequest request, [
    void Function(String type)? onCreate,
  ]) {
    final controller = request.controller;
    final registry = controller.prototypes;

    final creatable = <String>[
      for (final type in registry.types)
        if (registry[type]?.label != null) type,
    ]..sort((a, b) => registry[a]!.label!.compareTo(registry[b]!.label!));

    NodeMenuEntry entryFor(String type) {
      final prototype = registry[type]!;
      return NodeMenuEntry(
        label: prototype.label!,
        icon: prototype.icon,
        onSelected: onCreate == null
            ? () => createNode(request, type)
            : () => onCreate(type),
      );
    }

    final grouped = creatable.any((type) => registry[type]!.category != null);
    if (!grouped) {
      return <NodeMenuEntry>[for (final type in creatable) entryFor(type)];
    }

    // Ungrouped prototypes sit at the top, above the named groups, rather
    // than under an invented "Other" heading nobody chose.
    final categories = <String, List<NodeMenuEntry>>{};
    final loose = <NodeMenuEntry>[];
    for (final type in creatable) {
      final category = registry[type]!.category;
      if (category == null) {
        loose.add(entryFor(type));
      } else {
        (categories[category] ??= <NodeMenuEntry>[]).add(entryFor(type));
      }
    }

    final names = categories.keys.toList()..sort();
    return <NodeMenuEntry>[
      ...loose,
      for (final name in names)
        NodeMenuEntry(label: name, children: categories[name]!),
    ];
  }

  List<NodeMenuEntry> _projectEntries(NodeMenuRequest request) {
    final controller = request.controller;
    final history = controller.history;
    final project = controller.project;

    return <NodeMenuEntry>[
      NodeMenuEntry(
        label: 'Undo',
        icon: Icons.undo,
        shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, control: true),
        onSelected: history.canUndo ? history.undo : null,
      ),
      NodeMenuEntry(
        label: 'Redo',
        icon: Icons.redo,
        shortcut: const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ),
        onSelected: history.canRedo ? history.redo : null,
      ),
      const NodeMenuEntry.separator(),
      NodeMenuEntry(
        label: 'Open',
        icon: Icons.folder_open_outlined,
        onSelected: project.canLoad ? request.openProject : null,
      ),
      NodeMenuEntry(
        label: 'Save',
        icon: Icons.save_outlined,
        onSelected: project.canSave ? request.saveProject : null,
      ),
      NodeMenuEntry(
        label: 'New project',
        icon: Icons.note_add_outlined,
        onSelected: request.newProject,
      ),
    ];
  }

  /// Adds a node of [type] where the menu was opened and selects it.
  ///
  /// Public because the drop-to-create path builds the same entries and has to
  /// wire the new node up afterwards.
  static String createNode(NodeMenuRequest request, String type) {
    final controller = request.controller;
    final id = controller.nextId(type);
    controller.addNode(
      controller.prototypes.instantiate(
        type,
        id: id,
        position: request.scenePosition,
      ),
    );
    controller.selection.selectNode(id);
    return id;
  }
}
