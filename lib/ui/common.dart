import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';
import '../l10n/l10n.dart';
import '../system_env.dart';
import 'app_icons.dart';

export '../models.dart' show formatBytes;

/// Whether a scrolled list is close enough to its end to fetch the next
/// page: two screens ahead, so it usually arrives before the user gets there.
bool nearListEnd(ScrollMetrics metrics) => metrics.extentAfter < (metrics.viewportDimension * 2).clamp(1200, double.infinity);

/// Calls [onNearEnd] when the vertical list in [child] is [nearListEnd],
/// while scrolling and also when its content changes size, so a first page
/// too short to scroll on a tall window still brings the next one.
class NearEndListener extends StatelessWidget {
  const NearEndListener({super.key, required this.onNearEnd, this.enabled = true, required this.child});
  final VoidCallback onNearEnd;
  final bool enabled;
  final Widget child;

  bool _check(ScrollMetrics metrics, int depth) {
    if (enabled && depth == 0 && metrics.axis == Axis.vertical && metrics.hasContentDimensions && nearListEnd(metrics)) onNearEnd();
    return false;
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollMetricsNotification>(
        onNotification: (n) => _check(n.metrics, n.depth),
        child: NotificationListener<ScrollNotification>(onNotification: (n) => _check(n.metrics, n.depth), child: child),
      );
}

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
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message!, textAlign: TextAlign.center, maxLines: 6, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(color: colors.onSurfaceVariant, height: 1.5)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
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
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
      decoration: BoxDecoration(color: colors.errorContainer, borderRadius: AppStyle.cardRadius),
      child: Row(children: [
        Icon(AppIcons.warningCircle, color: colors.onErrorContainer, size: 20),
        const SizedBox(width: 12),
        Expanded(child: SelectableText(message, minLines: 1, maxLines: 8, style: TextStyle(color: colors.onErrorContainer))),
        if (onRetry != null) TextButton(onPressed: onRetry, child: Text(retryLabel ?? tr('Retry'))),
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

String twoDigits(int n) => n.toString().padLeft(2, '0');

String formatPlaybackTime(Duration value) {
  final hours = value.inHours;
  final minutes = twoDigits(value.inMinutes.remainder(60));
  final seconds = twoDigits(value.inSeconds.remainder(60));
  return hours > 0 ? '$hours:$minutes:$seconds' : '${value.inMinutes}:$seconds';
}

/// Like [formatPlaybackTime] but with the minutes always two digits: `01:23`.
String formatClock(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '$h:${twoDigits(m)}:${twoDigits(s)}' : '${twoDigits(m)}:${twoDigits(s)}';
}

/// `09:05`.
String formatHourMinute(DateTime t) => '${twoDigits(t.hour)}:${twoDigits(t.minute)}';

/// How long ago [date] was, as YouTube puts it under a video: 3 days ago.
String formatAgo(DateTime date, {DateTime? now}) {
  final age = (now ?? DateTime.now()).difference(date);
  final days = age.inDays;
  final (count, one, many) = switch (age) {
    _ when age.inMinutes < 1 => (0, '', ''),
    _ when age.inHours < 1 => (age.inMinutes, tr('1 minute ago'), tr('{0} minutes ago', [age.inMinutes])),
    _ when days < 1 => (age.inHours, tr('1 hour ago'), tr('{0} hours ago', [age.inHours])),
    _ when days < 7 => (days, tr('1 day ago'), tr('{0} days ago', [days])),
    _ when days < 30 => (days ~/ 7, tr('1 week ago'), tr('{0} weeks ago', [days ~/ 7])),
    _ when days < 365 => (days ~/ 30, tr('1 month ago'), tr('{0} months ago', [days ~/ 30])),
    _ => (days ~/ 365, tr('1 year ago'), tr('{0} years ago', [days ~/ 365])),
  };
  if (count == 0) return tr('Just now');
  return count == 1 ? one : many;
}

String formatDate(DateTime date) => tr('{1}/{2}/{0}', [date.year, date.month, date.day]);

/// An exact local start time for an upcoming stream.
String formatScheduledStart(DateTime date) {
  final local = date.toLocal();
  final time = formatHourMinute(local);
  return '${formatDate(local)} $time';
}

/// A dialog body's width: [wanted], or less on a screen too narrow for it
/// (the dialog's own margins and padding take 128).
double dialogWidth(BuildContext context, [double wanted = 420]) => math.max(200.0, math.min(wanted, MediaQuery.sizeOf(context).width - 128));

/// [url] as an http(s) link, or null for anything else, such as a folder
/// path, which `openInExplorer` opens.
Uri? webLink(String url) {
  final uri = Uri.tryParse(url);
  return uri == null || (uri.scheme != 'https' && uri.scheme != 'http') ? null : uri;
}

/// Opens a web link in the default browser.
Future<void> openExternal(String url) async {
  final uri = webLink(url);
  if (uri == null) return;
  if (!Platform.isWindows) return openWithDesktop(uri.toString());
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
              leadingIcon: Icon(v == value ? AppIcons.check : null, size: 18),
              onPressed: v == value ? null : () => onSelected(v),
              child: Text(item(v)),
            ),
        ],
        builder: (context, menu, _) => FilterChip(
          avatar: Icon(icon, size: 18, color: chipForeground(context, changed)),
          label: Row(mainAxisSize: MainAxisSize.min, children: [Text(label(value)), Icon(AppIcons.caretDown, size: 18, color: chipForeground(context, changed))]),
          selected: changed,
          showCheckmark: false,
          onSelected: (_) => menu.isOpen ? menu.close() : menu.open(),
        ),
      );
}

/// The colour of an icon on a chip: the page colour on a selected chip,
/// which is filled with the text colour.
Color chipForeground(BuildContext context, bool selected) {
  final scheme = Theme.of(context).colorScheme;
  return selected ? scheme.surface : scheme.onSurface;
}

/// [text] naming keys as this system's keyboard does: ⌘ and ⌥ on a Mac for
/// Ctrl and Alt.
/// Phones, tablets and TVs: no keyboard shortcuts or right-click to mention.
final bool touchFirst = Platform.isAndroid || Platform.isIOS;

/// A phone held either way: a touch screen whose short side is under a
/// tablet's. Its watch page is laid out as phone apps do: the player at
/// the top edge, full screen when turned sideways.
bool isPhone(BuildContext context) => (debugTouchFirst ?? touchFirst) && MediaQuery.sizeOf(context).shortestSide < 600;

/// Lets tests lay pages out as on a touch screen.
@visibleForTesting
bool? debugTouchFirst;

String keyNames(String text) => Platform.isMacOS ? text.replaceAll('Ctrl + ', '⌘ + ').replaceAll('Ctrl+', '⌘').replaceAll('Alt + ', '⌥ + ').replaceAll('Alt+', '⌥') : text;
