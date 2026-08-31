import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../geometry/viewport_transform.dart';
import '../model/graph_node.dart';
import '../model/node_connection.dart';
import '../model/node_graph.dart';
import '../model/node_group.dart';
import '../model/node_port.dart';
import '../model/port_ref.dart';
import '../prototype/link_prototype.dart';
import '../prototype/node_prototype_registry.dart';
import 'document_exceptions.dart';
import 'document_migrations.dart';
import 'document_reader.dart';
import 'graph_document.dart';
import 'payload_codecs.dart';

/// Which of a node's ports a document carries.
enum PortStorage {
  /// Every port, grouped by the family that produced it. The safe default.
  all,

  /// Only the host's own ports, leaving family-stamped ones for the prototype
  /// to re-derive on load.
  ///
  /// Correct only when every dynamic family is a pure function of the node's
  /// own [GraphNode.data]. A family that reads link state — anything built on
  /// [PortFamilies.variadic], where the exits are "every wired port plus one" —
  /// has nothing to read on load, because the ports it would have counted are
  /// the ones that were left out. The codec cannot check the claim, so this is
  /// yours to make.
  foreign,
}

/// Converts a [GraphDocument] to and from JSON-shaped maps.
///
/// The package does no I/O. [encode] returns a `Map<String, Object?>` made only
/// of JSON values and [decode] takes one back; writing it to a file, a database
/// or the clipboard is the host's business, as is `jsonEncode`.
///
/// [decode] builds a document and touches nothing else, so the caller's own
/// load path reads:
///
/// ```dart
/// final document = codec.decode(json);   // throws here, or not at all
/// controller.replaceGraph(document.graph, recordHistory: false);
/// ```
///
/// which cannot leave an editor blank because a file turned out to be bad.
@immutable
class NodeGraphCodec {
  const NodeGraphCodec({
    PayloadCodecs? payloads,
    this.prototypes,
    this.ports = PortStorage.all,
    this.storeDerivedLabels = false,
    this.migrations = GraphDocumentMigrations.standard,
  }) : _payloads = payloads;

  /// The version [encode] writes, and the version [decode] migrates up to.
  static const int version = 1;

  static const String _packageStamp = 'fl_nodes_v2/0.1.0';

  final PayloadCodecs? _payloads;

  /// The host types a document may carry beyond plain JSON.
  PayloadCodecs get payloads => _payloads ?? PayloadCodecs.none;

  /// Consulted only to decide what may be left *out*.
  ///
  /// Never needed to read a document: a node whose type nobody claims decodes
  /// into a perfectly ordinary [GraphNode], which is why an unknown type
  /// degrades instead of aborting the load.
  final NodePrototypeRegistry? prototypes;

  final PortStorage ports;

  /// Whether to write a caption a [DerivedLinkLabel] would recompute anyway.
  ///
  /// Off by default: the value is never read back. Turn it on for a consumer
  /// that reads documents without having the prototypes to hand.
  final bool storeDerivedLabels;

  final Map<int, GraphDocumentMigration> migrations;

  // ----------------------------------------------------------------- encode

  Map<String, Object?> encode(GraphDocument document) {
    final path = DocumentPath();
    final graph = document.graph;

    return <String, Object?>{
      'version': version,
      'package': document.packageVersion ?? _packageStamp,
      if (document.appVersion != null) 'app': document.appVersion,
      if (document.viewport != null)
        'viewport': _encodeViewport(document.viewport!, path),
      if (document.meta.isNotEmpty)
        'meta': path.at('meta', () => _encodeMap(document.meta, path)),
      'nodes': path.at(
        'nodes',
        () => <Object?>[
          for (final (index, node) in graph.nodes.values.indexed)
            path.at(index, () => _encodeNode(node, graph, path)),
        ],
      ),
      'connections': path.at(
        'connections',
        () => <Object?>[
          for (final (index, connection) in graph.connections.values.indexed)
            path.at(index, () => _encodeConnection(connection, path)),
        ],
      ),
      // Omitted rather than written empty, the way `meta` is. A document with
      // no frames in it predates them or simply has none, and both read back
      // the same way for good.
      if (graph.groups.isNotEmpty)
        'groups': path.at(
          'groups',
          () => <Object?>[
            for (final (index, group) in graph.groups.values.indexed)
              path.at(index, () => _encodeGroup(group)),
          ],
        ),
    };
  }

