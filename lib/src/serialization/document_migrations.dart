import 'document_exceptions.dart';

/// Lifts a document map one format version forward.
///
/// Migrations are pure `Map` to `Map`: they never mention a model type, so
/// refactoring the model cannot break the ability to read an old file, and a
/// migration can be tested with a literal on each side.
typedef GraphDocumentMigration =
    Map<String, Object?> Function(Map<String, Object?> document);

/// The chain that carries an old document up to the current version.
///
/// There is one reader, for the current version, and old versions reach it by
/// migration. The alternative — a reader per version, kept alive forever — ties
/// every historical format to a model that has since moved on, and costs a new
/// reader per model each time the format changes.
abstract final class GraphDocumentMigrations {
  /// Keyed by the version each entry migrates *from*: `standard[1]` turns a
  /// version 1 document into a version 2 one.
  ///
  /// Empty while version 1 is current — there is nothing older to lift.
  static const Map<int, GraphDocumentMigration> standard =
      <int, GraphDocumentMigration>{};

  /// Runs [document] from [from] up to [target].
  ///
  /// Throws naming the exact step that is missing, rather than handing a
  /// half-migrated document to a reader that will misread it.
  ///
  /// [label] and [key] name the axis in that failure — the prose and the
  /// document key it reads from. A document has two axes, this package's
  /// `format` version and the host's `schema` version, and telling somebody
  /// the format is at 3 when it is the schema that is at 3 sends them looking
  /// on the wrong side of the boundary.
  static Map<String, Object?> upgrade(
    Map<String, Object?> document, {
    required int from,
    required int target,
    Map<int, GraphDocumentMigration> chain = standard,
    String label = 'format',
    String key = 'version',
  }) {
    var current = document;
    for (var version = from; version < target; version++) {
      final migration = chain[version];
      if (migration == null) {
        throw GraphDocumentVersionException(
          'This document is in $label version $from and this build reads '
          'version $target, but there is no migration from version $version '
          'to ${version + 1}.',
          found: from,
          supported: target,
          path: <Object>[key],
        );
      }
      current = migration(current);
    }
    return current;
  }
}
