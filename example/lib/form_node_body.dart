import 'package:flutter/material.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

import 'workflow_node.dart';

/// A node body made of ordinary Flutter form widgets.
///
/// Two things are worth copying from here:
///
/// * The widgets read from and write back to `node.data` through the
///   controller, so edits go through the same history as dragging or wiring —
///   `Ctrl+Z` undoes a typed subject as readily as a moved node.
/// * Continuous edits are wrapped in a transaction. Typing writes to the model
///   on every keystroke so the canvas stays in sync, but the whole editing
///   session collapses into one undo step instead of one per character.
class FormNodeBody extends StatefulWidget {
  const FormNodeBody({super.key, required this.node, required this.isDark});

  final GraphNode node;
  final bool isDark;

  static const List<Color> swatches = <Color>[
    Color(0xFF6E97F0),
    Color(0xFF5BC48A),
    Color(0xFFE0A64A),
    Color(0xFFE05A6B),
    Color(0xFFB57BD8),
  ];

  @override
  State<FormNodeBody> createState() => _FormNodeBodyState();
}

class _FormNodeBodyState extends State<FormNodeBody> {
  late final TextEditingController _subject = TextEditingController(
    text: widget.node.subject,
  );
  final FocusNode _subjectFocus = FocusNode();

  /// True while a transaction is open, so focus and slider callbacks cannot
  /// unbalance begin/commit.
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _subjectFocus.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(FormNodeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Undo, redo or a document load can change the model behind the field.
    // Only adopt it while the user is not mid-edit, or the caret jumps.
    if (!_subjectFocus.hasFocus && widget.node.subject != _subject.text) {
      _subject.text = widget.node.subject;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = NodeEditorScope.of(context).controller;
  }

  @override
  void dispose() {
    if (_editing) _controller.history.commitTransaction();
    _subjectFocus
      ..removeListener(_handleFocusChange)
      ..dispose();
    _subject.dispose();
    super.dispose();
  }

  /// Cached rather than looked up on demand.
  ///
  /// [dispose] has to commit a transaction that is still open, and by then the
  /// element is deactivated — reaching for an inherited widget there throws.
  late NodeEditorController _controller;

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

  void _handleFocusChange() =>
      _subjectFocus.hasFocus ? _beginEdit() : _endEdit();

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final muted = widget.isDark
        ? const Color(0xFF98A0B4)
        : const Color(0xFF5C6478);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/thumbnail.png',
                  width: 46,
                  height: 46,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _subject,
                  focusNode: _subjectFocus,
                  maxLines: null,
                  style: TextStyle(fontSize: 12, color: muted),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Subject',
                    labelStyle: TextStyle(fontSize: 11, color: muted),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (value) {
                    _beginEdit();
                    _write(<String, Object?>{'subject': value});
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _CheckRow(
            label: 'Send as HTML',
            value: node.sendAsHtml,
            color: muted,
            onChanged: (value) =>
                _write(<String, Object?>{'sendAsHtml': value}),
          ),
          _SliderRow(
            label: 'Delay ${node.delayMinutes.round()} min',
            value: node.delayMinutes,
            color: muted,
            onStart: _beginEdit,
            onChanged: (value) =>
                _write(<String, Object?>{'delayMinutes': value}),
            onEnd: _endEdit,
          ),
          _SwatchRow(
            selected: node.labelColor,
            color: muted,
            onPicked: (value) =>
                _write(<String, Object?>{'labelColor': value.toARGB32()}),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final Color color;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 30,
          height: 30,
          child: Checkbox(
            value: value,
            visualDensity: VisualDensity.compact,
            onChanged: (next) => onChanged(next ?? false),
          ),
        ),
        Text(label, style: TextStyle(fontSize: 11.5, color: color)),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.color,
    required this.onStart,
    required this.onChanged,
    required this.onEnd,
  });

  final String label;
  final double value;
  final Color color;
  final VoidCallback onStart;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: TextStyle(fontSize: 11.5, color: color)),
        SizedBox(
          height: 24,
          child: Slider(
            value: value,
            max: 60,
            // One undo step for the whole drag, not one per frame.
            onChangeStart: (_) => onStart(),
            onChanged: onChanged,
            onChangeEnd: (_) => onEnd(),
          ),
        ),
      ],
    );
  }
}

class _SwatchRow extends StatelessWidget {
  const _SwatchRow({
    required this.selected,
    required this.color,
    required this.onPicked,
  });

  final Color selected;
  final Color color;
  final ValueChanged<Color> onPicked;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: <Widget>[
          Text('Label', style: TextStyle(fontSize: 11.5, color: color)),
          const SizedBox(width: 10),
          MenuAnchor(
            menuChildren: <Widget>[
              for (final swatch in FormNodeBody.swatches)
                MenuItemButton(
                  onPressed: () => onPicked(swatch),
                  leadingIcon: _Swatch(color: swatch, size: 14),
                  child: Text(
                    '#${swatch.toARGB32().toRadixString(16).substring(2)}',
                  ),
                ),
            ],
            builder: (context, menu, _) => InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => menu.isOpen ? menu.close() : menu.open(),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _Swatch(color: selected, size: 16),
                    Icon(Icons.arrow_drop_down, size: 16, color: color),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: const Color(0x33000000)),
      ),
    );
  }
}
