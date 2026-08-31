import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

/// Does an ordinary Flutter form actually work inside a node?
void main() {
  GraphNode node(String id, Offset position, {double? height = 220}) =>
      GraphNode(
        id: id,
        position: position,
        width: 240,
        height: height,
        ports: const <NodePort>[
          NodePort.input(id: 'in'),
          NodePort.output(id: 'out'),
        ],
      );

  Widget harness(
    NodeEditorController controller,
    NodeWidgetBuilder nodeBuilder,
  ) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 800,
          height: 600,
          child: NodeEditor(
            controller: controller,
            theme: NodeEditorTheme.dark(),
            nodeBuilder: nodeBuilder,
          ),
        ),
      ),
    ),
  );

  testWidgets('a checkbox toggles without dragging the node', (tester) async {
    final controller = NodeEditorController(
      graph: NodeGraph(nodes: <GraphNode>[node('a', const Offset(60, 60))]),
    );
    addTearDown(controller.dispose);
    var checked = false;

    await tester.pumpWidget(
      harness(
        controller,
        (context, graphNode, state) => StatefulBuilder(
          builder: (context, setState) => ColoredBox(
            color: const Color(0xFF2A2E38),
            child: Checkbox(
              value: checked,
              onChanged: (value) => setState(() => checked = value ?? false),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(checked, isTrue);
    expect(controller.graph.node('a')!.position, const Offset(60, 60));
  });

  testWidgets('tapping a text field inside a node focuses it', (tester) async {
    final controller = NodeEditorController(
      graph: NodeGraph(nodes: <GraphNode>[node('a', const Offset(60, 60))]),
    );
    addTearDown(controller.dispose);
    final text = TextEditingController(text: 'ab');
    addTearDown(text.dispose);
    final fieldFocus = FocusNode();
    addTearDown(fieldFocus.dispose);

    await tester.pumpWidget(
      harness(
        controller,
        (context, graphNode, state) => ColoredBox(
          color: const Color(0xFF2A2E38),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(controller: text, focusNode: fieldFocus),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(fieldFocus.hasFocus, isTrue, reason: 'a tap must focus the field');

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pumpAndSettle();
    expect(text.text, 'hello');
  });

  testWidgets('editor shortcuts do not fire while a node field has focus', (
    tester,
  ) async {
    final controller = NodeEditorController(
      graph: NodeGraph(nodes: <GraphNode>[node('a', const Offset(60, 60))]),
    );
    addTearDown(controller.dispose);
    final fieldFocus = FocusNode();
    addTearDown(fieldFocus.dispose);

    await tester.pumpWidget(
      harness(
        controller,
        (context, graphNode, state) => ColoredBox(
          color: const Color(0xFF2A2E38),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[TextField(focusNode: fieldFocus)],
          ),
        ),
      ),
    );

    controller.selection.selectNode('a');
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(fieldFocus.hasFocus, isTrue);

    // Delete belongs to the text field here, not to the canvas.
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(
      controller.graph.nodes,
      hasLength(1),
      reason: 'the node must survive typing in its own text field',
    );
  });

  testWidgets('a slider drags without moving the node', (tester) async {
    final controller = NodeEditorController(
      graph: NodeGraph(nodes: <GraphNode>[node('a', const Offset(60, 60))]),
    );
    addTearDown(controller.dispose);
    var value = 0.0;

    await tester.pumpWidget(
      harness(
        controller,
        (context, graphNode, state) => StatefulBuilder(
          builder: (context, setState) => ColoredBox(
            color: const Color(0xFF2A2E38),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Slider(
                  value: value,
                  onChanged: (next) => setState(() => value = next),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(Slider), const Offset(60, 0));
    await tester.pumpAndSettle();

    expect(value, greaterThan(0), reason: 'slider should have moved');
    expect(
      controller.graph.node('a')!.position,
      const Offset(60, 60),
      reason: 'the node must not move with it',
    );
  });

  testWidgets('scrolling a list inside a node does not zoom the canvas', (
    tester,
  ) async {
    final controller = NodeEditorController(
      graph: NodeGraph(nodes: <GraphNode>[node('a', const Offset(60, 60))]),
    );
    addTearDown(controller.dispose);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      harness(
        controller,
        (context, graphNode, state) => ColoredBox(
          color: const Color(0xFF2A2E38),
          child: ListView.builder(
            controller: scrollController,
            itemCount: 40,
            itemExtent: 30,
            itemBuilder: (context, index) => Text('row $index'),
          ),
        ),
      ),
    );

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final inside = tester.getCenter(find.byType(ListView));
    await tester.sendEventToBinding(pointer.hover(inside));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await tester.pumpAndSettle();

    expect(scrollController.offset, greaterThan(0), reason: 'list scrolled');
    expect(
      controller.camera.viewport.scale,
      1.0,
      reason: 'canvas must not zoom',
    );
  });

  testWidgets('the node still drags from a non-interactive area', (
    tester,
  ) async {
    final controller = NodeEditorController(
      graph: NodeGraph(nodes: <GraphNode>[node('a', const Offset(60, 60))]),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      harness(
        controller,
        (context, graphNode, state) => Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              key: const ValueKey<String>('header'),
              height: 40,
              color: const Color(0xFF3A4155),
            ),
            const TextField(),
          ],
        ),
      ),
    );

    await tester.drag(
      find.byKey(const ValueKey<String>('header')),
      const Offset(40, 25),
    );
    await tester.pumpAndSettle();

    expect(controller.graph.node('a')!.position, const Offset(100, 85));
  });

  testWidgets('an auto-height node grows with its content, ports following', (
    tester,
  ) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[node('a', const Offset(60, 60), height: null)],
      ),
    );
    addTearDown(controller.dispose);
    var lines = 1;

    await tester.pumpWidget(
      harness(
        controller,
        (context, graphNode, state) => StatefulBuilder(
          builder: (context, setState) => ColoredBox(
            color: const Color(0xFF2A2E38),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (var i = 0; i < lines; i++)
                  const SizedBox(height: 40, child: Text('row')),
                TextButton(
                  key: const ValueKey<String>('add'),
                  onPressed: () => setState(() => lines++),
                  child: const Text('add'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final before = controller.layout.sizeOf(controller.graph.node('a')!).height;
    // Handles are painted, so the thing to check is the geometry the painter
    // and the picker share, not a widget's position.
    final portBefore = controller.layout.portPosition(
      const PortRef('a', 'out'),
    );

    await tester.tap(find.byKey(const ValueKey<String>('add')));
    await tester.pumpAndSettle();

    final after = controller.layout.sizeOf(controller.graph.node('a')!).height;
    final portAfter = controller.layout.portPosition(const PortRef('a', 'out'));

    expect(after, before + 40);
    expect(portAfter!.dy, greaterThan(portBefore!.dy), reason: 'port follows');
  });

  testWidgets('a popup opened from inside a node works under zoom', (
    tester,
  ) async {
    final controller = NodeEditorController(
      graph: NodeGraph(nodes: <GraphNode>[node('a', const Offset(60, 60))]),
      viewport: const ViewportTransform(scale: 1.5),
    );
    addTearDown(controller.dispose);
    Color? picked;

    await tester.pumpWidget(
      harness(
        controller,
        (context, graphNode, state) => ColoredBox(
          color: const Color(0xFF2A2E38),
          child: Align(
            alignment: Alignment.topLeft,
            child: MenuAnchor(
              menuChildren: <Widget>[
                for (final swatch in const <Color>[
                  Color(0xFFE05A6B),
                  Color(0xFF5BC48A),
                ])
                  MenuItemButton(
                    onPressed: () => picked = swatch,
                    child: SizedBox(
                      width: 60,
                      height: 20,
                      child: ColoredBox(color: swatch),
                    ),
                  ),
              ],
              builder: (context, menu, _) => TextButton(
                key: const ValueKey<String>('swatch'),
                onPressed: menu.open,
                child: const Text('colour'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('swatch')));
    await tester.pumpAndSettle();

    expect(find.byType(MenuItemButton), findsNWidgets(2));
    await tester.tap(find.byType(MenuItemButton).last);
    await tester.pumpAndSettle();

    expect(picked, const Color(0xFF5BC48A));
  });
}