  Map<String, Object?> _encodeViewport(
    ViewportTransform viewport,
    DocumentPath path,
  ) => path.at('viewport', () {
    return <String, Object?>{
      'offset': _encodeOffset(viewport.offset, path),
      'scale': _finite(viewport.scale, path, 'scale'),
    };
  });

  Map<String, Object?> _encodeNode(
    GraphNode node,
    NodeGraph graph,
    DocumentPath path,
  ) {
    final fields = _encodeFieldGroups(node, graph, path);
    final groups = _encodePortGroups(node, path);

    return <String, Object?>{
      'id': node.id,
      'type': node.type,
      'position': path.at('position', () => _encodeOffset(node.position, path)),
      'width': _finite(node.width, path, 'width'),
      if (node.height != null) 'height': _finite(node.height!, path, 'height'),
      'draggable': node.draggable,
      'selectable': node.selectable,
      if (fields.isNotEmpty) 'fields': fields,
      if (groups.isNotEmpty) 'ports': groups,
    };
  }

  /// Field values, bucketed by the family that declares each key.
  ///
  /// Everything no family claims goes in a trailing bucket with no family, so
  /// the buckets always partition [GraphNode.data] exactly. Without a registry
  /// there is one bucket holding all of it, which decodes identically.
  List<Object?> _encodeFieldGroups(
    GraphNode node,
    NodeGraph graph,
    DocumentPath path,
  ) => path.at('fields', () {
    if (node.data.isEmpty) return const <Object?>[];

    final groups = <Object?>[];
    final claimed = <String>{};
    var index = 0;

    for (final group
        in prototypes?.fieldGroupsOf(graph, node) ?? const <NodeFieldGroup>[]) {
      final values = <String, Object?>{};
      for (final key in group.keys) {
        if (!node.data.containsKey(key) || !claimed.add(key)) continue;
        values[key] = node.data[key];
      }
      if (values.isEmpty) continue;
      groups.add(
        path.at(
          index++,
          () => <String, Object?>{
            'family': group.family,
            if (group.keyPrefix != null) 'keyPrefix': group.keyPrefix,
            'values': path.at('values', () => _encodeMap(values, path)),
          },
        ),
      );
    }

    final rest = <String, Object?>{
      for (final entry in node.data.entries)
        if (!claimed.contains(entry.key)) entry.key: entry.value,
    };
    if (rest.isNotEmpty) {
      groups.add(
        path.at(
          index,
          () => <String, Object?>{
            'values': path.at('values', () => _encodeMap(rest, path)),
          },
        ),
      );
    }
    return groups;
  });

  /// Ports, run-length grouped by [NodePort.family].
  ///
  /// Run-length rather than group-by, so the order survives: a node whose ports
  /// interleave families keeps its exact sequence, and order is not cosmetic —
  /// `NodeGeometry.anchorOf` spreads anchorless ports by their index among
  /// same-side siblings, so reordering moves handles on screen.
  List<Object?> _encodePortGroups(GraphNode node, DocumentPath path) =>
      path.at('ports', () {
        final subject = ports == PortStorage.foreign
            ? <NodePort>[
                for (final port in node.ports)
                  if (port.family == null) port,
              ]
            : node.ports;
        if (subject.isEmpty) return const <Object?>[];

        final groups = <Object?>[];
        var start = 0;
        while (start < subject.length) {
          final family = subject[start].family;
          var end = start + 1;
          while (end < subject.length && subject[end].family == family) {
            end++;
          }

          final index = groups.length;
          groups.add(
            path.at(
              index,
              () => <String, Object?>{
                // Omitted when null, which is exactly how the model spells "the
                // host's own port".
                'family': ?family,
                'ports': path.at(
                  'ports',
                  () => <Object?>[
                    for (var i = start; i < end; i++)
                      path.at(i - start, () => _encodePort(subject[i], path)),
                  ],
                ),
              },
            ),
          );
          start = end;
        }
        return groups;
      });

