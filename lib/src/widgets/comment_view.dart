import 'package:flutter/material.dart';

import '../controller/node_editor_controller.dart';
import '../model/graph_node.dart';
import '../model/node_comment.dart';
import 'node_editor_scope.dart';

/// The body of a comment note: a text field in a grey slab.
///
/// **Deliberately unthemed, but not colour-blind.** Every other colour on the
/// canvas comes from `NodeEditorTheme` or from the host's node builder; these
/// do not. A note is the app user's own annotation rather than part of the
/// graph's visual language, and one that picked up the accent colour would
/// read as one more kind of node.
///
/// What that does *not* mean is one fixed set of colours. It used to, and
/// near-white ink on a light canvas is unreadable. So there are two fixed
/// palettes and the canvas picks between them by its own background — no
/// accent either way, and still nothing owed to the host's `Theme`. The field
/// also sets [InputDecoration.filled] to false rather than leaving it unset:
/// a host whose `InputDecorationTheme` fills its inputs would otherwise paint
/// a solid box across the note, which is precisely the promise this class
/// makes and could not previously keep.
///
/// There is no title bar. The only chrome is [_padding] — a ring of slab wide
/// enough to grab, since the text field takes any press that lands on it and a
/// note with no margin could be typed in but never moved.
class CommentView extends StatefulWidget {
  const CommentView({super.key, required this.node, required this.controller});

  final GraphNode node;
  final NodeEditorController controller;

  @override
  State<CommentView> createState() => _CommentViewState();
}

/// Slab, its edge, the writing on it, and the placeholder. Fixed on purpose;
/// see [CommentView].
@immutable
class _CommentPalette {
  const _CommentPalette({
    required this.fill,
    required this.edge,
    required this.ink,
    required this.placeholder,
  });

  final Color fill;
  final Color edge;
  final Color ink;
  final Color placeholder;

  /// The slab is translucent in both, so it reads as the same object lit from
  /// either side: lighter than a dark canvas, darker than a light one. The
  /// light one is the weaker wash because the same alpha over a pale canvas
  /// lands as a heavy blot rather than a note.
  static const _CommentPalette onDark = _CommentPalette(
    fill: Color.fromARGB(127, 109, 114, 124),
    edge: Color(0xFF868C96),
    ink: Color(0xFFF2F3F5),
    placeholder: Color(0xFFBEC3CB),
  );

  static const _CommentPalette onLight = _CommentPalette(
    fill: Color.fromARGB(64, 109, 114, 124),
    edge: Color(0xFF9EA5B0),
    ink: Color(0xFF1B1E24),
    placeholder: Color(0xFF6B7280),
  );

  /// Read off the canvas rather than off `Theme.of`, so a host that runs a
  /// light app around a dark canvas — or the other way about — still gets a
  /// legible note.
  static _CommentPalette forCanvas(Color background) =>
      background.computeLuminance() > 0.5 ? onLight : onDark;
}

const double _radius = 8;
const double _padding = 12;
const double _fontSize = 13;

class _CommentViewState extends State<CommentView> {
  late final TextEditingController _text = TextEditingController(
    text: NodeComment.textOf(widget.node),
  );
  final FocusNode _focus = FocusNode(debugLabel: 'NodeComment');

  @override
  void initState() {
    super.initState();
    _focus.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(CommentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only when it actually differs. Assigning `text` moves the caret to the
    // end, and every keystroke comes back through here carrying the value it
    // just wrote — so an unconditional assignment would jump the caret to the
    // end of the note on every character typed anywhere but there.
    final incoming = NodeComment.textOf(widget.node);
    if (incoming != _text.text) _text.text = incoming;
  }

  @override
  void dispose() {
    _focus.removeListener(_handleFocusChange);
    // Closes the run of typing this note may still own. A plain field write,
    // so unlike a commit it is safe from `dispose`, which can run mid-layout
    // when the note is culled off screen.
    widget.controller.endCommentEdit();
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focus.hasFocus) widget.controller.endCommentEdit();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _CommentPalette.forCanvas(
      NodeEditorScope.of(context).theme.background,
    );
    return Material(
      color: palette.fill,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(_radius)),
        side: BorderSide(color: palette.edge),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_padding),
        child: TextField(
          controller: _text,
          focusNode: _focus,
          onChanged: (value) =>
              widget.controller.setCommentText(widget.node.id, value),
          // Grows with what is written, and stays grabbable when it is empty.
          minLines: 2,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          cursorColor: palette.ink,
          style: TextStyle(
            color: palette.ink,
            fontSize: _fontSize,
            height: 1.35,
          ),
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            // Explicit, not inherited: see [CommentView].
            filled: false,
            contentPadding: EdgeInsets.zero,
            hintText: 'Comment',
            hintStyle: TextStyle(
              color: palette.placeholder,
              fontSize: _fontSize,
            ),
          ),
        ),
      ),
    );
  }
}
