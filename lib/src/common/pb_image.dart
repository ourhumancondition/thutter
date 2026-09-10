import 'dart:io';

import 'package:flutter/material.dart';

import '../data/pb/pb_files.dart';

/// Shows a PocketBase file-field image: a locally-picked file if one is pending
/// upload, otherwise the server URL, otherwise a placeholder.
class PbImage extends StatelessWidget {
  const PbImage({
    super.key,
    required this.collection,
    required this.recordId,
    required this.filename,
    this.pendingPath,
    this.size = 48,
    this.fallbackIcon = Icons.image_outlined,
    this.shape = BoxShape.circle,
  });

  final String collection;
  final String recordId;
  final String? filename;
  final String? pendingPath;
  final double size;
  final IconData fallbackIcon;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    final radius = shape == BoxShape.circle
        ? BorderRadius.circular(size)
        : BorderRadius.circular(8);
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: radius,
      ),
      child: Icon(fallbackIcon, size: size * 0.5, color: Theme.of(context).hintColor),
    );

    Widget? image;
    if (pendingPath != null && pendingPath!.isNotEmpty) {
      image = Image.file(File(pendingPath!),
          width: size, height: size, fit: BoxFit.cover);
    } else {
      final url = pbFileUrl(collection, recordId, filename,
          thumb: (size * 2).round());
      if (url != null) {
        image = Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => placeholder,
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : placeholder,
        );
      }
    }

    return ClipRRect(
      borderRadius: radius,
      child: image ?? placeholder,
    );
  }
}