  Map<String, Object?> _encodePort(NodePort port, DocumentPath path) =>
      <String, Object?>{
        'id': port.id,
        'direction': port.direction.name,
        // Written even when it is the default, like `direction` and unlike the
        // optional keys below. Omitting a value equal to today's default is
        // how changing that default later silently reinterprets every document
        // already written.
        'kind': port.kind.name,
        if (port.dataType != null) 'dataType': port.dataType,
        if (port.label != null) 'label': port.label,
        // The authored side, not the resolved one: writing `side` would turn
        // every unset side into an explicit one, and equality compares what was
        // authored.
        if (port.declaredSide != null) 'side': port.declaredSide!.name,
        if (port.anchor != null)
          'anchor': path.at('anchor', () => _encodeOffset(port.anchor!, path)),
        if (port.color != null) 'color': _encodeColor(port.color!),
        if (port.maxConnections != null) 'maxConnections': port.maxConnections,
        if (port.linkType != null) 'linkType': port.linkType,
        if (port.data != null)
          'data': path.at('data', () => _encodeValue(port.data, path)),
      };

  Map<String, Object?> _encodeConnection(
    NodeConnection connection,
    DocumentPath path,
  ) {
    // A derived caption is recomputed on load and the stored one ignored, so
    // writing it only puts something in the file that can go stale.
    final derived =
        !storeDerivedLabels &&
        prototypes?.linkPrototype(connection.type)?.label is DerivedLinkLabel;

    return <String, Object?>{
      'id': connection.id,
      'type': connection.type,
      'from': _encodePortRef(connection.from),
      'to': _encodePortRef(connection.to),
      if (!derived && connection.label != null) 'label': connection.label,
      if (connection.color != null) 'color': _encodeColor(connection.color!),
      if (connection.data != null)
        'data': path.at('data', () => _encodeValue(connection.data, path)),
    };
  }

  static Map<String, Object?> _encodeGroup(
    NodeGroup group,
  ) => <String, Object?>{
    'id': group.id,
    'name': group.name,
    if (group.color != null) 'color': _encodeColor(group.color!),
    // Sorted, so a document is stable across runs: membership is a set and its
    // iteration order is not something a diff should have to see change.
    'nodes': group.nodeIds.toList()..sort(),
  };

  static Map<String, Object?> _encodePortRef(PortRef ref) => <String, Object?>{
    'nodeId': ref.nodeId,
    'portId': ref.portId,
  };

  List<Object?> _encodeOffset(Offset offset, DocumentPath path) => <Object?>[
    _finite(offset.dx, path, 'dx'),
    _finite(offset.dy, path, 'dy'),
  ];

  /// Packed when that round-trips exactly, component-wise when it would not.
  ///
  /// `Color` compares four doubles and a colour space, not a packed int, so a
  /// colour built from components or in a wide gamut is not recoverable from
  /// `toARGB32()`. The guard is a real equality check rather than a guess.
  static Object _encodeColor(Color color) {
    final packed = color.toARGB32();
    if (color.colorSpace == ColorSpace.sRGB && Color(packed) == color) {
      return packed;
    }
    return <String, Object?>{
      'a': color.a,
      'r': color.r,
      'g': color.g,
      'b': color.b,
      'space': color.colorSpace.name,
    };
  }

  double _finite(double value, DocumentPath path, String what) {
    if (value.isFinite) return value;
    throw GraphDocumentFormatException(
      'cannot write $what: $value has no JSON representation',
      path: path.path,
    );
  }

