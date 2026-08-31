import 'package:flutter/foundation.dart';

import '../model/graph_node.dart';
import '../model/node_connection.dart';
import '../model/node_graph.dart';
import '../model/node_port.dart';
import '../model/port_ref.dart';
import 'node_prototype.dart';

/// Builds one port family's ports from the node's current state.
///
/// The builder must be **deterministic and idempotent**: called twice on the
/// same state it has to return an equal list, or the node never settles and
/// resolution gives up. Two ways that goes wrong in practice:
///
/// * Generating ids from a counter. `controller.nextId()` returns something new
///   every call, so the port list never repeats. Derive ids from the state
///   instead — one past the highest index in use is both stable and free of
///   collisions after a port in the middle disappears.
/// * Putting a freshly allocated object in [NodePort.data]. Ports compare their
///   payload with `==`, so a new instance each pass reads as a changed port
///   forever. Use a const value, or one that defines equality.
typedef PortFamilyBuilder =
    List<NodePort> Function(NodeResolutionContext context);

/// Builds one field family's declarations from the node's current state.
///
/// Subject to the same determinism rule as [PortFamilyBuilder].
typedef FieldFamilyBuilder =
    List<NodeField> Function(NodeResolutionContext context);

/// Returns the node's declared height, or null to size it to its content.
typedef NodeHeightResolver = double? Function(NodeResolutionContext context);

/// Carries field values across an iteration of the prototype.
typedef NodeFieldMerge =
    Map<String, Object?> Function(NodeFieldMergeContext context);

/// Decides what happens to connections whose port has just disappeared.
typedef PortRemovalHandler = NodeGraph Function(PortRemoval removal);

/// Everything a builder may look at while deciding a node's shape.
///
/// Reads are deliberately local — the node's own fields and its own links. The
/// whole [graph] is here for the rare rule that needs it, but resolution only
/// re-runs for nodes an edit actually touched, so a rule reaching for a distant
/// node will go stale when that node changes. `revalidate()` is the way out.
@immutable
class NodeResolutionContext {
  const NodeResolutionContext({
    required this.graph,
    required this.node,
    required this.pass,
    required Map<String, int> connectionCounts,
    this.family,
  }) : _counts = connectionCounts;

  final NodeGraph graph;

  /// The node as this pass found it.
  ///
  /// [GraphNode.data] already holds the merged field values, so a default
  /// seeded this pass is visible here; [GraphNode.ports] still holds the
  /// previous pass's output, which is what makes a family able to grow from
  /// what it already has.
  final GraphNode node;

  /// The family being resolved, or null while resolving fields or height.
  final String? family;

  /// 0 on the first pass, incremented each time the node is re-derived.
  final int pass;

  final Map<String, int> _counts;

  String get nodeId => node.id;

  Map<String, Object?> get fields => node.data;

  /// The value at [key] when it is a [T], else null.
  T? field<T>(String key) {
    final value = node.data[key];
    return value is T ? value : null;
  }

  T fieldOr<T>(String key, T fallback) => field<T>(key) ?? fallback;

  /// This family's ports as the node currently has them, in order.
  ///
  /// Empty on a node that was just added, which is what lets `addNode` double
  /// as instantiation.
  List<NodePort> get currentPorts {
    final id = family;
    return id == null ? const <NodePort>[] : portsOf(id);
  }

  /// Another family's ports, for a rule that mirrors one family onto another.
  List<NodePort> portsOf(String family) => <NodePort>[
    for (final port in node.ports)
      if (port.family == family) port,
  ];

  /// The host's own ports — the ones carrying no family stamp.
  ///
  /// Resolution never touches these, which is what lets a prototyped node keep
  /// hand-authored ports alongside generated ones. A port stamped with a family
  /// the prototype no longer declares is *not* foreign: it is left over from an
  /// earlier version of the rule, and resolution retires it.
  List<NodePort> get foreignPorts => <NodePort>[
    for (final port in node.ports)
      if (port.family == null) port,
  ];

