import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

void main() {
  test('the grid shader asset key resolves and the program compiles', () async {
    final program = await GridShader.load();

    expect(
      program,
      isNotNull,
      reason: 'no key in ${GridShader.assetKeys} resolved',
    );
    expect(GridShader.createShader(), isNotNull);
  });

  test('configuring the shader binds every uniform slot', () async {
    await GridShader.load();
    final shader = GridShader.createShader();
    expect(shader, isNotNull);

    // Setting a slot past the last declared uniform must throw, which pins the
    // Dart-side indices to the uniform list in grid.frag.
    GridShader.configure(
      shader!,
      const ViewportTransform(offset: Offset(12, 34), scale: 1.5),
      NodeEditorTheme.dark(),
    );
    expect(() => shader.setFloat(18, 0), throwsA(isA<Error>()));
    shader.dispose();
  });

  test('isTooDense reports when even major lines would alias', () {
    final theme = NodeEditorTheme.dark();

    expect(GridShader.isTooDense(theme, 1), isFalse);
    expect(GridShader.isTooDense(theme, 0.01), isTrue);
  });

  testWidgets('the editor picks the shader up once it loads', (tester) async {
    final controller = NodeEditorController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NodeEditor(
            controller: controller,
            theme: NodeEditorTheme.dark(),
            nodeBuilder: (context, node, state) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.painter)
        .whereType<GridPainter>()
        .single;

    expect(painter.shader, isNotNull);
  });
}
