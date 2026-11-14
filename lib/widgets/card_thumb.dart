import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';

class CardThumb extends StatelessWidget {
  final String? path;
  final String? url;
  final double width;
  final double height;

  const CardThumb({
    super.key,
    this.path,
    this.url,
    this.width = 44,
    this.height = 64,
  });

  Widget _placeholder() => Container(
        width: width,
        height: height,
        color: AppColors.surface,
        child: const Icon(Icons.style_outlined, color: AppColors.textDim),
      );

  @override
  Widget build(BuildContext context) {
    Widget child;
    final pth = path;
    final u = url;
    if (pth != null && File(pth).existsSync()) {
      child = Image.file(File(pth),
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder());
    } else if (u != null && u.isNotEmpty) {
      child = Image.network(u,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder());
    } else {
      child = _placeholder();
    }
    return ClipRRect(borderRadius: BorderRadius.circular(3), child: child);
  }
}
