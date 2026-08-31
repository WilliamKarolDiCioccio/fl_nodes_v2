import 'package:flutter/material.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

import 'workflow_node.dart';
import 'workflow_node_card.dart';

/// Side panel reflecting the editor's selection.
///
/// It only listens to the controller — which is the point: the canvas and the
/// panel stay in sync without either knowing about the other.
class InspectorPanel extends StatelessWidget {
  const InspectorPanel({super.key, required this.controller});

  final NodeEditorController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 268,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final nodeIds = controller.selection.nodeIds;
    final connectionIds = controller.selection.connectionIds;

    if (nodeIds.isEmpty && connectionIds.isEmpty) {
      return const _EmptyState();
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        if (nodeIds.length > 1)
          _Section(
            title: 'Selection',
            children: <Widget>[Text('${nodeIds.length} nodes selected')],
          )
        else
          for (final id in nodeIds)
            if (controller.graph.node(id) case final GraphNode node)
              _NodeDetails(node: node, controller: controller),
        for (final id in connectionIds)
          if (controller.graph.connection(id) case final NodeConnection link)
            _Section(
              title: 'Connection',
              children: <Widget>[
                _Row('From', '${link.from.nodeId}.${link.from.portId}'),
                _Row('To', '${link.to.nodeId}.${link.to.portId}'),
                if (link.label != null) _Row('Label', link.label!),
              ],
            ),
      ],
    );
  }
}

class _NodeDetails extends StatelessWidget {
  const _NodeDetails({required this.node, required this.controller});

  final GraphNode node;
  final NodeEditorController controller;

  @override
  Widget build(BuildContext context) {
    // A note has no type, no ports and no fields of the demo's own — the panel
    // would otherwise report it as an "Untitled" action with an empty
    // everything. This is the one case a host has to write for comments, and
    // only because it looks at nodes itself.
    if (NodeComment.isComment(node)) return _CommentDetails(node: node);

    final style = WorkflowStyle.of(node.workflowType);
    final size = controller.layout.sizeOf(node);
    final links = controller.graph.connectionsOf(node.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(WorkflowStyle.iconOf(node.type), size: 18, color: style.color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                node.title,
                style: Theme.of(context).textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Node',
          children: <Widget>[
            _Row('Id', node.id),
            _Row('Type', WorkflowStyle.labelOf(node.type)),
            _Row(
              'Position',
              '${node.position.dx.round()}, ${node.position.dy.round()}',
            ),
            _Row(
              'Size',
              '${size.width.round()} × ${size.height.round()}'
                  '${node.hasIntrinsicHeight ? '  (measured)' : ''}',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Ports',
          children: <Widget>[
            for (final port in node.ports)
              _Row(
                port.isInput ? 'in' : 'out',
                '${port.id}${port.label == null ? '' : '  ·  ${port.label}'}',
              ),
          ],
        ),
        if (node.data.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          // Whatever the node body writes shows up here immediately, because
          // both read the same graph through the controller.
          _Section(
            title: 'Data',
            children: <Widget>[
              for (final entry in node.data.entries)
                _Row(entry.key, _describe(entry.value)),
            ],
          ),
        ],
        const SizedBox(height: 16),
        _Section(
          title: 'Connections (${links.length})',
          children: <Widget>[
            if (links.isEmpty)
              const Text('None')
            else
              for (final link in links)
                _Row(
                  link.from.nodeId == node.id ? '→' : '←',
                  link.from.nodeId == node.id
                      ? link.to.nodeId
                      : link.from.nodeId,
                ),
          ],
        ),
      ],
    );
  }
}

class _CommentDetails extends StatelessWidget {
  const _CommentDetails({required this.node});

  final GraphNode node;

  @override
  Widget build(BuildContext context) {
    final text = NodeComment.textOf(node);
    return _Section(
      title: 'Comment',
      children: <Widget>[
        _Row('Id', node.id),
        _Row(
          'Position',
          '${node.position.dx.round()}, ${node.position.dy.round()}',
        ),
        const SizedBox(height: 8),
        Text(
          text.isEmpty ? 'Empty' : text,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

String _describe(Object? value) {
  if (value is double) return value.toStringAsFixed(1);
  if (value is List) return value.join(', ');
  if (value is String) return value.isEmpty ? '—' : value;
  return '$value';
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 0.8,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
        const SizedBox(height: 6),
        ...children,
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  static const List<String> _hints = <String>[
    'Drag the canvas to sweep a selection; shift adds to it.',
    'Middle-drag or hold space to pan. Scroll to zoom.',
    'Drag a node to move it — no need to select it first.',
    'Drag a port to wire two nodes together.',
    'Right-click a node, a port, a wire or the canvas for a menu.',
    'Double-click a node to rename it.',
    'Del removes the selection, Ctrl+Z undoes.',
  ];

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    // Scrollable: the panel has a fixed width but shares the window's height
    // with the canvas, and there is no guarantee the hints fit.
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text('Nothing selected', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 16),
        for (final hint in _hints)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('·  ', style: TextStyle(color: outline)),
                Expanded(
                  child: Text(
                    hint,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: outline),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
