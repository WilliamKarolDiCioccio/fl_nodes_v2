import 'package:flutter/material.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

import 'prototype_nodes.dart';
import 'workflow_node.dart';

/// The body of the format node.
///
/// Worth comparing with `form_node_body.dart`: the write-back and transaction
/// pattern is identical, but nothing here decides what rows to draw. The rows
/// come from `prototypes.fieldsOf`, so they follow the format string — the same
/// source of truth that decides how many input ports the node has.
class FormatNodeBody extends StatefulWidget {
  const FormatNodeBody({super.key, required this.node, required this.isDark});

  final GraphNode node;
  final bool isDark;

  @override
  State<FormatNodeBody> createState() => _FormatNodeBodyState();
}

class _FormatNodeBodyState extends State<FormatNodeBody> {
  final TextEditingController _format = TextEditingController();
  final FocusNode _formatFocus = FocusNode();

  /// One controller per declared argument, created and disposed as the
  /// prototype adds and removes them.
  final Map<String, TextEditingController> _args =
      <String, TextEditingController>{};
  final Map<String, FocusNode> _argFocus = <String, FocusNode>{};

  bool _editing = false;

  /// Cached rather than looked up on demand.
  ///
  /// [dispose] has to commit a transaction that is still open, and by then the
  /// element is deactivated — reaching for an inherited widget there throws.
  late NodeEditorController _controller;

  @override
  void initState() {
    super.initState();
    _format.text = widget.node.formatText;
    _formatFocus.addListener(_handleFocusChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = NodeEditorScope.of(context).controller;
    _syncArgControllers();
  }

  @override
  void didUpdateWidget(FormatNodeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Undo, redo or a document load can change the model underneath. Only
    // adopt it while the field is not focused, or the caret jumps.
    if (!_formatFocus.hasFocus && widget.node.formatText != _format.text) {
      _format.text = widget.node.formatText;
    }
    _syncArgControllers();
  }

  @override
  void dispose() {
    // Never leave a transaction open behind us.
    if (_editing) _controller.history.commitTransaction();
    _format.dispose();
    _formatFocus.dispose();
    for (final controller in _args.values) {
      controller.dispose();
    }
    for (final focus in _argFocus.values) {
      focus.dispose();
    }
    super.dispose();
  }

  List<NodeField> get _declaredArgs => <NodeField>[
    for (final field in _controller.prototypes.fieldsOf(
      _controller.graph,
      widget.node,
    ))
      if (field.key.startsWith(argKeyPrefix)) field,
  ];

  void _syncArgControllers() {
    final live = <String>{for (final field in _declaredArgs) field.key};

    for (final key in live) {
      final value = (widget.node.data[key] as String?) ?? '';
      final existing = _args[key];
      if (existing == null) {
        _args[key] = TextEditingController(text: value);
        _argFocus[key] = FocusNode()..addListener(_handleFocusChange);
      } else if (!_argFocus[key]!.hasFocus && existing.text != value) {
        existing.text = value;
      }
    }

    for (final key in _args.keys.toList(growable: false)) {
      if (live.contains(key)) continue;
      _args.remove(key)!.dispose();
      _argFocus.remove(key)!.dispose();
    }
  }

  void _write(Map<String, Object?> entries) =>
      _controller.updateNode(widget.node.id, (node) => node.withData(entries));

  void _beginEdit() {
    if (_editing) return;
    _editing = true;
    _controller.history.beginTransaction();
  }

  void _endEdit() {
    if (!_editing) return;
    _editing = false;
    _controller.history.commitTransaction();
  }

  void _handleFocusChange() {
    final focused =
        _formatFocus.hasFocus ||
        _argFocus.values.any((focus) => focus.hasFocus);
    focused ? _beginEdit() : _endEdit();
  }

  bool _isWired(String key) {
    final slot = key.substring(argKeyPrefix.length);
    return _controller.graph
        .connectionsAt(PortRef(widget.node.id, 'arg_$slot'))
        .isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final muted = widget.isDark
        ? const Color(0xFF8C93A6)
        : const Color(0xFF6B7280);
    final fieldFill = widget.isDark
        ? const Color(0xFF1B1F29)
        : const Color(0xFFF2F4F8);
    final args = _declaredArgs;

    return Padding(
      padding: const EdgeInsets.all(CardMetrics.bodyPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: CardMetrics.fieldRowHeight,
            child: Center(
              child: TextField(
                controller: _format,
                focusNode: _formatFocus,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: fieldFill,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  hintText: 'Hello, {0}!',
                ),
                onChanged: (value) {
                  _beginEdit();
                  _write(<String, Object?>{'format': value});
                },
              ),
            ),
          ),
          for (final field in args)
            SizedBox(
              height: CardMetrics.rowHeight,
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 30,
                    child: Text(
                      field.label ?? field.key,
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ),
                  Expanded(
                    child: _isWired(field.key)
                        // A wired argument takes its value from the graph, so
                        // there is nothing to type here.
                        ? Text(
                            'from link',
                            style: TextStyle(
                              fontSize: 11,
                              color: muted,
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        : TextField(
                            controller: _args[field.key],
                            focusNode: _argFocus[field.key],
                            style: const TextStyle(fontSize: 11),
                            decoration: InputDecoration(
                              isDense: true,
                              filled: true,
                              fillColor: fieldFill,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              hintText: 'literal',
                            ),
                            onChanged: (value) {
                              _beginEdit();
                              _write(<String, Object?>{field.key: value});
                            },
                          ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The body of the fan-out node: one row per exit.
///
/// Stateless, because the node holds no fields — its whole shape comes from how
/// it is wired. Wire the free exit at the bottom and a new one appears beneath
/// it, because the port family is rebuilt from the link state.
class FanOutNodeBody extends StatelessWidget {
  const FanOutNodeBody({super.key, required this.node, required this.isDark});

  final GraphNode node;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final graph = NodeEditorScope.of(context).controller.graph;
    final muted = isDark ? const Color(0xFF8C93A6) : const Color(0xFF6B7280);
    final exits = <NodePort>[
      for (final port in node.ports)
        if (port.isOutput) port,
    ];

    return Padding(
      padding: const EdgeInsets.all(CardMetrics.bodyPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final port in exits)
            SizedBox(
              height: CardMetrics.rowHeight,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  port.label ?? port.id,
                  style: TextStyle(
                    fontSize: 12,
                    color: muted,
                    // The free exit is the invitation: wiring it grows the node.
                    fontStyle:
                        graph.connectionsAt(PortRef(node.id, port.id)).isEmpty
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
