import "dart:async";

import "package:flutter/material.dart";

class ExTextOutputController {
  void Function(String text)? _append;
  void Function()? _clear;

  void append(String text) {
    _append?.call(text);
  }

  void clear() {
    _clear?.call();
  }
}

class ExTextOutput extends StatefulWidget {
  final String labelText;
  final ExTextOutputController controller;

  const ExTextOutput({
    super.key,
    required this.labelText,
    required this.controller,
  });

  @override
  State<ExTextOutput> createState() => _ExTextOutputState();
}

class _ExTextOutputState extends State<ExTextOutput> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    widget.controller._append = append;
    widget.controller._clear = clear;
  }

  @override
  void didUpdateWidget(covariant ExTextOutput oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Re-wire controller if changed
    if (oldWidget.controller != widget.controller) {
      widget.controller._append = append;
      widget.controller._clear = clear;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Expanded(
    child: TextField(
      controller: _textController,
      scrollController: _scrollController,
      readOnly: true,
      expands: true,
      maxLines: null,
      textAlignVertical: TextAlignVertical.top,
      keyboardType: TextInputType.multiline,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: widget.labelText,
        alignLabelWithHint: true,
      ),
      style: const TextStyle(
        fontFamily: "Courier New",
        fontWeight: FontWeight.bold,
        fontSize: 20,
      ),
    ),
  );

  void append(String text) {
    _textController.text += text;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        unawaited(
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          ),
        );
      }
    });
  }

  void clear() {
    _textController.text = "";
  }
}
