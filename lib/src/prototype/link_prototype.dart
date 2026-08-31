import 'package:flutter/foundation.dart';

import '../model/graph_node.dart';
import '../model/node_connection.dart';
import '../model/node_graph.dart';
import '../model/node_port.dart';

/// Builds a link's caption from the connection and the graph around it.
///
/// Unlike a port family builder this is not iterated to a fixed point — a
/// derived caption is computed for display, never written back — so it has no
/// convergence requirement. It is called when connection geometry is rebuilt,
/// so keep it cheap and free of side effects.
typedef LinkLabelBuilder = String? Function(LinkResolutionContext context);

/// What a [LinkLabelBuilder] may look at.
@immutable
class LinkResolutionContext {
  const LinkResolutionContext({required this.graph, required this.connection});

  final NodeGraph graph;
  final NodeConnection connection;

  GraphNode? get fromNode => graph.node(connection.from.nodeId);
  GraphNode? get toNode => graph.node(connection.to.nodeId);

  NodePort? get fromPort => fromNode?.portById(connection.from.portId);
  NodePort? get toPort => toNode?.portById(connection.to.portId);
}

/// Who decides a link's caption.
///
/// The two cases are deliberately exclusive: a caption is either derived by
/// the prototype or owned by the app user, and there is no configuration in
/// which both are true. Mixing them would raise a question with no good answer
/// — whether re-deriving should overwrite what somebody typed.
@immutable
sealed class LinkLabel {
  const LinkLabel();
}

/// A caption the prototype computes, and the app user cannot change.
///
/// It follows whatever it is derived from with no bookkeeping, because it is
/// never stored: [NodeConnection.label] is ignored for links that use this.
final class DerivedLinkLabel extends LinkLabel {
  const DerivedLinkLabel({required this.build});

  final LinkLabelBuilder build;
}

/// A caption the app user owns, edited by tapping it on the canvas.
///
/// Stored in [NodeConnection.label] and never computed. A link with this and
/// no caption yet still draws a placeholder, so it can be given a first one.
final class EditableLinkLabel extends LinkLabel {
  const EditableLinkLabel({this.editorTitle = 'Link label'});

  /// Heading for the editor that opens when the caption is tapped.
  final String editorTitle;
}

/// The rule for one kind of connection, matched against [NodeConnection.type].
///
/// Links are far simpler than nodes: they have no ports to derive and no
/// geometry of their own, and they take no part in node resolution. What a
/// prototype decides is where a link's caption comes from.
@immutable
class LinkPrototype {
  const LinkPrototype({required this.type, this.label});

  /// Matched against [NodeConnection.type].
  final String type;

  /// Where the caption comes from, or null to leave it as plain data the
  /// document carries and nobody may edit on the canvas.
  final LinkLabel? label;

  /// Whether the app user may retitle links of this kind.
  bool get editableLabel => label is EditableLinkLabel;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkPrototype && other.type == type && other.label == label;

  @override
  int get hashCode => Object.hash(type, label);

  @override
  String toString() => 'LinkPrototype($type)';
}
