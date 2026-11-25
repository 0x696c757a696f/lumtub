import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:media_kit_video/media_kit_video.dart' show videoObstruction;

import '../l10n/l10n.dart';
import 'common.dart';
import 'motion.dart';
import 'app_icons.dart';

/// A panel that slides in from the player's right edge, for choices that
/// apply at once while the video keeps playing (更多设置, 字幕).
/// A phone held upright gets a sheet under the player instead, as phone
/// video apps open their panels, so the video stays in view.
Future<void> showPlayerPanel(BuildContext context, {required String title, List<PanelAction> actions = const [], double width = 400, required WidgetBuilder builder}) {
  final size = MediaQuery.sizeOf(context);
  if (watchesLikePhone(context) && size.height > size.width) {
    final below = size.height - MediaQuery.paddingOf(context).top - size.width * 9 / 16;
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      barrierColor: Colors.black26,
      constraints: BoxConstraints(maxHeight: max(size.height * 0.5, below)),
      builder: (context) => SizedBox(
        height: max(size.height * 0.5, below),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 8, 4),
            child: PanelHeader(title: title, actions: actions),
          ),
          Expanded(child: builder(context)),
        ]),
      ),
    );
  }
  return _sidePanel(context, title: title, actions: actions, width: width, builder: builder);
}

Future<void> _sidePanel(BuildContext context, {required String title, required List<PanelAction> actions, required double width, required WidgetBuilder builder}) => showGeneralDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: tr('Close'),
      barrierColor: Colors.black26,
      transitionDuration: Motion.of(Ease.fade),
      pageBuilder: (context, animation, secondary) => _Panel(title: title, actions: actions, width: width, builder: builder),
      transitionBuilder: (context, animation, secondary, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: Ease.curve)),
        child: child,
      ),
    );

class _Panel extends StatefulWidget {
  const _Panel({required this.title, required this.actions, required this.width, required this.builder});
  final String title;
  final List<PanelAction> actions;
  final double width;
  final WidgetBuilder builder;

  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  Rect? _covers;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The video moves into the room left beside the panel, so what is
    // chosen here shows on it instead of under the panel.
    final size = MediaQuery.sizeOf(context);
    final width = _width(size);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final covers = rtl ? Rect.fromLTWH(0, 0, width, size.height) : Rect.fromLTWH(size.width - width, 0, width, size.height);
    if (covers == _covers) return;
    _covers = covers;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _covers == covers) videoObstruction.value = covers;
    });
  }

  @override
  void dispose() {
    if (videoObstruction.value == _covers) videoObstruction.value = null;
    super.dispose();
  }

  double _width(Size size) => widget.width.clamp(0, max(0, size.width - 24)).toDouble();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Material(
        elevation: 2,
        color: theme.colorScheme.surface,
        shape: BorderDirectional(start: BorderSide(color: theme.colorScheme.outlineVariant)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: _width(size),
          height: double.infinity,
          child: SafeArea(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 4),
                child: PanelHeader(title: widget.title, actions: widget.actions, closes: true),
              ),
              Expanded(child: widget.builder(context)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A button in a panel's heading; [onPressed] gets the panel's context,
/// for closing it first.
class PanelAction {
  const PanelAction({required this.icon, required this.label, required this.onPressed});
  final IconData icon;
  final String label;
  final void Function(BuildContext panel) onPressed;
}

/// A panel's title with its buttons, labelled where they fit beside the
/// title and as icons with tooltips where a translation or a narrow
/// screen leaves too little room, so the title is never squeezed into a
/// column of single letters.
class PanelHeader extends StatelessWidget {
  const PanelHeader({super.key, required this.title, this.actions = const [], this.closes = false});
  final String title;
  final List<PanelAction> actions;
  final bool closes;

  /// The title keeps at least this much room, or all of itself if shorter.
  static const minTitle = 120.0;

  /// Whether labelled [actions] fit beside [title] in [width].
  static bool labelsFit(BuildContext context, {required String title, required List<PanelAction> actions, required double width, required bool closes}) {
    if (actions.isEmpty) return true;
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double measure(String text, TextStyle? style) {
      final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: direction, textScaler: scaler, maxLines: 1)..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final labelStyle = theme.textButtonTheme.style?.textStyle?.resolve(const {}) ?? theme.textTheme.labelLarge;
    var needed = min(measure(title, theme.textTheme.titleMedium), minTitle) + (closes ? 48 : 0);
    for (final action in actions) {
      // TextButton.icon: padding, the 18 px icon, the gap, the label.
      needed += 2 * 12 + scaler.scale(18) + 8 + measure(action.label, labelStyle) + 4;
    }
    return needed <= width;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final labelled = labelsFit(context, title: title, actions: actions, width: constraints.maxWidth, closes: closes);
        return Row(children: [
          Expanded(child: Text(title, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium)),
          for (final action in actions)
            labelled
                ? TextButton.icon(onPressed: () => action.onPressed(context), icon: Icon(action.icon, size: 18), label: Text(action.label, maxLines: 1))
                : IconButton(tooltip: action.label, onPressed: () => action.onPressed(context), icon: Icon(action.icon, size: 20)),
          if (closes) IconButton(tooltip: tr('Close'), onPressed: () => Navigator.of(context).pop(), icon: Icon(AppIcons.x)),
        ]);
      });
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
          Flexible(child: Text(widget.label, style: theme.textTheme.bodyMedium)),
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
              label: Text(_open ? tr('Collapse') : tr('Show all {0}', [widget.values.length])),
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
    // A long label is cut short; the tooltip shows it whole.
    return Semantics(
      toggled: value,
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: () => onChanged(!value),
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: SizedBox(
          width: 116,
          child: Material(
            color: value ? colors.primaryContainer : Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: value ? colors.primary : colors.outlineVariant)),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
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
        trailing: opens ? Icon(AppIcons.caretRight) : null,
        onTap: onTap,
      );
}
