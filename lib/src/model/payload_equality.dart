/// Value equality for the open payloads the model carries.
///
/// `data` fields hold whatever the host puts in them, and after a load that is
/// whatever a JSON decoder produced. Dart compares `List` and `Map` by
/// identity, so without this a decoded payload would never equal the one it was
/// written from — and a port whose payload compared unequal on every pass would
/// keep its node from ever settling under a prototype.
///
/// Comparing here rather than wrapping decoded containers in a value-equal type
/// keeps the equality symmetric. A wrapper can only ever be equal to a plain
/// container from its own side, and `expect(actual, expected)` compares the
/// other way round.
bool payloadEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;

  if (a is List) {
    if (b is! List || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!payloadEquals(a[i], b[i])) return false;
    }
    return true;
  }

  if (a is Map) {
    if (b is! Map || a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (!payloadEquals(entry.value, b[entry.key])) return false;
    }
    return true;
  }

  return a == b;
}

/// The hash that goes with [payloadEquals], so equal payloads hash equal.
int payloadHash(Object? value) {
  if (value is List) {
    return Object.hashAll(value.map(payloadHash));
  }
  if (value is Map) {
    return Object.hashAllUnordered(
      value.entries.map(
        (entry) =>
            Object.hash(payloadHash(entry.key), payloadHash(entry.value)),
      ),
    );
  }
  return value.hashCode;
}
