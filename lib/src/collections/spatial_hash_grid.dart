import 'dart:math' as math;
import 'dart:ui';

/// A uniform spatial hash over axis-aligned rects.
///
/// Buckets rects into fixed-size cells so that "what is in this region" and
/// "what is under this point" cost roughly the area queried rather than the
/// number of entries. That is what keeps viewport culling and pointer picking
/// flat as a graph grows into the thousands of nodes.
///
/// Modelled on the spatial hash in
/// [fl_nodes](https://github.com/WilliamKarolDiCioccio/fl_nodes), this
/// package's predecessor.
class SpatialHashGrid {
  SpatialHashGrid({this.cellSize = 512}) : assert(cellSize > 0);

  /// Side length of a cell. Best set to a small multiple of a typical node, so
  /// each entry lands in one or a few cells.
  final double cellSize;

  /// Entries whose footprint is too large to bucket usefully are kept aside
  /// and tested on every query, rather than being smeared over thousands of
  /// cells.
  static const int _maxCellsPerEntry = 256;

  final Map<_Cell, Set<String>> _cells = <_Cell, Set<String>>{};
  final Map<String, _Entry> _entries = <String, _Entry>{};
  final Set<String> _oversized = <String>{};

  int get length => _entries.length;

  /// Total number of cell references held, for diagnostics.
  int get cellReferences =>
      _cells.values.fold(0, (total, ids) => total + ids.length);

  Rect? rectOf(String id) => _entries[id]?.rect;

  /// Inserts or moves [id]. Re-bucketing is skipped when the entry still
  /// covers exactly the same cells, which is the common case while dragging.
  void put(String id, Rect rect) {
    if (!rect.isFinite) {
      remove(id);
      return;
    }

    final existing = _entries[id];
    if (existing != null && existing.rect == rect) return;

    final cells = _coveredCells(rect);
    if (cells == null) {
      if (existing != null) _detach(id, existing);
      _entries[id] = _Entry(rect, const <_Cell>[]);
      _oversized.add(id);
      return;
    }

    if (existing != null) {
      if (_sameCells(existing.cells, cells)) {
        _entries[id] = _Entry(rect, existing.cells);
        return;
      }
      _detach(id, existing);
    }

    for (final cell in cells) {
      (_cells[cell] ??= <String>{}).add(id);
    }
    _entries[id] = _Entry(rect, cells);
  }

  void remove(String id) {
    final entry = _entries.remove(id);
    if (entry != null) _detach(id, entry);
    _oversized.remove(id);
  }

  void clear() {
    _cells.clear();
    _entries.clear();
    _oversized.clear();
  }

  /// Replaces the whole index with [rects].
  void rebuild(Map<String, Rect> rects) {
    clear();
    rects.forEach(put);
  }

  /// Ids whose rect overlaps [bounds].
  Set<String> queryRect(Rect bounds) {
    final hits = <String>{};
    if (!bounds.isFinite) return hits;

    for (final id in _oversized) {
      if (_entries[id]!.rect.overlaps(bounds)) hits.add(id);
    }

    final cells = _coveredCells(bounds);
    if (cells == null) {
      // The query itself is unbounded; fall back to a full scan.
      _entries.forEach((id, entry) {
        if (entry.rect.overlaps(bounds)) hits.add(id);
      });
      return hits;
    }

    for (final cell in cells) {
      final ids = _cells[cell];
      if (ids == null) continue;
      for (final id in ids) {
        if (_entries[id]!.rect.overlaps(bounds)) hits.add(id);
      }
    }
    return hits;
  }

  /// Ids whose rect contains [point].
  Set<String> queryPoint(Offset point) {
    final hits = <String>{};
    for (final id in _oversized) {
      if (_entries[id]!.rect.contains(point)) hits.add(id);
    }

    final ids = _cells[_cellOf(point)];
    if (ids != null) {
      for (final id in ids) {
        if (_entries[id]!.rect.contains(point)) hits.add(id);
      }
    }
    return hits;
  }

  void _detach(String id, _Entry entry) {
    for (final cell in entry.cells) {
      final ids = _cells[cell];
      if (ids == null) continue;
      ids.remove(id);
      if (ids.isEmpty) _cells.remove(cell);
    }
    _oversized.remove(id);
  }

  _Cell _cellOf(Offset point) =>
      (x: (point.dx / cellSize).floor(), y: (point.dy / cellSize).floor());

  /// Cells covered by [rect], or null when that would be too many.
  List<_Cell>? _coveredCells(Rect rect) {
    final topLeft = _cellOf(rect.topLeft);
    final bottomRight = _cellOf(rect.bottomRight);
    final columns = bottomRight.x - topLeft.x + 1;
    final rows = bottomRight.y - topLeft.y + 1;
    if (columns <= 0 || rows <= 0) return const <_Cell>[];
    if (columns * rows > _maxCellsPerEntry) return null;

    final cells = <_Cell>[];
    for (var x = topLeft.x; x <= bottomRight.x; x++) {
      for (var y = topLeft.y; y <= bottomRight.y; y++) {
        cells.add((x: x, y: y));
      }
    }
    return cells;
  }

  static bool _sameCells(List<_Cell> a, List<_Cell> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Cell size that keeps a typical entry inside one or two cells.
  static double suggestedCellSize(double typicalExtent) =>
      math.max(64, typicalExtent * 2);
}

typedef _Cell = ({int x, int y});

class _Entry {
  const _Entry(this.rect, this.cells);

  final Rect rect;
  final List<_Cell> cells;
}
