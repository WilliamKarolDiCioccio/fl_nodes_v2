import 'package:flutter/material.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

import 'workflow_node.dart';

/// The two nodes in this demo whose shape is derived rather than authored.
///
/// Both are ordinary [NodePrototype]s: given what the node's fields say and how
/// it is wired right now, they return the ports it should have. Nothing else in
/// the demo knows they are special — the card, the inspector and the painters
/// all see a perfectly ordinary [GraphNode].

/// `{0}`, `{1}` and friends in a format string.
final RegExp _placeholder = RegExp(r'\{(\d+)\}');

/// The distinct placeholder indices in [text], in ascending order.
///
/// A set, so `"{0} and {0} again"` is one argument, and sorted, so the result
/// depends only on the string — never on the order things were typed.
List<int> formatSlots(String text) => <int>{
  for (final match in _placeholder.allMatches(text)) int.parse(match.group(1)!),
}.toList()..sort();

/// Namespace for the per-argument literal values.
///
/// The prototype manages every key beneath it, which is how a value whose slot
/// has gone from the format string gets cleaned up with it.
const String argKeyPrefix = 'arg.';
const String _exitIdPrefix = 'exit_';

/// The value key for the argument filling slot [index].
String argKey(int index) => '$argKeyPrefix$index';

/// A `print()`-style node: one input per placeholder in its format string.
///
/// Type `{1}` into the field and a second input appears; delete it and the port
/// goes, taking any wire that landed on it with it, in one undo step.
final NodePrototype formatPrototype = NodePrototype(
  type: 'format',
  label: 'Format',
  icon: Icons.data_object_rounded,
  category: 'Data',
  defaultWidth: CardMetrics.width,
  description:
      'Builds a string from a template and its arguments.\n\n'
      'Type a placeholder like {0} into the format field and an input '
      'appears for it; delete the placeholder and the input goes, taking '
      'any wire that landed on it with it.\n\n'
      'It declares no control ports, so it is a pure data node: nothing '
      'runs it, and it computes only when something downstream reads it.',
  fields: <FieldFamily>[
    const StaticFieldFamily(
      id: 'text',
      fields: <NodeField>[
        NodeField(
          key: 'format',
          label: 'Format',
          defaultValue: 'Hello, {0}. {1}!',
        ),
      ],
    ),
    // The fields are generated too, not just the ports: one literal per slot,
    // used whenever that input is not wired to anything.
    DynamicFieldFamily(
      id: 'args',
      keyPrefix: argKeyPrefix,
      build: (context) => <NodeField>[
        for (final slot in formatSlots(context.fieldOr<String>('format', '')))
          NodeField(key: argKey(slot), label: '{$slot}', defaultValue: ''),
      ],
    ),
  ],
  ports: <PortFamily>[
    DynamicPortFamily(
      id: 'result',
      build: (context) {
        final args = formatSlots(context.fieldOr<String>('format', '')).length;
        return <NodePort>[
          NodePort.output(
            id: 'out',
            dataType: 'string',
            anchor: Offset(1, CardMetrics.formatHeaderAnchorY(args)),
          ),
        ];
      },
    ),
    DynamicPortFamily(
      id: 'args',
      build: (context) {
        final slots = formatSlots(context.fieldOr<String>('format', ''));
        return <NodePort>[
          for (var i = 0; i < slots.length; i++)
            NodePort.input(
              id: 'arg_${slots[i]}',
              label: '{${slots[i]}}',
              dataType: 'string',
              // One input per row, pinned to that row's centre — the same
              // trick the condition card uses, except the row count now
              // follows the text instead of being fixed at construction.
              anchor: Offset(0, CardMetrics.formatArgAnchorY(i, slots.length)),
            ),
        ];
      },
    ),
  ],
  resolveHeight: (context) =>
      CardMetrics.formatHeight(context.portsOf('args').length),
  // No control ports anywhere on this node, which is what makes it a pure data
  // node: it is evaluated when something asks for its output, not when the
  // flow arrives. Each slot takes the value wired to it, or the literal in the
  // field beside it when nothing is.
  onExecute: (context) async {
    var text = context.fieldOr<String>('format', '');
    for (final slot in formatSlots(text)) {
      final value =
          context.input<String>('arg_$slot') ??
          context.fieldOr<String>(argKey(slot), '');
      text = text.replaceAll('{$slot}', value);
    }
    context.emit('out', text);
  },
);

