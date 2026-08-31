import 'package:flutter/material.dart';

/// The default editor for a link caption: a small modal with a text field.
///
/// Captions are canvas text rather than widgets, so there is nothing to focus
/// in place. A modal is the simplest thing that works and it keeps a text field
/// off the canvas, where it would have to be positioned, scaled, clipped and
/// hit-tested along with everything else.
///
/// Returns the new caption, or null if the user backed out. An empty result
/// clears the caption.
Future<String?> showConnectionLabelEditor(
  BuildContext context, {
  required String? initialValue,
  String title = 'Link label',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _ConnectionLabelDialog(initialValue: initialValue, title: title),
  );
}

class _ConnectionLabelDialog extends StatefulWidget {
  const _ConnectionLabelDialog({
    required this.initialValue,
    required this.title,
  });

  final String? initialValue;
  final String title;

  @override
  State<_ConnectionLabelDialog> createState() => _ConnectionLabelDialogState();
}

class _ConnectionLabelDialogState extends State<_ConnectionLabelDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue ?? '')
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: (widget.initialValue ?? '').length,
        );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Leave empty to remove the caption',
          ),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
