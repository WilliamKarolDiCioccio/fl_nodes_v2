import 'package:flutter/widgets.dart';

import '../model/graph_node.dart';
import '../model/node_port.dart';
import 'node_execution.dart';
import 'node_resolution.dart';

/// A group of ports a prototype owns.
///
/// Families are the unit of the static/dynamic choice: a node can hold a fixed
/// input and a variadic output and have only the second re-derive. They are
/// also the unit of replacement — resolving a family swaps out exactly its own
/// ports and leaves every other port on the node alone.
@immutable
sealed class PortFamily {
  const PortFamily({required this.id});

  /// Unique within the prototype, and stamped onto every port it produces.
  final String id;
}

/// A family whose ports never change.
///
/// Still owned, which is the point: the ports are re-materialised on every
/// pass, so editing the prototype propagates a renamed label or a moved anchor
/// to nodes that already exist.
final class StaticPortFamily extends PortFamily {
  const StaticPortFamily({required super.id, required this.ports});

  final List<NodePort> ports;
}

/// A family rebuilt from the node's fields and links on every pass.
final class DynamicPortFamily extends PortFamily {
  const DynamicPortFamily({required super.id, required this.build});

  final PortFamilyBuilder build;
}

/// A group of [GraphNode.data] keys a prototype owns.
@immutable
sealed class FieldFamily {
  const FieldFamily({required this.id});

  final String id;
}

/// A fixed set of declared fields.
final class StaticFieldFamily extends FieldFamily {
  const StaticFieldFamily({required super.id, required this.fields});

  final List<NodeField> fields;
}

/// A family whose declared fields depend on the node's current values.
///
/// [keyPrefix] is what makes pruning possible. Keys beneath it are the
/// prototype's to manage, so a value whose field has gone can be dropped
/// without the package having to remember what it declared last time — and
/// everything outside it stays the host's business.
final class DynamicFieldFamily extends FieldFamily {
  const DynamicFieldFamily({
    required super.id,
    required this.keyPrefix,
    required this.build,
  });

  final String keyPrefix;
  final FieldFamilyBuilder build;
}

/// One entry in [GraphNode.data], as the prototype declares it.
///
/// The package stores the value and nothing else: [data] carries whatever the
/// host's editor switches on — a type tag, a range, a picker hint.
@immutable
class NodeField {
  const NodeField({
    required this.key,
    this.defaultValue,
    this.label,
    this.data,
  });

  final String key;
  final Object? defaultValue;
  final String? label;
  final Object? data;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NodeField &&
          other.key == key &&
          other.defaultValue == defaultValue &&
          other.label == label &&
          other.data == data;

  @override
  int get hashCode => Object.hash(key, defaultValue, label, data);

  @override
  String toString() => 'NodeField($key)';
}

/// The rule that normalises one kind of node.
///
/// Where a conventional prototype is a template stamped out once, this is a
/// reduction rule applied continuously: given what the node's fields say and
/// what its links look like right now, it returns the ports, fields and height
/// that node *should* have. Resolution rewrites the node to match, so ports
/// become derived state rather than something the document authors by hand.
///
/// That is what makes ports able to appear on demand — one input per
/// placeholder in a format string, one more exit each time the last free one is
/// wired — and it is why a document only has to persist the fields: the ports
/// come back on their own.
@immutable
class NodePrototype {
  const NodePrototype({
    required this.type,
    this.label,
    this.icon,
    this.category,
    this.description,
    this.defaultWidth,
    this.resizable = false,
    this.minWidth,
    this.maxWidth,
    this.maxHeight,
    this.fields = const <FieldFamily>[],
    this.ports = const <PortFamily>[],
    this.inheritFields = NodeFields.seedAndPrune,
    this.onPortsRemoved = NodePortRemoval.dropConnections,
    this.resolveHeight,
    this.onExecute,
    this.pure = true,
    this.maxPasses = 8,
  }) : assert(maxPasses > 0, 'a prototype needs at least one pass');

  /// Matched against [GraphNode.type].
  final String type;

  /// The name a person sees, where [type] is the name the document uses.
  ///
  /// It doubles as the opt-in for the editor's "Create" menu: a prototype
  /// without one is not offered there. That saves a second flag, and it means
  /// a prototype only ends up in a palette once somebody has decided what to
  /// call it.
  final String? label;

  /// Shown beside [label] in menus.
  final IconData? icon;

  /// Groups this node with its siblings in the "Create" menu.
  ///
  /// Null leaves it ungrouped; a menu whose prototypes set no category at all
  /// is rendered flat rather than under one heading.
  final String? category;

  /// What this kind of node is for, in prose, for the reader of a graph.
  ///
  /// The editor's node menu offers it read-only, and offers nothing when this
  /// is null — help text belongs to the kind of node, written once by whoever
  /// wrote the prototype, not to each copy on the canvas.
  final String? description;

  /// The width a freshly instantiated node of this type starts at.
  ///
  /// A seed, not a rule: resolution never touches [GraphNode.width], because
  /// a width the app user has since chosen is theirs. It only saves a palette
  /// from having to know a number that belongs to the prototype.
  final double? defaultWidth;

  /// Whether a person may drag a node's bottom-right corner to resize it.
  ///
  /// Off by default: a host whose cards are laid out to one width — port
  /// rows measured against it, a preview column sized to it — has to decide
  /// that a wider card is still a right one before the editor offers it.
  ///
  /// The width is the node's own. The height is a **floor**,
  /// [GraphNode.minHeight]: what [resolveHeight] or the content says is the
  /// least the node can be, the corner can only add room below it, and the
  /// ports stay on their rows because every anchor is a fraction of the
  /// declared height rather than of the box. A prototype that would rather
  /// use the room than leave it blank reads the floor in [resolveHeight].
  final bool resizable;

  /// The narrowest a resize may leave the node, or [defaultWidth] — else
  /// [GraphNode.defaultWidth] — when unset. A card cannot be dragged
  /// narrower than the width it was designed at.
  final double? minWidth;

  /// The widest, or no limit when unset.
  final double? maxWidth;

  /// The tallest a resize may make the node, or no limit when unset. The
  /// floor is always what the node already is.
  final double? maxHeight;

  /// [minWidth] as a resize reads it.
  double get resizeFloor => minWidth ?? defaultWidth ?? GraphNode.defaultWidth;

  final List<FieldFamily> fields;
  final List<PortFamily> ports;

  /// How field values carry across iterations. Yours to override.
  final NodeFieldMerge inheritFields;

  /// What becomes of connections whose port has just vanished.
  final PortRemovalHandler onPortsRemoved;

  /// The node's declared height, or null to size it to its content.
  ///
  /// Leave the callback off entirely to not touch [GraphNode.height] at all,
  /// which is what an auto-measured node wants.
  final NodeHeightResolver? resolveHeight;

  /// What this node does when the flow reaches it.
  ///
  /// Null is not "does nothing": a node with no executor passes the flow
  /// straight through its one control output, which is what most of a
  /// narrative graph's passages want.
  final NodeExecutor? onExecute;

  /// Whether a value this node computes may be reused within one run.
  ///
  /// A pure data node — one that declares no control ports — is evaluated when
  /// something asks for its output and then reused until one of its own inputs
  /// changes. That is right for a node that is a function of its inputs and
  /// wrong for one that is not: `random()`, `now()`, anything that reads the
  /// world. Those set this false and are evaluated on every pull.
  ///
  /// It says nothing about resolution, which never caches.
  final bool pure;

  /// Passes before the node is declared non-convergent and left as it is.
  final int maxPasses;
}
