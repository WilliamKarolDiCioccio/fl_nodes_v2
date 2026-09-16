import 'package:flutter/foundation.dart';

/// What an edit is doing to the graph.
///
/// Coarse on purpose. A host asking to be told about edits wants to know
/// whether something *went away* or merely moved; it does not want a case per
/// method, which would be a list to extend every time the controller grew one.
enum GraphEditKind {
  /// The whole document was swapped — a load, or a normalisation pass.
  replace,

  addNodes,

  /// Something about a node other than its position changed — a field, its
  /// size, its ports, or its `metadata`.
  updateNodes,
  removeNodes,

  /// Positions only. Frequent, and the one kind a host almost always wants to
  /// ignore.
  moveNodes,

  connect,
  disconnect,

  /// A connection's caption changed; the wire itself did not.
  labelConnection,

  /// A group was made, disbanded, renamed or recoloured.
  group,

  /// A note's text changed.
  comment,
}

/// One change to the graph: what kind, and what it touched.
///
/// Handed to [NodeEditorController.guard] before it lands and to
/// [NodeEditorController.onEdit] after, so a host can refuse an edit or
/// react to one without having to diff two graphs to find out what happened.
@immutable
class GraphEdit {
  const GraphEdit({
    required this.kind,
    this.nodeIds = const <String>{},
    this.connectionIds = const <String>{},
    this.groupIds = const <String>{},
  });

  final GraphEditKind kind;

  /// The nodes this edit is about. For [GraphEditKind.connect] and
  /// [GraphEditKind.disconnect] these are the wire's two ends, which is what
  /// a host reasoning about a *node* wants; the wires themselves are in
  /// [connectionIds].
  final Set<String> nodeIds;

  final Set<String> connectionIds;

  final Set<String> groupIds;

  /// Whether this edit removes [nodeId] from the graph.
  ///
  /// The question a host most often has, and the one it is easiest to get
  /// subtly wrong: a node also goes away when the document is replaced
  /// wholesale, and a guard that only watched [GraphEditKind.removeNodes]
  /// would not see it.
  bool removes(String nodeId) =>
      kind == GraphEditKind.removeNodes && nodeIds.contains(nodeId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphEdit &&
          other.kind == kind &&
          setEquals(other.nodeIds, nodeIds) &&
          setEquals(other.connectionIds, connectionIds) &&
          setEquals(other.groupIds, groupIds);

  @override
  int get hashCode => Object.hash(
    kind,
    Object.hashAllUnordered(nodeIds),
    Object.hashAllUnordered(connectionIds),
    Object.hashAllUnordered(groupIds),
  );

  @override
  String toString() =>
      'GraphEdit(${kind.name}${nodeIds.isEmpty ? '' : ' nodes:$nodeIds'}'
      '${connectionIds.isEmpty ? '' : ' wires:$connectionIds'}'
      '${groupIds.isEmpty ? '' : ' groups:$groupIds'})';
}

/// Asked before an edit lands. Returning false abandons it.
///
/// **Synchronous, and that is the contract.** An edit is a frame's work, and
/// the controller cannot hold a graph half-changed while a dialog is open. A
/// host that needs to ask a question refuses here and re-issues the edit once
/// it has an answer — which is also why refusing is silent: the host already
/// knows it refused, and the editor has nothing to add.
typedef GraphEditGuard = bool Function(GraphEdit edit);

/// Told after an edit landed.
///
/// [ChangeNotifier] already says *that* the graph changed; this says **what**
/// changed, which is the difference between a host diffing two graphs and a
/// host reading one field.
typedef GraphEditListener = void Function(GraphEdit edit);
