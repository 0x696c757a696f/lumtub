import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';
import '../l10n/l10n.dart';

export '../models.dart' show formatBytes;

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
  const ErrorBanner(this.message, {super.key, this.onRetry, this.retryLabel});
  final String message;
  final VoidCallback? onRetry;
  /// What the button says, when it does something other than retry.
  final String? retryLabel;

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
        if (onRetry != null) TextButton(onPressed: onRetry, child: Text(retryLabel ?? tr('重试'))),
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

String formatPlaybackTime(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '${value.inMinutes}:$seconds';
}

String formatDate(DateTime date) => tr('{0}年{1}月{2}日', [date.year, date.month, date.day]);

/// Opens a web link in the default browser.
Future<void> openExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (!Platform.isWindows || uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return;
  // rundll32 passes the whole address on; explorer.exe can drop everything
  // after the first '&'.
  await Process.start('rundll32.exe', ['url.dll,FileProtocolHandler', uri.toString()]);
}

Future<void> copyText(BuildContext context, String text, String notice) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notice)));
}

/// A search option chip that opens a menu of its values.
class OptionChip<T> extends StatelessWidget {
  const OptionChip({super.key, required this.icon, required this.value, required this.values, required this.label, required this.item, required this.changed, required this.onSelected});
  final IconData icon;
  final T value;
  final List<T> values;
  final String Function(T value) label;
  final String Function(T value) item;
  final bool changed;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => MenuAnchor(
        menuChildren: [
          for (final v in values)
            MenuItemButton(
              leadingIcon: Icon(v == value ? Icons.check_rounded : null, size: 18),
              onPressed: v == value ? null : () => onSelected(v),
              child: Text(item(v)),
            ),
        ],
        builder: (context, menu, _) => FilterChip(
          avatar: Icon(icon, size: 18),
          label: Row(mainAxisSize: MainAxisSize.min, children: [Text(label(value)), const Icon(Icons.arrow_drop_down_rounded, size: 18)]),
          selected: changed,
          showCheckmark: false,
          onSelected: (_) => menu.isOpen ? menu.close() : menu.open(),
        ),
      );
}