/// How many exits a fan-out node should have: every wired one, plus a free one.
int _exitCount(NodeResolutionContext context) =>
    context
        .portsOf('exits')
        .where((port) => context.isConnected(port.id))
        .length +
    1;

/// A node that grows an exit each time its last free one is wired.
///
/// The rule is a pure function of link state, which is what makes it settle:
/// resolving it twice in a row produces the same ports the second time.
final NodePrototype fanOutPrototype = NodePrototype(
  type: 'fanOut',
  label: 'Fan out',
  icon: Icons.shuffle_rounded,
  category: 'Flow',
  defaultWidth: CardMetrics.width,
  description:
      'Splits the flow into as many exits as you wire.\n\n'
      'There is always one free exit at the bottom. Wire it and another '
      'appears; unwire one in the middle and the rest renumber, captions '
      'and all.',
  ports: <PortFamily>[
    DynamicPortFamily(
      id: 'entry',
      build: (context) => <NodePort>[
        NodePort.input(
          id: 'in',
          kind: PortKind.control,
          anchor: Offset(0, CardMetrics.headerRowAnchorY(_exitCount(context))),
        ),
      ],
    ),
    DynamicPortFamily(
      id: 'exits',
      build: (context) {
        final kept = <NodePort>[
          for (final port in context.currentPorts)
            if (context.isConnected(port.id)) port,
        ];

        // One past the highest index still in use. Numbering by list length
        // would hand out an id that is already taken as soon as an exit in the
        // middle is unwired, and drawing from a counter would never repeat at
        // all — the node would keep re-deriving and never settle.
        var highest = -1;
        for (final port in kept) {
          final index =
              int.tryParse(port.id.substring(_exitIdPrefix.length)) ?? -1;
          if (index > highest) highest = index;
        }

        final total = kept.length + 1;
        return <NodePort>[
          for (var i = 0; i < kept.length; i++)
            kept[i].copyWith(
              anchor: Offset(1, CardMetrics.rowAnchorY(i, total)),
            ),
          NodePort.output(
            id: '$_exitIdPrefix${highest + 1}',
            kind: PortKind.control,
            label: 'Out ${highest + 1}',
            anchor: Offset(1, CardMetrics.rowAnchorY(kept.length, total)),
            linkType: exitLinkType,
          ),
        ];
      },
    ),
  ],
  resolveHeight: (context) =>
      CardMetrics.rowsHeight(context.portsOf('exits').length),
  // The demo has no routing rule, so it always takes the first exit. The point
  // is that choosing one is the node's business, not the runner's.
  onExecute: (context) async {
    final exits = context.node.outputs
        .where((port) => port.kind == PortKind.control)
        .toList(growable: false);
    if (exits.isNotEmpty) context.flow(exits.first.id);
  },
);

/// A condition with no rule to evaluate, so it takes every branch.
///
/// A real host picks one. Taking all of them shows the thing worth seeing
/// here: control flow is a pulse, so a node several branches converge on runs
/// once for each of them.
final NodePrototype conditionPrototype = NodePrototype(
  type: 'condition',
  label: 'Condition',
  icon: Icons.call_split_rounded,
  category: 'Flow',
  defaultWidth: CardMetrics.width,
  description:
      'Routes the run down exactly one of its branches.\n\n'
      'Each branch has its own output port and its own wire caption — tap '
      'the text on a wire to name the choice it stands for. This demo '
      'always takes the first branch; a real one would evaluate a rule.',
  // Its branches were authored by hand until the Create menu needed to build
  // one from nothing. They are derived from the `branches` field now, which
  // also means renaming a branch renames its port and its wire caption.
  fields: const <FieldFamily>[
    StaticFieldFamily(
      id: 'copy',
      fields: <NodeField>[
        NodeField(key: 'title', label: 'Title', defaultValue: 'New condition'),
        NodeField(
          key: 'branches',
          label: 'Branches',
          defaultValue: <String>['Yes', 'No'],
        ),
      ],
    ),
  ],
  ports: <PortFamily>[
    DynamicPortFamily(
      id: 'flow',
      build: (context) {
        final branches = conditionBranches(context.node);
        return <NodePort>[
          NodePort.input(
            id: 'in',
            kind: PortKind.control,
            anchor: Offset(0, CardMetrics.headerAnchorY(branches.length)),
          ),
          for (var i = 0; i < branches.length; i++)
            NodePort.output(
              id: 'branch_$i',
              kind: PortKind.control,
              label: branches[i],
              // One output per row, pinned to that row's centre.
              anchor: Offset(1, CardMetrics.branchAnchorY(i, branches.length)),
              // Wires leaving a branch are the ones worth naming.
              linkType: branchLinkType,
            ),
        ];
      },
    ),
  ],
  resolveHeight: (context) =>
      CardMetrics.conditionHeight(conditionBranches(context.node).length),
  onExecute: (context) async => context.flowAll(<String>[
    for (final port in context.node.outputs)
      if (port.kind == PortKind.control) port.id,
  ]),
);