  Map<String, Object?> _encodeMap(
    Map<String, Object?> values,
    DocumentPath path,
  ) {
    final encoded = <String, Object?>{
      for (final entry in values.entries)
        entry.key: path.at(entry.key, () => _encodeValue(entry.value, path)),
    };
    // A map of the host's own that happens to hold a "$type" key would read
    // back as a tagged payload, so it is wrapped out of harm's way.
    if (encoded.containsKey(PayloadCodecs.typeKey)) {
      return <String, Object?>{
        PayloadCodecs.typeKey: PayloadCodecs.mapTag,
        PayloadCodecs.valueKey: encoded,
      };
    }
    return encoded;
  }

  Object? _encodeValue(Object? value, DocumentPath path) {
    if (value == null || value is bool || value is String || value is int) {
      return value;
    }
    if (value is double) return _finite(value, path, 'value');
    if (value is List) {
      return <Object?>[
        for (final (index, element) in value.indexed)
          path.at(index, () => _encodeValue(element, path)),
      ];
    }
    if (value is Map && value.keys.every((Object? key) => key is String)) {
      return _encodeMap(value.cast<String, Object?>(), path);
    }

    final codec = payloads.forValue(value);
    if (codec == null) {
      throw UnencodablePayloadException(
        'a ${value.runtimeType} has no JSON representation and no payload '
        'codec is registered for it — register one on PayloadCodecs, or store '
        'a JSON value',
        type: value.runtimeType,
        path: path.path,
      );
    }
    return <String, Object?>{
      PayloadCodecs.typeKey: codec.tag,
      PayloadCodecs.valueKey: codec.encodeValue(value),
    };
  }

  // ----------------------------------------------------------------- decode

  /// Rebuilds a document, or throws without having touched anything.
  GraphDocument decode(Map<String, Object?> json) {
    final reader = DocumentReader();

    final found = reader.at('version', () => reader.integer(json['version']));
    if (found < 1) {
      throw GraphDocumentFormatException(
        'format version must be 1 or greater, found $found',
        path: const <Object>['version'],
      );
    }
    if (found > version) {
      throw GraphDocumentVersionException(
        'This document was written in format version $found, and this build '
        'reads up to version $version. Update the app that opens it.',
        found: found,
        supported: version,
        path: const <Object>['version'],
      );
    }

    final current = GraphDocumentMigrations.upgrade(
      json,
      from: found,
      target: version,
      chain: migrations,
    );
    return _read(current, reader);
  }

  GraphDocument _read(Map<String, Object?> json, DocumentReader reader) {
    final nodes = <GraphNode>[];
    final nodeIds = <String>{};
    reader.at<void>('nodes', () {
      final list = reader.array(json['nodes'] ?? const <Object?>[]);
      for (final (index, entry) in list.indexed) {
        reader.at<void>(index, () {
          final node = _readNode(reader.object(entry), reader);
          if (!nodeIds.add(node.id)) {
            reader.fail('duplicate node id "${node.id}"');
          }
          nodes.add(node);
        });
      }
    });

    final connections = <NodeConnection>[];
    final connectionIds = <String>{};
    reader.at<void>('connections', () {
      final list = reader.array(json['connections'] ?? const <Object?>[]);
      for (final (index, entry) in list.indexed) {
        reader.at<void>(index, () {
          final connection = _readConnection(reader.object(entry), reader);
          if (!connectionIds.add(connection.id)) {
            reader.fail('duplicate connection id "${connection.id}"');
          }
          connections.add(connection);
        });
      }
    });

    final groups = <NodeGroup>[];
    final groupIds = <String>{};
    reader.at<void>('groups', () {
      final list = reader.array(json['groups'] ?? const <Object?>[]);
      for (final (index, entry) in list.indexed) {
        reader.at<void>(index, () {
          final group = _readGroup(reader.object(entry), nodeIds, reader);
          if (!groupIds.add(group.id)) {
            reader.fail('duplicate group id "${group.id}"');
          }
          groups.add(group);
        });
      }
    });

    final viewportJson = json['viewport'];
    final meta = json['meta'];

    return GraphDocument(
      graph: NodeGraph(nodes: nodes, connections: connections, groups: groups),
      viewport: viewportJson == null
          ? null
          : reader.at('viewport', () {
              final map = reader.object(viewportJson);
              return ViewportTransform(
                offset: reader.at('offset', () => reader.offset(map['offset'])),
                scale: reader.at('scale', () => reader.number(map['scale'])),
              );
            }),
      meta: meta == null
          ? const <String, Object?>{}
          : reader.at('meta', () => _readMap(reader.object(meta), reader)),
      appVersion: json['app'] == null
          ? null
          : reader.at('app', () => reader.string(json['app'])),
      packageVersion: json['package'] == null
          ? null
          : reader.at('package', () => reader.string(json['package'])),
    );
  }

