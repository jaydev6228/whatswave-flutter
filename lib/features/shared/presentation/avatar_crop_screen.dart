import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Square crop step after picking a profile or group icon -- matches the
/// adjust-and-crop flow users expect from WhatsApp and similar apps.
class AvatarCropScreen extends StatefulWidget {
  const AvatarCropScreen({required this.sourceFile, super.key});

  final File sourceFile;

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  final CropController _cropController = CropController();
  var _isSaving = false;

  Future<void> _saveCrop(Uint8List bytes) async {
    if (_isSaving) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      final directory = await getTemporaryDirectory();
      final output = File(
        '${directory.path}/avatar-crop-${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await output.writeAsBytes(bytes, flush: true);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(output);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save that photo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Move and scale'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            key: const Key('avatar_crop_done_button'),
            onPressed: _isSaving ? null : _cropController.crop,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Done'),
          ),
        ],
      ),
      body: FutureBuilder<Uint8List>(
        future: widget.sourceFile.readAsBytes(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }
          final bytes = snapshot.data;
          if (bytes == null || bytes.isEmpty) {
            return Center(
              child: Text(
                'That photo could not be opened.',
                style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white),
              ),
            );
          }

          return Crop(
            controller: _cropController,
            image: bytes,
            aspectRatio: 1,
            radius: 0,
            baseColor: Colors.black,
            maskColor: Colors.black.withValues(alpha: 0.45),
            onCropped: (result) {
              switch (result) {
                case CropSuccess(:final croppedImage):
                  unawaited(_saveCrop(croppedImage));
                case CropFailure():
                  if (!mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not crop that photo.')),
                  );
              }
            },
          );
        },
      ),
    );
  }
}
