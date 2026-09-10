import 'package:flutter/material.dart';

Future<String?> showRouteStoryQuestionDialog(BuildContext context) {
  var question = '';
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Ask about this route'),
      content: TextField(
        onChanged: (value) => question = value,
        autofocus: true,
        maxLength: 300,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Question',
          hintText: 'What happened near here?',
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(question),
          child: const Text('Ask'),
        ),
      ],
    ),
  );
}
