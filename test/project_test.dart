import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

void main() {
  GraphNode node(String id, {Offset position = Offset.zero}) => GraphNode(
    id: id,
    position: position,
    width: 100,
    height: 50,
    data: <String, Object?>{'name': id},
    ports: const <NodePort>[
      NodePort.input(id: 'in'),
      NodePort.output(id: 'out'),
    ],
  );

  NodeEditorController controllerWith(
    List<GraphNode> nodes, {
    NodeGraphCodec? codec,
  }) {
    final controller = NodeEditorController(
      graph: NodeGraph(nodes: nodes),
      codec: codec,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  group('documents', () {
    test('the current state round-trips through JSON text', () {
      final controller = controllerWith(<GraphNode>[
        node('a'),
        node('b', position: const Offset(200, 0)),
      ]);
      controller.project
        ..meta = const <String, Object?>{'title': 'Lead routing'}
        ..appVersion = 'demo/1.0.0';
      controller.camera.viewport = const ViewportTransform(
        offset: Offset(-40, 20),
        scale: 0.75,
      );

      final text = controller.project.encodeToJson();
      final reopened = controllerWith(const <GraphNode>[]);
      final document = reopened.project.decodeJson(text);
      reopened.project.open(document);

      expect(reopened.graph, controller.graph);
      expect(reopened.camera.viewport, controller.camera.viewport);
      expect(
        reopened.project.meta,
        const <String, Object?>{'title': 'Lead routing'},
        reason: 'a title survives the round trip because opening adopts it',
      );
    });

    test('the encoded text is indented unless asked otherwise', () {
      final controller = controllerWith(<GraphNode>[node('a')]);

      expect(controller.project.encodeToJson(), contains('\n'));
      expect(
        controller.project.encodeToJson(indent: ''),
        isNot(contains('\n')),
      );
    });

    test('a document that cannot be read leaves the open one alone', () {
      final controller = controllerWith(<GraphNode>[node('a')]);
      final before = controller.graph;

      expect(
        () => controller.project.decodeJson(
          jsonEncode(<String, Object?>{'version': 99}),
        ),
        throwsA(isA<GraphDocumentVersionException>()),
      );
      expect(
        () => controller.project.decodeJson('not json at all'),
        throwsFormatException,
      );
      expect(
        () => controller.project.decodeJson('[1, 2, 3]'),
        throwsFormatException,
        reason: 'a JSON array is well-formed text but not a document',
      );

      expect(
        identical(controller.graph, before),
        isTrue,
        reason: 'decoding is separate from opening precisely so this holds',
      );
    });

    test('opening drops the history and keeps the camera when told', () {
      final controller = controllerWith(<GraphNode>[node('a')]);
      controller.addNode(node('b', position: const Offset(200, 0)));
      expect(controller.history.canUndo, isTrue);

      final camera = const ViewportTransform(offset: Offset(10, 10), scale: 2);
      controller.camera.viewport = camera;
      final document = controller.project.decode(
        controller.project.codec.encode(
          GraphDocument(graph: NodeGraph(nodes: <GraphNode>[node('c')])),
        ),
      );
      controller.project.open(document, restoreViewport: false);

      expect(controller.graph.nodes.keys, <String>['c']);
      expect(
        controller.history.canUndo,
        isFalse,
        reason: 'an undo across a load would restore half of a closed document',
      );
      expect(controller.camera.viewport, camera);
      expect(controller.selection.isEmpty, isTrue);
    });

    test('reset starts an empty document', () {
      final controller = controllerWith(<GraphNode>[node('a')]);
      controller.project.meta = const <String, Object?>{'title': 'Old'};
      controller.selection.selectNode('a');

      controller.project.reset();

      expect(controller.graph.nodes, isEmpty);
      expect(controller.selection.isEmpty, isTrue);
      expect(controller.project.meta, isEmpty);
      expect(controller.project.isDirty, isFalse);
    });
  });

  group('unsaved changes', () {
    test('a freshly built document is clean, and an edit is not', () {
      final controller = controllerWith(<GraphNode>[node('a')]);
      expect(
        controller.project.isDirty,
        isFalse,
        reason: 'the document as constructed is the baseline',
      );

      controller.moveNodes(<String, Offset>{'a': const Offset(10, 10)});
      expect(controller.project.isDirty, isTrue);
    });

    test('undoing back to the saved state reports clean again', () {
      final controller = controllerWith(<GraphNode>[node('a')]);

      controller.addNode(node('b', position: const Offset(200, 0)));
      expect(controller.project.isDirty, isTrue);

      controller.history.undo();
      expect(
        controller.project.isDirty,
        isFalse,
        reason: 'undo restores the very snapshot that was the baseline',
      );
    });

    test('writing metadata is an edit, and writing it back is not', () {
      final controller = controllerWith(<GraphNode>[node('a')]);

      controller.setNodeMetadata('a', <String, Object?>{'k': 1});
      expect(controller.project.isDirty, isTrue);

      controller.history.undo();
      expect(controller.project.isDirty, isFalse);

      controller.setNodeMetadata('a', const <String, Object?>{});
      expect(
        controller.project.isDirty,
        isFalse,
        reason: 'equal metadata is the map the node already had',
      );
    });

    test('measuring an auto-height node is not an edit', () {
      final controller = controllerWith(const <GraphNode>[]);
      controller.addNode(const GraphNode(id: 'auto', position: Offset.zero));
      controller.project.markSaved();

      controller.layout.reportMeasuredSize('auto', const Size(220, 140));

      expect(
        controller.project.isDirty,
        isFalse,
        reason: 'a measurement is not something the user typed',
      );
    });
  });

  group('storage', () {
    test(
      'save hands the encoded document to the sink and marks it clean',
      () async {
        final controller = controllerWith(<GraphNode>[node('a')]);
        Map<String, Object?>? written;
        controller.project.sink = (json) async {
          written = json;
          return true;
        };

        controller.addNode(node('b', position: const Offset(200, 0)));
        expect(controller.project.isDirty, isTrue);

        expect(await controller.project.save(), isTrue);
        expect(written, isNotNull);
        expect((written!['nodes']! as List<Object?>).length, 2);
        expect(controller.project.isDirty, isFalse);
        expect(controller.project.lastSaved, isNotNull);
      },
    );

    test('a save the user backs out of does not mark it clean', () async {
      final controller = controllerWith(<GraphNode>[node('a')]);
      controller.project.sink = (json) async => false;

      controller.addNode(node('b', position: const Offset(200, 0)));
      expect(await controller.project.save(), isFalse);
      expect(controller.project.isDirty, isTrue);
      expect(controller.project.lastSaved, isNull);
    });

    test('an edit made while the write is in flight stays unsaved', () async {
      final controller = controllerWith(<GraphNode>[node('a')]);
      final gate = Completer<bool>();
      controller.project.sink = (json) => gate.future;

      controller.addNode(node('b', position: const Offset(200, 0)));
      final saving = controller.project.save();

      controller.addNode(node('c', position: const Offset(400, 0)));
      gate.complete(true);
      expect(await saving, isTrue);

      expect(
        controller.project.isDirty,
        isTrue,
        reason: 'what reached storage is not what is on screen any more',
      );
    });

    test(
      'load decodes before it replaces, so a bad document changes nothing',
      () async {
        final controller = controllerWith(<GraphNode>[node('a')]);
        final before = controller.graph;
        controller.project.source = () async => <String, Object?>{
          'version': 99,
        };

        await expectLater(
          controller.project.load(),
          throwsA(isA<GraphDocumentVersionException>()),
        );
        expect(identical(controller.graph, before), isTrue);
      },
    );

    test('load returns null when the source has nothing', () async {
      final controller = controllerWith(<GraphNode>[node('a')]);
      controller.project.source = () async => null;

      expect(await controller.project.load(), isNull);
      expect(controller.graph.nodes.keys, <String>['a']);
    });

    test('saving or loading with nothing configured says which is missing', () {
      final controller = controllerWith(<GraphNode>[node('a')]);

      expect(controller.project.canSave, isFalse);
      expect(controller.project.canLoad, isFalse);
      expect(
        controller.project.save,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('sink'),
          ),
        ),
      );
      expect(
        controller.project.load,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('source'),
          ),
        ),
      );
    });

    test('a full cycle through a sink and back through a source', () async {
      Map<String, Object?>? storage;

      final source = controllerWith(<GraphNode>[
        node('a'),
        node('b', position: const Offset(200, 0)),
      ]);
      source.project.sink = (json) async {
        storage = json;
        return true;
      };
      await source.project.save();

      final target = controllerWith(const <GraphNode>[]);
      target.project.source = () async => storage;
      final document = await target.project.load();

      expect(document, isNotNull);
      expect(target.graph, source.graph);
      expect(target.project.isDirty, isFalse);
    });
  });
}