  GraphNode _readNode(Map<String, Object?> json, DocumentReader reader) {
    final id = reader.at('id', () => reader.string(json['id']));

    final data = <String, Object?>{};
    reader.at<void>('fields', () {
      final groups = reader.array(json['fields'] ?? const <Object?>[]);
      for (final (index, entry) in groups.indexed) {
        reader.at<void>(index, () {
          final group = reader.object(entry);
          reader.at<void>('values', () {
            final values = _readMap(reader.object(group['values']), reader);
            for (final value in values.entries) {
              if (data.containsKey(value.key)) {
                reader.fail(
                  'field "${value.key}" appears in more than one family',
                );
              }
              data[value.key] = value.value;
            }
          });
        });
      }
    });

    final ports = <NodePort>[];
    final portIds = <String>{};
    reader.at<void>('ports', () {
      final groups = reader.array(json['ports'] ?? const <Object?>[]);
      for (final (index, entry) in groups.indexed) {
        reader.at<void>(index, () {
          final group = reader.object(entry);
          final family = group['family'] == null
              ? null
              : reader.at('family', () => reader.string(group['family']));
          reader.at<void>('ports', () {
            final list = reader.array(group['ports']);
            for (final (portIndex, portEntry) in list.indexed) {
              reader.at<void>(portIndex, () {
                final port = _readPort(
                  reader.object(portEntry),
                  family,
                  reader,
                );
                if (!portIds.add(port.id)) {
                  reader.fail('duplicate port id "${port.id}" on this node');
                }
                ports.add(port);
              });
            }
          });
        });
      }
    });

    return GraphNode(
      id: id,
      type: json['type'] == null
          ? 'default'
          : reader.at('type', () => reader.string(json['type'])),
      position: reader.at('position', () => reader.offset(json['position'])),
      width: json['width'] == null
          ? GraphNode.defaultWidth
          : reader.at('width', () => reader.number(json['width'])),
      // Absent means auto-measure: the encoder never writes a null-valued key,
      // so there is no third state to tell apart.
      height: json['height'] == null
          ? null
          : reader.at('height', () => reader.number(json['height'])),
      ports: ports,
      data: data,
      draggable: json['draggable'] == null
          ? true
          : reader.at('draggable', () => reader.boolean(json['draggable'])),
      selectable: json['selectable'] == null
          ? true
          : reader.at('selectable', () => reader.boolean(json['selectable'])),
    );
  }

  NodePort _readPort(
    Map<String, Object?> json,
    String? family,
    DocumentReader reader,
  ) => NodePort(
    id: reader.at('id', () => reader.string(json['id'])),
    direction: reader.at(
      'direction',
      () => reader.enumByName(
        json['direction'],
        PortDirection.values,
        'port direction',
      ),
    ),
    // Absent in anything written before kinds existed, and `data` is what
    // those ports were.
    kind: json['kind'] == null
        ? PortKind.data
        : reader.at(
            'kind',
            () => reader.enumByName(json['kind'], PortKind.values, 'port kind'),
          ),
    dataType: json['dataType'] == null
        ? null
        : reader.at('dataType', () => reader.string(json['dataType'])),
    label: json['label'] == null
        ? null
        : reader.at('label', () => reader.string(json['label'])),
    side: json['side'] == null
        ? null
        : reader.at(
            'side',
            () => reader.enumByName(json['side'], PortSide.values, 'port side'),
          ),
    anchor: json['anchor'] == null
        ? null
        : reader.at('anchor', () => reader.offset(json['anchor'])),
    color: json['color'] == null
        ? null
        : reader.at('color', () => reader.color(json['color'])),
    maxConnections: json['maxConnections'] == null
        ? null
        : reader.at(
            'maxConnections',
            () => reader.integer(json['maxConnections']),
          ),
    data: json['data'] == null
        ? null
        : reader.at('data', () => _readValue(json['data'], reader)),
    // Stamped from the group, so a port can never disagree with the family
    // that produced it.
    family: family,
    linkType: json['linkType'] == null
        ? null
        : reader.at('linkType', () => reader.string(json['linkType'])),
  );

