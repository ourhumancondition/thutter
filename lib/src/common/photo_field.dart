import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'pb_image.dart';

/// Edit-screen control: shows the current image (server or freshly picked) and
/// lets the user pick a replacement. Returns the chosen local path via [onPick];
/// nothing is uploaded until the record syncs.
class PhotoField extends StatelessWidget {
  const PhotoField({
    super.key,
    required this.collection,
    required this.recordId,
    required this.filename,
    required this.pendingPath,
    required this.onPick,
    this.label = 'Photo',
  });

  final String collection;
  final String recordId;
  final String? filename;
  final String? pendingPath;
  final ValueChanged<String> onPick;
  final String label;

  Future<void> _pick() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    final path = file?.path;
    if (path != null) onPick(path);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          PbImage(
            collection: collection,
            recordId: recordId,
            filename: filename,
            pendingPath: pendingPath,
            size: 64,
            shape: BoxShape.rectangle,
            fallbackIcon: Icons.person_outline,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                if (pendingPath != null)
                  Text('New photo — uploads on sync',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Choose'),
          ),
        ],
      ),
    );
  }
}
