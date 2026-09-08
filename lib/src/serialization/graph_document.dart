import 'package:flutter/foundation.dart';

import '../geometry/viewport_transform.dart';
import '../model/node_graph.dart';

/// A whole saved document: the graph, the camera it was saved under, and
/// whatever the host keeps alongside them.
@immutable
class GraphDocument {
  const GraphDocument({
    required this.graph,
    this.viewport,
    this.meta = const <String, Object?>{},
    this.appVersion,
    this.packageVersion,
    this.schemaVersion,
  });

  final NodeGraph graph;

  /// The camera, or null for a document that carries no view.
  ///
  /// Strictly this is controller state rather than document state, but every
  /// editor wants to reopen where it was left. Null lets the host choose
  /// between restoring the camera and framing the content afresh.
  final ViewportTransform? viewport;

  /// Host passthrough, kept under its own key so it can never collide with
  /// anything the format owns.
  final Map<String, Object?> meta;

  /// The host application's own version string. Written, read back, and never
  /// interpreted.
  final String? appVersion;

  /// Which build of this package wrote the file.
  ///
  /// A breadcrumb for whoever is debugging a bad one. The integer format
  /// version is the only thing that governs how a document is parsed.
  final String? packageVersion;

  /// The *host's* own format version for what it keeps in this document.
  ///
  /// The package's integer governs the envelope — nodes, connections, groups,
  /// ports. This one governs what the host means by a node's `type` and by the
  /// keys in its `data`, both of which the package carries and never
  /// interprets. Two axes because they move on different clocks: renaming a
  /// field on somebody else's node type is not a reason for this package to
  /// cut a format version, and cutting one here should not oblige every host
  /// to write a migration.
  ///
  /// Null on a document from a host that does not version its own data.
  final int? schemaVersion;

  GraphDocument copyWith({
    NodeGraph? graph,
    ViewportTransform? viewport,
    Map<String, Object?>? meta,
    String? appVersion,
    String? packageVersion,
    int? schemaVersion,
  }) => GraphDocument(
    graph: graph ?? this.graph,
    viewport: viewport ?? this.viewport,
    meta: meta ?? this.meta,
    appVersion: appVersion ?? this.appVersion,
    packageVersion: packageVersion ?? this.packageVersion,
    schemaVersion: schemaVersion ?? this.schemaVersion,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphDocument &&
          other.graph == graph &&
          other.viewport == viewport &&
          mapEquals(other.meta, meta) &&
          other.appVersion == appVersion &&
          other.packageVersion == packageVersion &&
          other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    graph,
    viewport,
    Object.hashAllUnordered(meta.keys),
    appVersion,
    packageVersion,
    schemaVersion,
  );

  @override
  String toString() => 'GraphDocument($graph)';
}
