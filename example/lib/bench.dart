import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

import 'sample_graph.dart';
import 'workflow_node_card.dart';

/// An on-device frame benchmark, for the half `flutter test` cannot see.
///
/// The widget benchmarks measure the UI thread, and the UI thread turned out
/// to be flat across resolutions — so anything that scales with pixels is on
/// the raster thread, and the only way to see that is to actually rasterise.
/// This runs a scripted drag against a real window and reports what
/// [FrameTiming] says about both threads.
///
/// ```sh
/// flutter run --profile -d linux -t lib/bench.dart
/// flutter run --profile -d linux -t lib/bench.dart --dart-define=SHADOW=off
/// ```
///
/// | define | default | what it removes |
/// | --- | --- | --- |
/// | `NODES` | 500 | graph size |
/// | `GRID` | on | the background grid, a full-viewport fragment shader |
/// | `SHADOW` | on | the blurred drop shadow on every card |
/// | `FRAMES` | 240 | how long to run |
const int kNodes = int.fromEnvironment('NODES', defaultValue: 500);
const int kFrames = int.fromEnvironment('FRAMES', defaultValue: 240);
const String kGrid = String.fromEnvironment('GRID', defaultValue: 'on');
const String kShadow = String.fromEnvironment('SHADOW', defaultValue: 'on');

/// `bare` renders a plain box instead of the editor, to price the platform
/// itself; `empty` renders the editor with no nodes in it.
const String kMode = String.fromEnvironment('MODE', defaultValue: 'full');

void main() => runApp(const _BenchApp());

class _BenchApp extends StatelessWidget {
  const _BenchApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(),
    home: const _BenchPage(),
  );
}

class _BenchPage extends StatefulWidget {
  const _BenchPage();

  @override
  State<_BenchPage> createState() => _BenchPageState();
}

class _BenchPageState extends State<_BenchPage>
    with SingleTickerProviderStateMixin {
  late final NodeEditorController _controller;
  final GlobalKey<NodeEditorState> _editorKey = GlobalKey<NodeEditorState>();
  late final Ticker _ticker;

  final List<FrameTiming> _timings = <FrameTiming>[];
  int _frame = 0;
  int _spin = 0;
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    _controller = NodeEditorController(
      graph: kMode == 'empty' ? NodeGraph() : buildStressGraph(kNodes),
    );
    _ticker = createTicker(_tick);
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (kMode == 'full') _editorKey.currentState?.fitToContent();
      // A few frames of settling before anything is counted.
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        _recording = true;
        _ticker.start();
      });
    });
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _ticker.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    if (_recording) _timings.addAll(timings);
  }

  /// Moves one node every frame: the same work a pointer drag does, without
  /// needing a pointer.
  void _tick(Duration elapsed) {
    if (kMode == 'full') {
      _controller.translateNodes(const <String>['n0'], const Offset(2, 1));
    } else {
      // Nothing to drag, so dirty the frame the cheapest way there is.
      setState(() => _spin = (_spin + 1) % 1000);
    }
    if (++_frame >= kFrames) {
      _ticker.stop();
      _report();
    }
  }

  void _report() {
    final view = View.of(context);
    double percentile(List<double> sorted, double p) =>
        sorted[(sorted.length * p).clamp(0, sorted.length - 1).floor()];

    String line(String name, Duration Function(FrameTiming t) pick) {
      final values = _timings.map((t) => pick(t).inMicroseconds / 1000).toList()
        ..sort();
      if (values.isEmpty) return '$name: no frames';
      return '$name  p50 ${percentile(values, 0.5).toStringAsFixed(2)}ms  '
          'p90 ${percentile(values, 0.9).toStringAsFixed(2)}ms  '
          'p99 ${percentile(values, 0.99).toStringAsFixed(2)}ms  '
          'max ${values.last.toStringAsFixed(2)}ms';
    }

    final editor = _editorKey.currentState;
    final drawn = editor == null
        ? 0
        : _controller.layout
              .nodesIn(
                _controller.camera.viewport.visibleSceneRect(
                  editor.viewportSize,
                ),
              )
              .length;

    stdout.writeln(
      '\n=== node editor frame benchmark ===\n'
      'window ${view.physicalSize.width.toInt()}x'
      '${view.physicalSize.height.toInt()} physical, '
      'dpr ${view.devicePixelRatio}\n'
      '$kNodes nodes, $drawn drawn, '
      'zoom ${(_controller.camera.viewport.scale * 100).round()}%, '
      'grid $kGrid, shadow $kShadow, mode $kMode\n'
      '${_timings.length} frames\n'
      '${line('BUILD ', (t) => t.buildDuration)}\n'
      '${line('RASTER', (t) => t.rasterDuration)}\n'
      '${line('TOTAL ', (t) => t.totalSpan)}',
    );
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    if (kMode == 'bare') {
      return Scaffold(
        body: Center(
          child: Text('$_spin', style: const TextStyle(fontSize: 40)),
        ),
      );
    }
    return Scaffold(
      body: NodeEditor(
        key: _editorKey,
        controller: _controller,
        theme: NodeEditorTheme.dark().copyWith(showGrid: kGrid == 'on'),
        nodeBuilder: (context, node, state) => WorkflowNodeCard(
          node: node,
          state: state,
          isDark: true,
          shadow: kShadow == 'on',
        ),
      ),
    );
  }
}
