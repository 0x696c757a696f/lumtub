import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'motion.dart';
import 'app_icons.dart';

/// A panel that slides in from the player's right edge, for choices that
/// apply at once while the video keeps playing (更多设置, 字幕).
Future<void> showPlayerPanel(BuildContext context, {required String title, List<Widget> actions = const [], double width = 400, required WidgetBuilder builder}) => showGeneralDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: tr('关闭'),
      barrierColor: Colors.black26,
      transitionDuration: Motion.of(Ease.fade),
      pageBuilder: (context, animation, secondary) => _Panel(title: title, actions: actions, width: width, builder: builder),
      transitionBuilder: (context, animation, secondary, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: Ease.curve)),
        child: child,
      ),
    );

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.actions, required this.width, required this.builder});
  final String title;
  final List<Widget> actions;
  final double width;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        elevation: 8,
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width.clamp(0, size.width - 24).toDouble(),
          height: double.infinity,
          child: SafeArea(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(children: [
                  Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                  ...actions,
                  IconButton(tooltip: tr('关闭'), onPressed: () => Navigator.of(context).pop(), icon: const Icon(AppIcons.x)),
                ]),
              ),
              Expanded(child: builder(context)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A heading over a group of rows.
class PanelHeading extends StatelessWidget {
  const PanelHeading(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge!.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

/// A label over chips, one of which is chosen; a tap applies at once.
/// [collapsed] shows only the chosen value until 全部 is clicked, for
/// long lists such as a video's audio tracks.
class PanelChoices<T> extends StatefulWidget {
  const PanelChoices({super.key, required this.label, this.icon, required this.value, required this.values, required this.onSelected, this.collapsed = false});
  final String label;
  final IconData? icon;
  final T value;
  final List<(T, String)> values;
  final ValueChanged<T> onSelected;
  final bool collapsed;

  @override
  State<PanelChoices<T>> createState() => _PanelChoicesState<T>();
}

class _PanelChoicesState<T> extends State<PanelChoices<T>> {
  late bool _open = !widget.collapsed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = _open ? widget.values : [for (final entry in widget.values) if (entry.$1 == widget.value) entry];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (widget.icon != null) ...[Icon(widget.icon, size: 18, color: theme.colorScheme.onSurfaceVariant), const SizedBox(width: 8)],
          Text(widget.label, style: theme.textTheme.bodyMedium),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (v, text) in shown)
            ChoiceChip(
              label: Text(text),
              selected: v == widget.value,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              onSelected: (_) {
                if (v != widget.value) widget.onSelected(v);
              },
            ),
          if (widget.collapsed && widget.values.length > 1)
            ActionChip(
              avatar: Icon(_open ? AppIcons.caretUp : AppIcons.caretDown, size: 18),
              label: Text(_open ? tr('收起') : tr('全部 {0} 个', [widget.values.length])),
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _open = !_open),
            ),
        ]),
      ]),
    );
  }
}

/// A tile that turns something on and off, for the switches at the top
/// of 更多设置.
class PanelToggle extends StatelessWidget {
  const PanelToggle({super.key, required this.label, required this.icon, required this.value, required this.onChanged});
  final String label;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 116,
      child: Material(
        color: value ? colors.primaryContainer : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Column(children: [
              Icon(icon, size: 22, color: value ? colors.onPrimaryContainer : colors.onSurfaceVariant),
              const SizedBox(height: 4),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: value ? colors.onPrimaryContainer : colors.onSurface)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A row with a switch.
class PanelSwitch extends StatelessWidget {
  const PanelSwitch({super.key, required this.label, required this.icon, required this.value, required this.onChanged, this.detail});
  final String label;
  final String? detail;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        dense: true,
        secondary: Icon(icon, size: 20),
        title: Text(label),
        subtitle: detail == null ? null : Text(detail!),
        value: value,
        onChanged: onChanged,
      );
}

/// A row that opens something else, or does something once.
class PanelLink extends StatelessWidget {
  const PanelLink({super.key, required this.label, required this.icon, required this.onTap, this.detail, this.opens = true});
  final String label;
  final String? detail;
  final IconData icon;
  final VoidCallback onTap;
  /// Shows a chevron: the row leads to another page or dialog.
  final bool opens;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        leading: Icon(icon, size: 20),
        title: Text(label),
        subtitle: detail == null ? null : Text(detail!, style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12)),
        trailing: opens ? const Icon(AppIcons.caretRight) : null,
        onTap: onTap,
      );
}
