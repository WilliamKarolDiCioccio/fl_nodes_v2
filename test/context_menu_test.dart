import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

/// Entries are data, so what a menu offers — and what it offers greyed out —
/// is asserted here without pumping a menu and dismissing it. The widget-level
/// half of this lives in `context_menu_actions_test.dart`.
void main() {
  const menus = NodeEditorMenus();

  GraphNode node(String id, {String type = 'plain', Offset? at}) => GraphNode(
    id: id,
    type: type,
    position: at ?? const Offset(0, 0),
    width: 160,
    height: 90,
    ports: const <NodePort>[
      NodePort.input(id: 'in'),
      NodePort.output(id: 'out'),
    ],
  );

  NodeEditorController boot({
    NodeGraph? graph,
    NodePrototypeRegistry? prototypes,
  }) {
    final controller = NodeEditorController(
      graph:
          graph ??
          NodeGraph(
            nodes: <GraphNode>[
              node('a'),
              node('b', at: const Offset(400, 0)),
            ],
          ),
      prototypes: prototypes,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  NodeMenuRequest request(
    NodeEditorController controller,
    NodeMenuTarget target, {
    void Function(GraphNode, String)? describeNode,
    void Function(NodeGroup)? renameGroup,
    VoidCallback? newProject,
    VoidCallback? openProject,
    VoidCallback? saveProject,
  }) => NodeMenuRequest(
    controller: controller,
    target: target,
    viewportSize: const Size(800, 600),
    describeNode: describeNode ?? (_, _) {},
    renameGroup: renameGroup ?? (_) {},
    newProject: newProject ?? () {},
    openProject: openProject ?? () {},
    saveProject: saveProject ?? () {},
  );

  List<String> labels(List<NodeMenuEntry> entries) => <String>[
    for (final entry in entries)
      if (entry.isSeparator) '---' else entry.label,
  ];

  NodeMenuEntry find(List<NodeMenuEntry> entries, String label) =>
      entries.firstWhere((entry) => entry.label == label);

  group('node menu', () {
    test('offers cut, copy, delete', () {
      final controller = boot();
      controller.selection.selectNode('a');
      final entries = menus.entriesFor(
        request(
          controller,
          NodeMenuNodeTarget(controller.graph.nodes['a']!, Offset.zero),
        ),
      );

      expect(labels(entries), <String>[
        'Cut',
        'Copy',
        'Delete',
        '---',
        'Group',
      ]);
      expect(
        entries.where((entry) => !entry.isSeparator).every((e) => e.isEnabled),
        isTrue,
      );
    });

    test('shows a description only when the prototype declares one', () {
      final controller = boot(
        graph: NodeGraph(
          nodes: <GraphNode>[
            node('a', type: 'documented'),
            node('b', type: 'bare'),
            node('c', type: 'unregistered'),
          ],
        ),
        prototypes: NodePrototypeRegistry(const <NodePrototype>[
          NodePrototype(type: 'documented', description: 'What it does.'),
          NodePrototype(type: 'bare'),
        ]),
      );

      List<String> forNode(String id) => labels(
        menus.entriesFor(
          request(
            controller,
            NodeMenuNodeTarget(controller.graph.nodes[id]!, Offset.zero),
          ),
        ),
      );

      expect(forNode('a'), contains('Description'));
      expect(forNode('b'), isNot(contains('Description')));
      expect(
        forNode('c'),
        isNot(contains('Description')),
        reason: 'a node whose type has no prototype has nowhere to keep one',
      );
    });

    test('a blank description counts as none', () {
      final controller = boot(
        graph: NodeGraph(nodes: <GraphNode>[node('a', type: 'blank')]),
        prototypes: NodePrototypeRegistry(const <NodePrototype>[
          NodePrototype(type: 'blank', description: '   '),
        ]),
      );

      expect(
        labels(
          menus.entriesFor(
            request(
              controller,
              NodeMenuNodeTarget(controller.graph.nodes['a']!, Offset.zero),
            ),
          ),
        ),
        isNot(contains('Description')),
      );
    });

    test('the trailing separator is dropped when nothing follows it', () {
      final controller = boot();
      controller.selection.selectNode('a');
      final entries = menus.entriesFor(
        request(
          controller,
          NodeMenuNodeTarget(controller.graph.nodes['a']!, Offset.zero),
        ),
      );

      expect(
        entries.last.isSeparator,
        isFalse,
        reason: 'the rule before "Description" has nothing under it here',
      );
    });
  });

  group('port menu', () {
    test('cut links is disabled on an unwired port', () {
      final controller = boot();
      final entries = menus.entriesFor(
        request(
          controller,
          const NodeMenuPortTarget(PortRef('a', 'out'), Offset.zero),
        ),
      );

      expect(entries.single.label, 'Cut links');
      expect(entries.single.isEnabled, isFalse);
    });

    test('cut links is enabled and singular for one wire', () {
      final controller = boot();
      controller.connect(const PortRef('a', 'out'), const PortRef('b', 'in'));

      final entries = menus.entriesFor(
        request(
          controller,
          const NodeMenuPortTarget(PortRef('a', 'out'), Offset.zero),
        ),
      );

      expect(entries.single.label, 'Cut link');
      expect(entries.single.isEnabled, isTrue);
    });
  });

  group('link menu', () {
    test('offers both ends and a delete', () {
      final controller = boot();
      final id = controller.connect(
        const PortRef('a', 'out'),
        const PortRef('b', 'in'),
      )!;

      final entries = menus.entriesFor(
        request(
          controller,
          NodeMenuConnectionTarget(
            controller.graph.connections[id]!,
            Offset.zero,
            insertion: const RoutePoint(
              index: 0,
              position: Offset(200, 100),
              distance: 0,
            ),
          ),
        ),
      );

      expect(labels(entries), <String>[
        'Go to source',
        'Go to destination',
        '---',
        'Add waypoint here',
        'Clear waypoints',
        '---',
        'Delete',
      ]);
      expect(
        labels(entries.where((e) => !e.isSeparator && !e.isEnabled).toList()),
        <String>['Clear waypoints'],
        reason: 'nothing to clear on a wire that has no waypoints yet',
      );

      entries.firstWhere((e) => e.label == 'Add waypoint here').onSelected!();
      expect(
        controller.graph.connections[id]!.waypoints,
        <Offset>[const Offset(200, 100)],
        reason: 'the entry adds the point the editor said it would',
      );
    });

    test('adding needs the editor to have said where', () {
      final controller = boot();
      final id = controller.connect(
        const PortRef('a', 'out'),
        const PortRef('b', 'in'),
      )!;
      final entries = menus.entriesFor(
        request(
          controller,
          NodeMenuConnectionTarget(
            controller.graph.connections[id]!,
            Offset.zero,
          ),
        ),
      );
      expect(
        entries.firstWhere((e) => e.label == 'Add waypoint here').isEnabled,
        isFalse,
      );
    });

    test('on a handle the menu is about that handle', () {
      final controller = boot();
      final id = controller.connect(
        const PortRef('a', 'out'),
        const PortRef('b', 'in'),
      )!;
      controller.setConnectionWaypoints(id, const <Offset>[
        Offset(200, 50),
        Offset(260, 150),
      ]);

      final entries = menus.entriesFor(
        request(
          controller,
          NodeMenuConnectionTarget(
            controller.graph.connections[id]!,
            Offset.zero,
            waypoint: 1,
          ),
        ),
      );
      expect(labels(entries), <String>[
        'Go to source',
        'Go to destination',
        '---',
        'Remove waypoint',
        'Clear waypoints',
        '---',
        'Delete',
      ]);
      expect(
        entries.where((entry) => !entry.isSeparator).every((e) => e.isEnabled),
        isTrue,
      );

      entries.firstWhere((e) => e.label == 'Remove waypoint').onSelected!();
      expect(controller.graph.connections[id]!.waypoints, <Offset>[
        const Offset(200, 50),
      ]);

      final again = menus.entriesFor(
        request(
          controller,
          NodeMenuConnectionTarget(
            controller.graph.connections[id]!,
            Offset.zero,
          ),
        ),
      );
      again.firstWhere((e) => e.label == 'Clear waypoints').onSelected!();
      expect(controller.graph.connections[id]!.waypoints, isEmpty);
    });

    test('navigation is disabled on a self-connection', () {
      final controller = NodeEditorController(
        graph: NodeGraph(nodes: <GraphNode>[node('a')]),
        allowSelfConnections: true,
      );
      addTearDown(controller.dispose);
      final id = controller.connect(
        const PortRef('a', 'out'),
        const PortRef('a', 'in'),
      )!;

      final entries = menus.entriesFor(
        request(
          controller,
          NodeMenuConnectionTarget(
            controller.graph.connections[id]!,
            Offset.zero,
          ),
        ),
      );

      expect(find(entries, 'Go to source').isEnabled, isFalse);
      expect(find(entries, 'Go to destination').isEnabled, isFalse);
      expect(
        find(entries, 'Delete').isEnabled,
        isTrue,
        reason: 'a loop is still a link, and deleting it is the way out',
      );
    });
  });

  group('canvas menu', () {
    test('paste is disabled with an empty clipboard', () {
      final controller = boot();
      final entries = menus.entriesFor(
        request(controller, const NodeMenuCanvasTarget(Offset.zero)),
      );

      expect(find(entries, 'Paste').isEnabled, isFalse);

      controller.selection.selectNode('a');
      controller.clipboard.copy();

      final after = menus.entriesFor(
        request(controller, const NodeMenuCanvasTarget(Offset.zero)),
      );
      expect(find(after, 'Paste').isEnabled, isTrue);
    });

    test('center view is disabled on an empty graph', () {
      final controller = NodeEditorController();
      addTearDown(controller.dispose);

      final entries = menus.entriesFor(
        request(controller, const NodeMenuCanvasTarget(Offset.zero)),
      );
      expect(find(entries, 'Center view').isEnabled, isFalse);
    });

    test('no Create submenu when no prototype is named', () {
      final controller = boot(
        prototypes: NodePrototypeRegistry(const <NodePrototype>[
          NodePrototype(type: 'plain'),
        ]),
      );

      expect(
        labels(
          menus.entriesFor(
            request(controller, const NodeMenuCanvasTarget(Offset.zero)),
          ),
        ),
        isNot(contains('Create')),
        reason: 'an empty submenu is worse than no submenu',
      );
    });

    test('Create lists named prototypes alphabetically, flat', () {
      final controller = boot(
        prototypes: NodePrototypeRegistry(const <NodePrototype>[
          NodePrototype(type: 'z', label: 'Alpha'),
          NodePrototype(type: 'a', label: 'Beta'),
          NodePrototype(type: 'hidden'),
        ]),
      );

      final create = find(
        menus.entriesFor(
          request(controller, const NodeMenuCanvasTarget(Offset.zero)),
        ),
        'Create',
      );

      expect(labels(create.children), <String>['Alpha', 'Beta']);
    });

    test('Create groups by category once one is named', () {
      final controller = boot(
        prototypes: NodePrototypeRegistry(const <NodePrototype>[
          NodePrototype(type: 'a', label: 'Loose'),
          NodePrototype(type: 'b', label: 'Split', category: 'Flow'),
          NodePrototype(type: 'c', label: 'Merge', category: 'Flow'),
          NodePrototype(type: 'd', label: 'Text', category: 'Data'),
        ]),
      );

      final create = find(
        menus.entriesFor(
          request(controller, const NodeMenuCanvasTarget(Offset.zero)),
        ),
        'Create',
      );

      expect(
        labels(create.children),
        <String>['Loose', 'Data', 'Flow'],
        reason:
            'an uncategorised prototype sits above the groups rather than '
            'under an "Other" heading nobody asked for',
      );
      expect(labels(find(create.children, 'Flow').children), <String>[
        'Merge',
        'Split',
      ]);
    });

    test('project entries track what the controller can actually do', () {
      final controller = boot();
      final project = find(
        menus.entriesFor(
          request(controller, const NodeMenuCanvasTarget(Offset.zero)),
        ),
        'Project',
      );

      expect(labels(project.children), <String>[
        'Undo',
        'Redo',
        '---',
        'Open',
        'Save',
        'New project',
      ]);
      expect(find(project.children, 'Undo').isEnabled, isFalse);
      expect(
        find(project.children, 'Open').isEnabled,
        isFalse,
        reason: 'no source is wired, so Open would have nothing to read',
      );
      expect(find(project.children, 'Save').isEnabled, isFalse);

      controller.project.source = () async => null;
      controller.project.sink = (_) async => true;
      controller.translateNodes(<String>['a'], const Offset(10, 10));

      final after = find(
        menus.entriesFor(
          request(controller, const NodeMenuCanvasTarget(Offset.zero)),
        ),
        'Project',
      );
      expect(find(after.children, 'Undo').isEnabled, isTrue);
      expect(find(after.children, 'Open').isEnabled, isTrue);
      expect(find(after.children, 'Save').isEnabled, isTrue);
    });

    test('Add comment leaves a note where the click landed', () {
      final controller = boot();
      final entries = menus.entriesFor(
        request(controller, const NodeMenuCanvasTarget(Offset(240, 180))),
      );

      find(entries, 'Add comment').onSelected!();

      final note = controller.graph.comments.single;
      expect(note.position, const Offset(240, 180));
      expect(
        controller.selection.nodeIds,
        <String>{note.id},
        reason: 'a blank note is no use unselected — the caret goes into it',
      );
    });

    test('Add comment is offered with no prototypes at all', () {
      final controller = boot();
      expect(
        labels(
          menus.entriesFor(
            request(controller, const NodeMenuCanvasTarget(Offset.zero)),
          ),
        ),
        contains('Add comment'),
        reason: 'notes are the editor\'s own, not something a host declares',
      );
    });

    test('showProjectMenu: false drops the submenu', () {
      final controller = boot();
      expect(
        labels(
          const NodeEditorMenus(showProjectMenu: false).entriesFor(
            request(controller, const NodeMenuCanvasTarget(Offset.zero)),
          ),
        ),
        isNot(contains('Project')),
      );
    });
  });

  group('the build hook', () {
    test('sees the defaults and its result is what shows', () {
      final controller = boot();
      controller.selection.selectNode('a');
      List<NodeMenuEntry>? seen;

      final custom = NodeEditorMenus(
        build: (request, defaults) {
          seen = defaults;
          return <NodeMenuEntry>[
            ...defaults,
            const NodeMenuEntry(label: 'Mine'),
          ];
        },
      );

      final entries = custom.entriesFor(
        request(
          controller,
          NodeMenuNodeTarget(controller.graph.nodes['a']!, Offset.zero),
        ),
      );

      expect(labels(seen!), <String>['Cut', 'Copy', 'Delete', '---', 'Group']);
      expect(labels(entries).last, 'Mine');
    });

    test('returning nothing leaves nothing to open', () {
      final controller = boot();
      final custom = NodeEditorMenus(
        build: (request, defaults) => const <NodeMenuEntry>[],
      );

      expect(
        custom.entriesFor(
          request(controller, const NodeMenuCanvasTarget(Offset.zero)),
        ),
        isEmpty,
      );
    });

    test('a hook that empties a group takes its rule with it', () {
      final controller = boot();
      final custom = NodeEditorMenus(
        build: (request, defaults) => defaults
            .where((entry) => entry.isSeparator || entry.label == 'Paste')
            .toList(),
      );

      final entries = custom.entriesFor(
        request(controller, const NodeMenuCanvasTarget(Offset.zero)),
      );

      expect(labels(entries), <String>['Paste']);
    });
  });
}
