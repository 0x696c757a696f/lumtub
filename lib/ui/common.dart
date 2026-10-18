import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Full-area message for empty, error and not-yet-available states.
class StatusView extends StatelessWidget {
  const StatusView({super.key, required this.icon, required this.title, this.message, this.action, this.error = false});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: error ? colors.errorContainer : colors.secondaryContainer, shape: BoxShape.circle),
            child: Icon(icon, size: 34, color: error ? colors.onErrorContainer : colors.onSecondaryContainer),
          ),
          const SizedBox(height: 20),
          Text(title, textAlign: TextAlign.center, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message!, textAlign: TextAlign.center, maxLines: 6, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(color: colors.onSurfaceVariant, height: 1.5)),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ),
    ));
  }
}

/// Inline error with an optional retry, for errors below existing content.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(color: colors.errorContainer, borderRadius: AppStyle.cardRadius),
      child: Row(children: [
        Icon(Icons.error_outline_rounded, color: colors.onErrorContainer, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(message, maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.onErrorContainer))),
        if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('重试')),
      ]),
    );
  }
}

/// Settings group: a section title above a card.
class PreferenceCard extends StatelessWidget {
  const PreferenceCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(child: child);
}

/// Heading used at the top of each page.
class PageHeader extends StatelessWidget {
  const PageHeader(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 8, AppStyle.pagePadding, 16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
            ],
          ])),
          if (trailing != null) trailing!,
        ]),
      );
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

String formatDate(DateTime date) => '${date.year}年${date.month}月${date.day}日';

/// Opens a link in the default browser.
Future<void> openExternal(String url) async {
  if (!Platform.isWindows) return;
  await Process.start('explorer.exe', [url]);
}

Future<void> copyText(BuildContext context, String text, String notice) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notice)));
}
