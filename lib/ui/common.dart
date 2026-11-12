import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';
import '../device.dart';
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

  /// Narrower than this, the buttons go under the title, so on a phone
  /// they do not squeeze it.
  static const stackBelow = 560.0;

  @override
  Widget build(BuildContext context) {
    final heading = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      // A TV's few hundred pixels of height go to the videos.
      if (subtitle != null && !Device.tv) ...[
        const SizedBox(height: 2),
        Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
      ],
    ]);
    final trailing = this.trailing;
    return Padding(
      padding: EdgeInsets.fromLTRB(AppStyle.pagePadding, Device.tv ? 0 : 8, AppStyle.pagePadding, Device.tv ? 8 : 16),
      child: trailing == null
          ? Row(children: [Expanded(child: heading)])
          : LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth < stackBelow
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      heading,
                      const SizedBox(height: 4),
                      SingleChildScrollView(scrollDirection: Axis.horizontal, child: trailing),
                    ])
                  : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: heading), trailing]),
            ),
    );
  }
}

/// Chips and filters: wrapped over as many lines as they need, or on a TV
/// one line that scrolls sideways as the remote moves along it, as TV apps
/// lay out their filters, so the videos start higher.
class FilterFlow extends StatelessWidget {
  const FilterFlow({super.key, required this.children, this.spacing = 8});
  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) => Device.tv
      ? SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final (i, child) in children.indexed) Padding(padding: EdgeInsetsDirectional.only(end: i == children.length - 1 ? 0 : spacing), child: child),
          ]),
        )
      : Wrap(spacing: spacing, runSpacing: spacing, crossAxisAlignment: WrapCrossAlignment.center, children: children);
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
bool get touchFirst => debugTouchFirst ?? _touchFirst;
final bool _touchFirst = Platform.isAndroid || Platform.isIOS;

/// A phone held either way: a touch screen whose short side is under a
/// tablet's, never a TV, whose screen is as few pixels across but far
/// away. Its watch page is laid out as phone apps do: the player at
/// the top edge, full screen when turned sideways.
bool isPhone(BuildContext context) => touchFirst && !Device.tv && MediaQuery.sizeOf(context).shortestSide < 600;

/// A watch page laid out as a phone's: on a phone, and on a tablet held
/// upright, where the player across the width leaves room for tabs under it.
bool watchesLikePhone(BuildContext context) {
  if (isPhone(context)) return true;
  final size = MediaQuery.sizeOf(context);
  return touchFirst && !Device.tv && size.height > size.width;
}

/// One row of [pickFromSheet]; a null label draws a divider.
typedef SheetChoice<T> = ({T? value, IconData? icon, String? label, bool selected});

/// A phone's menu: [choices] as rows a finger can hit, in a sheet from the
/// bottom of the screen. The picked value, or null when dismissed.
Future<T?> pickFromSheet<T>(BuildContext context, List<SheetChoice<T>> choices, {String? title}) => showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      builder: (context) => ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 8), children: [
        if (title != null) Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 8), child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        for (final c in choices)
          if (c.label == null)
            const Divider(height: 8)
          else
            ListTile(
              minTileHeight: 52,
              leading: c.icon != null ? Icon(c.icon) : c.selected ? Icon(AppIcons.check) : const SizedBox(width: 24),
              title: Text(c.label!),
              selected: c.selected,
              trailing: c.icon != null && c.selected ? Icon(AppIcons.check) : null,
              onTap: () => Navigator.pop(context, c.value),
            ),
      ]),
    );

/// A dialog on larger screens. On a phone a sheet that rises only to the
/// bottom of the player, so the video stays in view while it is open.
Future<T?> showPanel<T>(BuildContext context, WidgetBuilder builder) {
  if (!isPhone(context)) return showDialog<T>(context: context, builder: builder);
  final size = MediaQuery.sizeOf(context);
  final below = size.height - MediaQuery.paddingOf(context).top - size.width * 9 / 16;
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: BoxConstraints(maxHeight: math.max(size.height * 0.5, below)),
    builder: builder,
  );
}

/// The inside of a [showPanel]: an [AlertDialog] on larger screens, on a
/// phone the same title, content and buttons laid out in the sheet.
class PanelDialog extends StatelessWidget {
  const PanelDialog({super.key, required this.title, required this.content, this.actions = const []});
  final Widget title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    if (!isPhone(context)) return AlertDialog(title: title, content: content, actions: actions);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        child: DefaultTextStyle.merge(style: Theme.of(context).textTheme.titleLarge, child: title),
      ),
      Flexible(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: content)),
      if (actions.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: OverflowBar(alignment: MainAxisAlignment.end, spacing: 8, children: actions),
        ),
    ]);
  }
}

/// Lets tests lay pages out as on a touch screen.
@visibleForTesting
bool? debugTouchFirst;

String keyNames(String text) => Platform.isMacOS ? text.replaceAll('Ctrl + ', '⌘ + ').replaceAll('Ctrl+', '⌘').replaceAll('Alt + ', '⌥ + ').replaceAll('Alt+', '⌥') : text;
