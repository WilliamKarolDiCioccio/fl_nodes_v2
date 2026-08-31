import 'package:flutter/material.dart';

import '../model/node_group.dart';

/// The default editor for a group's name: a small modal with a text field.
///
/// A modal rather than a field in the handle, for the same reason a link
/// caption gets one — the handle is the group's only drag surface, and a text
/// field in it would take every press that landed on the name.
///
/// Returns the new name, or null if the user backed out. An empty result
/// restores [NodeGroup.defaultName].
Future<String?> showGroupNameEditor(
  BuildContext context, {
  required String initialValue,
  String title = 'Group name',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _GroupNameDialog(initialValue: initialValue, title: title),
  );
}

class _GroupNameDialog extends StatefulWidget {
  const _GroupNameDialog({required this.initialValue, required this.title});

  final String initialValue;
  final String title;

  @override
  State<_GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<_GroupNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initialValue.length,
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
            hintText: 'Leave empty for "${NodeGroup.defaultName}"',
          ),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Rename')),
      ],
    );
  }
}
