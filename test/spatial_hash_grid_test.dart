import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

void main() {
  group('SpatialHashGrid', () {
    test('queries by area and by point', () {
      final grid = SpatialHashGrid(cellSize: 100)
        ..put('a', const Rect.fromLTWH(0, 0, 50, 50))
        ..put('b', const Rect.fromLTWH(500, 500, 50, 50));

      expect(grid.queryRect(const Rect.fromLTWH(-10, -10, 30, 30)), <String>{
        'a',
      });
      expect(grid.queryRect(const Rect.fromLTWH(490, 490, 30, 30)), <String>{
        'b',
      });
      expect(grid.queryRect(const Rect.fromLTWH(200, 200, 50, 50)), isEmpty);

      expect(grid.queryPoint(const Offset(25, 25)), <String>{'a'});
      expect(grid.queryPoint(const Offset(300, 300)), isEmpty);
    });

    test('finds entries spanning several cells', () {
      final grid = SpatialHashGrid(cellSize: 100)
        ..put('wide', const Rect.fromLTWH(50, 50, 300, 20));

      expect(grid.queryPoint(const Offset(320, 60)), <String>{'wide'});
      expect(grid.queryRect(const Rect.fromLTWH(200, 55, 5, 5)), <String>{
        'wide',
      });
    });

    test('moving an entry leaves no stale references', () {
      final grid = SpatialHashGrid(cellSize: 100)
        ..put('a', const Rect.fromLTWH(0, 0, 50, 50))
        ..put('a', const Rect.fromLTWH(800, 800, 50, 50));

      expect(grid.queryPoint(const Offset(25, 25)), isEmpty);
      expect(grid.queryPoint(const Offset(825, 825)), <String>{'a'});
      expect(grid.length, 1);
      expect(grid.cellReferences, 1);
    });

    test('removing drops every cell reference', () {
      final grid = SpatialHashGrid(cellSize: 100)
        ..put('wide', const Rect.fromLTWH(0, 0, 500, 500))
        ..remove('wide');

      expect(grid.length, 0);
      expect(grid.cellReferences, 0);
      expect(grid.queryPoint(const Offset(10, 10)), isEmpty);
    });

    test('an entry too large to bucket is still found', () {
      // 1000x1000 cells of 10 is far past the per-entry cell cap.
      final grid = SpatialHashGrid(cellSize: 10)
        ..put('huge', const Rect.fromLTWH(0, 0, 10000, 10000))
        ..put('small', const Rect.fromLTWH(20, 20, 5, 5));

      expect(grid.cellReferences, 1, reason: 'huge entry must not be bucketed');
      expect(grid.queryPoint(const Offset(9000, 9000)), <String>{'huge'});
      expect(grid.queryPoint(const Offset(22, 22)), <String>{'huge', 'small'});
    });

    test('non-finite rects are rejected rather than hashed', () {
      final grid = SpatialHashGrid(cellSize: 100)
        ..put('a', const Rect.fromLTWH(0, 0, 10, 10))
        ..put('a', Rect.largest);

      expect(grid.queryPoint(Offset.zero), <String>{'a'});
      expect(grid.cellReferences, 0, reason: 'oversized, not bucketed');

      grid.put('a', const Rect.fromLTRB(0, 0, double.nan, 10));
      expect(grid.length, 0);
    });

    test('rebuild replaces the whole index', () {
      final grid = SpatialHashGrid(cellSize: 100)
        ..put('a', const Rect.fromLTWH(0, 0, 10, 10))
        ..rebuild(<String, Rect>{'b': const Rect.fromLTWH(0, 0, 10, 10)});

      expect(grid.queryPoint(const Offset(5, 5)), <String>{'b'});
      expect(grid.length, 1);
    });
  });
}
