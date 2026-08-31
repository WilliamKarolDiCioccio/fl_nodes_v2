import 'dart:math' as math;

import '../model/node_port.dart';
import 'node_resolution.dart';

/// Ready-made [PortFamilyBuilder]s for the shapes that come up most.
///
/// Nothing here is privileged — these are ordinary builders, and a family that
/// needs different behaviour writes its own.
abstract final class PortFamilies {
  /// Keeps every connected port and always leaves [spare] free ones at the end,
  /// so wiring the last port grows the family.
  ///
  /// Ids are `'$idPrefix$index'` with the index one past the highest still in
  /// use, and the builder stamps them itself. That is what keeps repeated
  /// resolution stable: numbering by list length instead would hand out an id
  /// that is already taken once a port in the middle is disconnected, and
  /// drawing from a counter would never repeat at all.
  static PortFamilyBuilder variadic({
    required String idPrefix,
    required NodePort Function(int index) create,
    int spare = 1,
    int minimum = 0,
  }) {
    assert(spare >= 0, 'a negative number of spare ports is meaningless');
    return (context) {
      final kept = <NodePort>[
        for (final port in context.currentPorts)
          if (context.isConnected(port.id)) port,
      ];

      var highest = -1;
      for (final port in kept) {
        final index = _indexOf(port.id, idPrefix);
        if (index != null && index > highest) highest = index;
      }

      final ports = <NodePort>[...kept];
      final target = math.max(kept.length + spare, minimum);
      while (ports.length < target) {
        highest++;
        ports.add(create(highest).copyWith(id: '$idPrefix$highest'));
      }
      return ports;
    };
  }

  static int? _indexOf(String portId, String prefix) =>
      portId.startsWith(prefix)
      ? int.tryParse(portId.substring(prefix.length))
      : null;
}
