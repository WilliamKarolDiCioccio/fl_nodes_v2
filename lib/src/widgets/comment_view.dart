import 'package:flutter/material.dart';

import '../controller/node_editor_controller.dart';
import '../model/graph_node.dart';
import '../model/node_comment.dart';

/// The body of a comment note: a text field in a grey slab.
///
/// **Deliberately unthemed.** Every other colour on the canvas comes from
/// `NodeEditorTheme` or from the host's node builder; these do not, and are
/// the same in a light app and a dark one. A note is the app user's own
/// annotation rather than part of the graph's visual language, and a note that
/// picked up the accent colour would read as one more kind of node.
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
const Color _fill = Color.fromARGB(127, 109, 114, 124);
const Color _edge = Color(0xFF868C96);
const Color _ink = Color(0xFFF2F3F5);
const Color _placeholder = Color(0xFFBEC3CB);

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
    return Material(
      color: _fill,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(_radius)),
        side: BorderSide(color: _edge),
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
          cursorColor: _ink,
          style: const TextStyle(
            color: _ink,
            fontSize: _fontSize,
            height: 1.35,
          ),
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            hintText: 'Comment',
            hintStyle: TextStyle(color: _placeholder, fontSize: _fontSize),
          ),
        ),
      ),
    );
  }
}
