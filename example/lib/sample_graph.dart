import 'package:flutter/widgets.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

import 'prototype_nodes.dart';
import 'workflow_node.dart';

/// A small automation pipeline, wired up so the demo opens on something worth
/// looking at.
NodeGraph buildSampleGraph() {
  return NodeGraph(
    nodes: <GraphNode>[
      WorkflowNodes.trigger(
        id: 'trigger',
        position: const Offset(0, 160),
        title: 'Form submitted',
        subtitle: 'Fires whenever the contact form receives a new entry.',
      ),
      WorkflowNodes.action(
        id: 'enrich',
        position: const Offset(320, 168),
        title: 'Enrich contact',
        subtitle: 'Look the address up and attach company details.',
      ),
      WorkflowNodes.condition(
        id: 'score',
        position: const Offset(640, 140),
        title: 'Lead score',
        branches: <String>['High', 'Medium', 'Low'],
      ),
      WorkflowNodes.action(
        id: 'notify',
        position: const Offset(960, 40),
        title: 'Notify sales',
        subtitle: 'Post to the #leads channel and assign an owner.',
      ),
      WorkflowNodes.action(
        id: 'nurture',
        position: const Offset(960, 190),
        title: 'Add to nurture',
        subtitle: 'Drop into the six-week email sequence.',
      ),
      WorkflowNodes.form(
        id: 'compose',
        position: const Offset(1300, 20),
        title: 'Compose message',
        subject: 'Thanks for getting in touch',
        delayMinutes: 15,
      ),
      // These two arrive holding only their fields. Their ports — and the
      // fan-out's height — are derived by their prototypes when the controller
      // takes the document.
      PrototypeNodes.fanOut(
        id: 'route',
        position: const Offset(1300, 300),
        title: 'Route reply',
      ),
      PrototypeNodes.format(
        id: 'greeting',
        position: const Offset(1640, 480),
        title: 'Greeting',
      ),
      // A format string with no placeholders is a constant: no argument ports,
      // nothing to pull, one value out. It is what feeds the greeting's first
      // slot, and the shortest demonstration of a data node in the demo.
      PrototypeNodes.format(
        id: 'name',
        position: const Offset(1300, 520),
        title: 'Recipient',
        format: 'Mr. Allen',
      ),
      // Where the fan-out's first exit leads, and where the greeting ends up.
      // The control wire decides *that* it runs; the data wire decides what it
      // has to say.
      WorkflowNodes.output(
        id: 'deliver',
        position: const Offset(1980, 300),
        title: 'Send reply',
        subtitle: 'Post the composed greeting back to the contact.',
      ),
      WorkflowNodes.output(
        id: 'archive',
        position: const Offset(960, 330),
        title: 'Archive',
        subtitle: 'Store the record and stop.',
      ),
      // A note is an ordinary node of a reserved type, so it goes in the
      // document alongside the rest and needs nothing else set up.
      NodeComment.create(
        id: 'note',
        position: const Offset(620, 430),
        text:
            'Low scores skip the reply entirely — that branch is deliberate, '
            'not a gap.',
      ),
    ],
    groups: <NodeGroup>[
      // A frame owns no geometry: it is drawn around whatever these four
      // nodes turn out to occupy, and follows them when they move.
      NodeGroup(
        id: 'reply',
        name: 'Composing the reply',
        color: NodeGroup.palette.first,
        nodeIds: <String>{'compose', 'route', 'greeting', 'name'},
      ),
    ],
    connections: <NodeConnection>[
      const NodeConnection(
        id: 'c1',
        from: PortRef('trigger', 'out'),
        to: PortRef('enrich', 'in'),
      ),
      const NodeConnection(
        id: 'c2',
        from: PortRef('enrich', 'out'),
        to: PortRef('score', 'in'),
      ),
      const NodeConnection(
        id: 'c3',
        type: branchLinkType,
        from: PortRef('score', 'branch_0'),
        to: PortRef('notify', 'in'),
        label: 'High',
      ),
      const NodeConnection(
        id: 'c4',
        type: branchLinkType,
        from: PortRef('score', 'branch_1'),
        to: PortRef('nurture', 'in'),
        label: 'Medium',
      ),
      const NodeConnection(
        id: 'c5',
        type: branchLinkType,
        from: PortRef('score', 'branch_2'),
        to: PortRef('archive', 'in'),
        label: 'Low',
      ),
      const NodeConnection(
        id: 'c6',
        from: PortRef('notify', 'out'),
        to: PortRef('compose', 'in'),
      ),
      const NodeConnection(
        id: 'c7',
        from: PortRef('compose', 'out'),
        to: PortRef('archive', 'in'),
      ),
      const NodeConnection(
        id: 'c8',
        from: PortRef('nurture', 'out'),
        to: PortRef('route', 'in'),
      ),
      // Lands on a port that does not exist yet: 'exit_0' appears when the
      // fan-out is resolved, and wiring it is what makes 'exit_1' follow.
      const NodeConnection(
        id: 'c9',
        type: exitLinkType,
        from: PortRef('route', 'exit_0'),
        to: PortRef('deliver', 'in'),
      ),
      // The one data wire in the demo. Nothing pushes a value along it: the
      // archive node reads it when the flow reaches the archive, and that read
      // is what makes the format node compute at all.
      const NodeConnection(
        id: 'c10',
        from: PortRef('greeting', 'out'),
        to: PortRef('deliver', 'value'),
      ),
      // Lands on a generated argument port, so it goes when the placeholder
      // that produced that port goes.
      const NodeConnection(
        id: 'c11',
        from: PortRef('name', 'out'),
        to: PortRef('greeting', 'arg_0'),
      ),
    ],
  );
}

/// A generated grid of wired-up nodes, for exercising culling, the spatial
/// index and the connection cache at a scale no hand-authored sample reaches.
///
/// Heights are declared rather than measured, so the graph is fully indexed on
/// the first frame instead of settling over several.
NodeGraph buildStressGraph(int count) {
  const columns = 24;
  const spacing = Offset(320, 190);

  final nodes = <GraphNode>[];
  final connections = <NodeConnection>[];

  for (var i = 0; i < count; i++) {
    final position = Offset(
      (i % columns) * spacing.dx,
      (i ~/ columns) * spacing.dy,
    );
    nodes.add(
      GraphNode(
        id: 'n$i',
        type: WorkflowNodeType.action.name,
        position: position,
        width: CardMetrics.width,
        height: 74,
        data: <String, Object?>{
          'title': 'Step $i',
          'subtitle': 'Generated node.',
        },
        ports: const <NodePort>[
          NodePort.input(id: 'in'),
          NodePort.output(id: 'out'),
        ],
      ),
    );

    if (i % columns != 0) {
      connections.add(
        NodeConnection(
          id: 'c$i',
          from: PortRef('n${i - 1}', 'out'),
          to: PortRef('n$i', 'in'),
        ),
      );
    }
  }

  return NodeGraph(nodes: nodes, connections: connections);
}
