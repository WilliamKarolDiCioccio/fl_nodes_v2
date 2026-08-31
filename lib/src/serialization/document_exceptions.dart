/// Something went wrong converting a document, and this says where.
///
/// Every failure carries a [path] from the document root, so a malformed file
/// reports `nodes[3].ports[1].anchor` rather than leaving the reader to bisect
/// it by hand.
class GraphDocumentException implements Exception {
  const GraphDocumentException(this.message, {this.path = const <Object>[]});

  final String message;

  /// Steps from the root: `['nodes', 3, 'ports', 1, 'anchor']`.
  final List<Object> path;

  /// The path as a person reads it: `nodes[3].ports[1].anchor`.
  String get location {
    if (path.isEmpty) return '<document>';
    final buffer = StringBuffer();
    for (final step in path) {
      if (step is int) {
        buffer.write('[$step]');
      } else {
        if (buffer.isNotEmpty) buffer.write('.');
        buffer.write(step);
      }
    }
    return buffer.toString();
  }

  @override
  String toString() => '$runtimeType at $location: $message';
}

/// The document is not shaped the way this version expects.
class GraphDocumentFormatException extends GraphDocumentException {
  const GraphDocumentFormatException(super.message, {super.path});
}

/// The document was written in a version this build cannot read.
///
/// Separate from [GraphDocumentFormatException] because a host wants to say
/// "update the app" rather than "the file is broken".
class GraphDocumentVersionException extends GraphDocumentException {
  const GraphDocumentVersionException(
    super.message, {
    required this.found,
    required this.supported,
    super.path,
  });

  /// The version the document claims.
  final int found;

  /// The newest version this build understands.
  final int supported;
}

/// A value in the graph has no JSON representation and no registered codec.
class UnencodablePayloadException extends GraphDocumentException {
  const UnencodablePayloadException(
    super.message, {
    required this.type,
    super.path,
  });

  final Type type;
}
