import 'dart:ui';

import 'document_exceptions.dart';

/// Tracks where in a document the work currently is.
///
/// Shared by reading and writing: both need to say `nodes[3].ports[1].anchor`
/// when something goes wrong, and neither should have to thread a path through
/// every signature to do it.
class DocumentPath {
  final List<Object> _path = <Object>[];

  List<Object> get path => List<Object>.unmodifiable(_path);

  /// Runs [body] one step deeper, so anything it throws carries [step].
  R at<R>(Object step, R Function() body) {
    _path.add(step);
    try {
      return body();
    } finally {
      _path.removeLast();
    }
  }
}

/// Reads primitives out of a decoded JSON document, remembering where it is.
///
/// Every read goes through here so a failure can name its location. The
/// alternative — casting inline — reports `type 'String' is not a subtype of
/// type 'num'` and leaves whoever hit it to find which of four hundred nodes it
/// came from.
class DocumentReader extends DocumentPath {
  Never fail(String message) =>
      throw GraphDocumentFormatException(message, path: path);

  static String _describe(Object? value) =>
      value == null ? 'null' : 'a ${value.runtimeType}';

  Map<String, Object?> object(Object? value) {
    if (value is! Map) fail('expected an object, found ${_describe(value)}');
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        fail('expected string keys, found a ${key.runtimeType} key');
      }
      result[key] = entry.value;
    }
    return result;
  }

  List<Object?> array(Object? value) {
    if (value is! List) fail('expected an array, found ${_describe(value)}');
    return value;
  }

  String string(Object? value) {
    if (value is! String) fail('expected a string, found ${_describe(value)}');
    return value;
  }

  bool boolean(Object? value) {
    if (value is! bool) {
      fail('expected true or false, found ${_describe(value)}');
    }
    return value;
  }

  /// Accepts an int as well as a double, because JSON writes `160.0` as `160`.
  double number(Object? value) {
    if (value is! num) fail('expected a number, found ${_describe(value)}');
    final result = value.toDouble();
    if (!result.isFinite) fail('expected a finite number, found $value');
    return result;
  }

  int integer(Object? value) {
    if (value is int) return value;
    if (value is double && value == value.roundToDouble() && value.isFinite) {
      return value.toInt();
    }
    fail('expected a whole number, found ${_describe(value)}');
  }

  T enumByName<T extends Enum>(Object? value, List<T> values, String what) {
    final name = string(value);
    for (final candidate in values) {
      if (candidate.name == name) return candidate;
    }
    final legal = values.map((candidate) => candidate.name).join(', ');
    fail('unknown $what "$name"; expected one of $legal');
  }

  Offset offset(Object? value) {
    final list = array(value);
    if (list.length != 2) {
      fail('expected [dx, dy], found ${list.length} entries');
    }
    return Offset(at(0, () => number(list[0])), at(1, () => number(list[1])));
  }

  /// Accepts the packed form written for ordinary sRGB colours, or the
  /// component form used when packing would not round-trip exactly.
  Color color(Object? value) {
    if (value is int) return Color(value);
    final map = object(value);
    return Color.from(
      alpha: at('a', () => number(map['a'])),
      red: at('r', () => number(map['r'])),
      green: at('g', () => number(map['g'])),
      blue: at('b', () => number(map['b'])),
      colorSpace: at(
        'space',
        () => enumByName(map['space'], ColorSpace.values, 'colour space'),
      ),
    );
  }
}