/// The branch names on a condition node, never empty.
///
/// A condition with no branches would have no exits and no way to grow one,
/// so an empty list falls back to a single unnamed branch rather than to a
/// dead end.
List<String> conditionBranches(GraphNode node) {
  final raw = node.data['branches'];
  final names = <String>[if (raw is List) ...raw.map((entry) => '$entry')];
  return names.isEmpty ? const <String>['Branch'] : names;
}

/// The prototypes this demo normalises its document against.
/// The four nodes whose shape is authored rather than derived.
///
/// They were plain [GraphNode]s until the editor grew a "Create" menu, which
/// reads the registry: a prototype is how a node type says what it is called,
/// what it looks like in a list, and what it is for. Declaring their ports and
/// fields here as well is what lets the menu build one from nothing — and it
/// costs the nodes already on the canvas nothing, because a family that
/// declares exactly the ports a node already has adopts them rather than
/// replacing them.
final NodePrototype triggerPrototype = NodePrototype(
  type: 'trigger',
  label: 'Trigger',
  icon: Icons.bolt_rounded,
  category: 'Flow',
  defaultWidth: CardMetrics.width,
  description:
      'Where a run starts.\n\n'
      'It has no control input, which is exactly what makes it an entry '
      'point: the runner takes every node with an outgoing control port and '
      'nothing feeding it as a root.',
  fields: const <FieldFamily>[
    StaticFieldFamily(
      id: 'copy',
      fields: <NodeField>[
        NodeField(key: 'title', label: 'Title', defaultValue: 'New trigger'),
        NodeField(
          key: 'subtitle',
          label: 'Subtitle',
          defaultValue: 'Describe what starts this run.',
        ),
      ],
    ),
  ],
  ports: const <PortFamily>[
    StaticPortFamily(
      id: 'flow',
      ports: <NodePort>[NodePort.output(id: 'out', kind: PortKind.control)],
    ),
  ],
);

final NodePrototype actionPrototype = NodePrototype(
  type: 'action',
  label: 'Action',
  icon: Icons.play_arrow_rounded,
  category: 'Flow',
  defaultWidth: CardMetrics.width,
  description:
      'A step that does something and passes the flow on.\n\n'
      'It has no executor, and a node without one forwards the flow through '
      'its single control output — which is what most of a workflow wants.',
  fields: const <FieldFamily>[
    StaticFieldFamily(
      id: 'copy',
      fields: <NodeField>[
        NodeField(key: 'title', label: 'Title', defaultValue: 'New action'),
        NodeField(
          key: 'subtitle',
          label: 'Subtitle',
          defaultValue: 'Describe what this step does.',
        ),
      ],
    ),
  ],
  ports: const <PortFamily>[
    StaticPortFamily(
      id: 'flow',
      ports: <NodePort>[
        NodePort.input(id: 'in', kind: PortKind.control),
        NodePort.output(id: 'out', kind: PortKind.control),
      ],
    ),
  ],
);

