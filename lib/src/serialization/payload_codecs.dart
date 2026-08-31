import 'package:flutter/foundation.dart';

/// Turns a host value into a JSON value.
typedef PayloadEncoder<T extends Object> = Object? Function(T value);

/// Rebuilds a host value from the JSON [PayloadEncoder] produced.
typedef PayloadDecoder<T extends Object> = T Function(Object? json);

/// Carries one host type across the document boundary.
///
/// [toJson] returns a JSON *value* — a primitive, a list, or a string-keyed map
/// — not a string, so a nested structure stays structured in the document
/// instead of being encoded twice and read back as an opaque blob.
@immutable
class PayloadCodec<T extends Object> {
  const PayloadCodec({
    required this.tag,
    required this.toJson,
    required this.fromJson,
  });

  /// Written into the document beside the value, and matched on the way back.
  ///
  /// Both directions dispatching on the same recorded string is what keeps them
  /// from drifting apart: the alternative — encoding by runtime type and
  /// decoding by a declared one — silently disagrees for a generic like
  /// `List<int>`.
  final String tag;

  final PayloadEncoder<T> toJson;
  final PayloadDecoder<T> fromJson;

  Type get type => T;

  bool matches(Object value) => value is T;

  /// Encodes [value], which must satisfy [matches].
  Object? encodeValue(Object value) => toJson(value as T);

  Object decodeValue(Object? json) => fromJson(json);

  @override
  String toString() => 'PayloadCodec<$T>($tag)';
}

/// The host types a document may carry beyond plain JSON.
///
/// Deliberately an instance rather than a process-wide table: two editors in
/// one app may carry entirely different payloads, and a test has to be able to
/// build one that carries none.
@immutable
class PayloadCodecs {
  PayloadCodecs([
    Iterable<PayloadCodec<Object>> codecs = const <PayloadCodec<Object>>[],
  ]) : _codecs = List<PayloadCodec<Object>>.unmodifiable(codecs) {
    for (final codec in _codecs) {
      if (codec.tag == mapTag) {
        throw ArgumentError.value(
          codec.tag,
          'tag',
          'is reserved for escaping a map that contains a "$typeKey" key',
        );
      }
      if (_byTag.containsKey(codec.tag)) {
        throw ArgumentError.value(codec.tag, 'tag', 'is registered twice');
      }
      _byTag[codec.tag] = codec;
      _byType.putIfAbsent(codec.type, () => codec);
    }
  }

  /// A registry that carries nothing but plain JSON.
  static final PayloadCodecs none = PayloadCodecs();

  /// Marks a tagged value: `{"$type": "colour", "value": 4285504496}`.
  static const String typeKey = r'$type';

  /// Holds the encoded value beside [typeKey].
  static const String valueKey = 'value';

  /// Escapes a plain map that happens to contain a [typeKey] of its own.
  static const String mapTag = 'map';

  final List<PayloadCodec<Object>> _codecs;
  final Map<String, PayloadCodec<Object>> _byTag =
      <String, PayloadCodec<Object>>{};
  final Map<Type, PayloadCodec<Object>> _byType =
      <Type, PayloadCodec<Object>>{};

  bool get isEmpty => _codecs.isEmpty;

  Iterable<String> get tags => _byTag.keys;

  /// The codec for [value]: an exact runtime-type match first, then the first
  /// registration [value] is an instance of.
  ///
  /// The fallback matters because `<int>[1, 2].runtimeType` is `List<int>`, not
  /// `List<dynamic>` — the mismatch that makes generic payloads fall through a
  /// type-keyed table. Registration order decides between overlapping codecs.
  PayloadCodec<Object>? forValue(Object value) {
    final exact = _byType[value.runtimeType];
    if (exact != null) return exact;
    for (final codec in _codecs) {
      if (codec.matches(value)) return codec;
    }
    return null;
  }

  PayloadCodec<Object>? forTag(String tag) => _byTag[tag];
}