  NodeConnection _readConnection(
    Map<String, Object?> json,
    DocumentReader reader,
  ) => NodeConnection(
    id: reader.at('id', () => reader.string(json['id'])),
    from: reader.at('from', () => _readPortRef(json['from'], reader)),
    to: reader.at('to', () => _readPortRef(json['to'], reader)),
    type: json['type'] == null
        ? 'default'
        : reader.at('type', () => reader.string(json['type'])),
    label: json['label'] == null
        ? null
        : reader.at('label', () => reader.string(json['label'])),
    color: json['color'] == null
        ? null
        : reader.at('color', () => reader.color(json['color'])),
    data: json['data'] == null
        ? null
        : reader.at('data', () => _readValue(json['data'], reader)),
  );

  /// A frame, with any member the document does not actually carry dropped.
  ///
  /// Deliberately lenient where a dangling *connection* would be an error: a
  /// wire to nowhere has no meaning, but a frame around four of five nodes is
  /// still a frame, and refusing to open the document over it would be worse
  /// than drawing it slightly smaller.
  NodeGroup _readGroup(
    Map<String, Object?> json,
    Set<String> knownNodes,
    DocumentReader reader,
  ) {
    final members = <String>{};
    reader.at<void>('nodes', () {
      final list = reader.array(json['nodes'] ?? const <Object?>[]);
      for (final (index, entry) in list.indexed) {
        final id = reader.at(index, () => reader.string(entry));
        if (knownNodes.contains(id)) members.add(id);
      }
    });

    return NodeGroup(
      id: reader.at('id', () => reader.string(json['id'])),
      nodeIds: members,
      name: json['name'] == null
          ? NodeGroup.defaultName
          : reader.at('name', () => reader.string(json['name'])),
      color: json['color'] == null
          ? null
          : reader.at('color', () => reader.color(json['color'])),
    );
  }

  PortRef _readPortRef(Object? value, DocumentReader reader) {
    final map = reader.object(value);
    return PortRef(
      reader.at('nodeId', () => reader.string(map['nodeId'])),
      reader.at('portId', () => reader.string(map['portId'])),
    );
  }

  Map<String, Object?> _readMap(
    Map<String, Object?> json,
    DocumentReader reader,
  ) => <String, Object?>{
    for (final entry in json.entries)
      entry.key: reader.at(entry.key, () => _readValue(entry.value, reader)),
  };

  Object? _readValue(Object? value, DocumentReader reader) {
    if (value == null || value is bool || value is num || value is String) {
      return value;
    }
    if (value is List) {
      return <Object?>[
        for (final (index, element) in value.indexed)
          reader.at(index, () => _readValue(element, reader)),
      ];
    }

    final map = reader.object(value);
    final tag = map[PayloadCodecs.typeKey];
    if (tag is! String) {
      return _readMap(map, reader);
    }

    if (tag == PayloadCodecs.mapTag) {
      return reader.at(
        PayloadCodecs.valueKey,
        () => _readMap(reader.object(map[PayloadCodecs.valueKey]), reader),
      );
    }

    final codec = payloads.forTag(tag);
    if (codec == null) {
      return reader.fail(
        'unknown payload type "$tag" — register a PayloadCodec for it, or '
        'open this document with the app that wrote it',
      );
    }
    return codec.decodeValue(map[PayloadCodecs.valueKey]);
  }
}