  int connectionCount(String portId) => _counts[portId] ?? 0;

  bool isConnected(String portId) => connectionCount(portId) > 0;

  Iterable<NodeConnection> connectionsAt(String portId) =>
      graph.connectionsAt(PortRef(node.id, portId));

  /// The same context aimed at a different family.
  NodeResolutionContext forFamily(String? family) => NodeResolutionContext(
    graph: graph,
    node: node,
    pass: pass,
    connectionCounts: _counts,
    family: family,
  );

  /// The same context over an updated node, keeping the connection counts.
  NodeResolutionContext forNode(GraphNode node) => NodeResolutionContext(
    graph: graph,
    node: node,
    pass: pass,
    connectionCounts: _counts,
    family: family,
  );
}

/// What a [NodeFieldMerge] sees when carrying values across an iteration.
@immutable
class NodeFieldMergeContext {
  const NodeFieldMergeContext({
    required this.node,
    required this.declared,
    required this.managedPrefixes,
    required this.pass,
  });

  /// The node before the merge; its data holds the previous values.
  final GraphNode node;

  /// The fields declared this pass, in family then builder order.
  final List<NodeField> declared;

  /// The [DynamicFieldFamily.keyPrefix] of every dynamic field family on the
  /// prototype — the keys it is allowed to drop.
  final Set<String> managedPrefixes;

  final int pass;

  Map<String, Object?> get previous => node.data;

  Set<String> get declaredKeys => <String>{
    for (final field in declared) field.key,
  };

  /// Whether [key] falls in a namespace the prototype manages.
  bool manages(String key) =>
      managedPrefixes.any((prefix) => key.startsWith(prefix));
}

/// Ready-made inheritance policies.
///
/// Pass a [NodeFieldMerge] of your own to [NodePrototype.inheritFields] for
/// anything else — renumbering values when a field is inserted in the middle,
/// for instance, which no general rule can guess at.
abstract final class NodeFields {
  /// Keeps every surviving value, seeds a default for each newly declared
  /// field, and drops managed keys whose field is gone.
  ///
  /// Values outside a managed prefix are never touched, so whatever else the
  /// host keeps in `data` — a title, a colour — survives untouched.
  static Map<String, Object?> seedAndPrune(NodeFieldMergeContext context) {
    final declared = context.declaredKeys;
    final next = <String, Object?>{};
    for (final entry in context.previous.entries) {
      if (context.manages(entry.key) && !declared.contains(entry.key)) continue;
      next[entry.key] = entry.value;
    }
    for (final field in context.declared) {
      if (!next.containsKey(field.key)) next[field.key] = field.defaultValue;
    }
    return next;
  }

  /// Like [seedAndPrune], but never drops anything.
  static Map<String, Object?> seedOnly(NodeFieldMergeContext context) {
    final next = Map<String, Object?>.of(context.previous);
    for (final field in context.declared) {
      if (!next.containsKey(field.key)) next[field.key] = field.defaultValue;
    }
    return next;
  }
}

/// A node's ports changed and these connections referenced the ones that went.
@immutable
class PortRemoval {
  const PortRemoval({
    required this.graph,
    required this.node,
    required this.removed,
    required this.affected,
  });

  /// The graph with [node] already rewritten.
  final NodeGraph graph;

  final GraphNode node;

  /// The vanished ports, with their labels, anchors and data intact — enough
  /// to decide where a connection ought to go instead.
  final List<NodePort> removed;

  final List<NodeConnection> affected;
}

/// Ready-made policies for connections left behind by a vanished port.
abstract final class NodePortRemoval {
  /// Drops every affected connection.
  static NodeGraph dropConnections(PortRemoval removal) =>
      removal.graph.removeConnections(removal.affected.map((c) => c.id));

  /// Leaves them alone.
  ///
  /// Resolution still sweeps up anything genuinely dangling afterwards, so this
  /// is only useful for a handler that rewires in a later step.
  static NodeGraph keep(PortRemoval removal) => removal.graph;
}
