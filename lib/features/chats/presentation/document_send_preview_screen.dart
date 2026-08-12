import 'package:flutter/material.dart';

import '../domain/chat_attachment.dart';

/// File attachment + optional caption from the document review step.
class DocumentSendDraft {
  const DocumentSendDraft({
    required this.attachment,
    required this.caption,
  });

  final ChatAttachment attachment;
  final String? caption;
}

/// A lightweight review screen for picked documents -- shows the file card
/// and an optional caption field before sending (matching photo/video flow).
class DocumentSendPreviewScreen extends StatefulWidget {
  const DocumentSendPreviewScreen({
    required this.attachment,
    super.key,
  });

  final ChatAttachment attachment;

  @override
  State<DocumentSendPreviewScreen> createState() =>
      _DocumentSendPreviewScreenState();
}

class _DocumentSendPreviewScreenState extends State<DocumentSendPreviewScreen> {
  late final TextEditingController _captionController;

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController();
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  void _confirmSend() {
    final caption = _captionController.text.trim();
    Navigator.of(context).pop(
      DocumentSendDraft(
        attachment: widget.attachment,
        caption: caption.isEmpty ? null : caption,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attachment = widget.attachment;
    final kindVisual =
        documentKindVisual(attachment.documentKind, attachment.tintColor);

    return Scaffold(
      key: const Key('document_send_preview_screen'),
      appBar: AppBar(
        title: const Text('Send document'),
        actions: [
          TextButton(
            key: const Key('document_send_preview_send_button'),
            onPressed: _confirmSend,
            child: const Text('Send'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        kindVisual.$1,
                        color: kindVisual.$2,
                        size: 36,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              attachment.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              attachment.details,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.68),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('document_send_preview_caption_field'),
                controller: _captionController,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Add a caption (optional)',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