final NodePrototype outputPrototype = NodePrototype(
  type: 'output',
  label: 'Output',
  icon: Icons.check_circle_outline_rounded,
  category: 'Flow',
  defaultWidth: CardMetrics.width,
  description:
      'Where a run ends, and the one hand-authored node that reads a value.\n\n'
      'Its control input accepts any number of wires, so every branch can '
      'finish here. Whatever reaches its "value" input is what it would '
      'print — wire a Format node to it and run the graph to see.',
  fields: const <FieldFamily>[
    StaticFieldFamily(
      id: 'copy',
      fields: <NodeField>[
        NodeField(key: 'title', label: 'Title', defaultValue: 'New output'),
        NodeField(
          key: 'subtitle',
          label: 'Subtitle',
          defaultValue: 'Describe how this run ends.',
        ),
      ],
    ),
  ],
  ports: const <PortFamily>[
    StaticPortFamily(
      id: 'flow',
      ports: <NodePort>[
        NodePort.input(id: 'in', kind: PortKind.control, maxConnections: null),
        NodePort.input(id: 'value', label: 'value', dataType: 'string'),
      ],
    ),
  ],
);

final NodePrototype formPrototype = NodePrototype(
  type: 'form',
  label: 'Form',
  icon: Icons.edit_note_rounded,
  category: 'Content',
  defaultWidth: 272,
  description:
      'A node whose body is an ordinary Flutter form.\n\n'
      'Text fields, switches, sliders and a colour menu, all inside the '
      'card, all keeping their focus and their state while the node is '
      'dragged and reselected. It declares no height, so it grows as its '
      'text wraps and the ports follow the measured size.',
  fields: const <FieldFamily>[
    StaticFieldFamily(
      id: 'copy',
      fields: <NodeField>[
        NodeField(key: 'title', label: 'Title', defaultValue: 'Compose email'),
        NodeField(key: 'subject', label: 'Subject', defaultValue: ''),
        NodeField(
          key: 'sendAsHtml',
          label: 'Send as HTML',
          defaultValue: false,
        ),
        NodeField(key: 'delayMinutes', label: 'Delay', defaultValue: 0.0),
        NodeField(key: 'labelColor', defaultValue: 0xFF6E97F0),
      ],
    ),
  ],
  ports: const <PortFamily>[
    StaticPortFamily(
      id: 'flow',
      ports: <NodePort>[
        NodePort.input(id: 'in', kind: PortKind.control),
        NodePort.output(id: 'out', kind: PortKind.control),
      ],
    ),
  ],
);

final NodePrototypeRegistry workflowPrototypes = NodePrototypeRegistry(
  <NodePrototype>[
    triggerPrototype,
    actionPrototype,
    conditionPrototype,
    formPrototype,
    outputPrototype,
    formatPrototype,
    fanOutPrototype,
  ],
  links: <LinkPrototype>[
    // Two link kinds, one of each sort, because a caption is either the app
    // user's or the prototype's and never both.
    //
    // A branch names a choice, which is content nobody can compute.
    const LinkPrototype(
      type: branchLinkType,
      label: EditableLinkLabel(editorTitle: 'Branch label'),
    ),
    // An exit is named after the port it leaves, so its caption renumbers
    // itself when an exit in the middle is unwired. Nothing is stored: the
    // caption is worked out fresh whenever the geometry is.
    LinkPrototype(
      type: exitLinkType,
      label: DerivedLinkLabel(build: (context) => context.fromPort?.label),
    ),
  ],
);

/// Seeds for the two derived nodes.
///
/// Note how little there is: no ports, no height. Adding one of these to a
/// controller resolves it, and the prototype fills the rest in — which is also
/// why a document only has to persist the fields.
abstract final class PrototypeNodes {
  static GraphNode format({
    required String id,
    required Offset position,
    String title = 'Format',
    String format = 'Hello, {0}. {1}!',
  }) => GraphNode(
    id: id,
    type: WorkflowNodeType.format.name,
    position: position,
    width: CardMetrics.width,
    data: <String, Object?>{'title': title, 'format': format},
  );

  static GraphNode fanOut({
    required String id,
    required Offset position,
    String title = 'Pick one',
  }) => GraphNode(
    id: id,
    type: WorkflowNodeType.fanOut.name,
    position: position,
    width: CardMetrics.width,
    data: <String, Object?>{'title': title},
  );
}
