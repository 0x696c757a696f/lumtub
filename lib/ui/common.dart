import 'package:flutter/material.dart';

import 'theme.dart';

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(28, 0, 28, 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.errorBackground, borderRadius: BorderRadius.circular(10)),
        child: Text(message, style: const TextStyle(color: AppColors.errorText)),
      );
}

class PreferenceCard extends StatelessWidget {
  const PreferenceCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(color: AppColors.surface, margin: EdgeInsets.zero, child: child);
}

String formatBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String formatPlaybackTime(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '${value.inMinutes}:$seconds';
}
