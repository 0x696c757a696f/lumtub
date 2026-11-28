import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';
import '../ui/app_icons.dart';
import '../ui/common.dart';

TextStyle? _titleStyle(BuildContext context) => Theme.of(context).textTheme.titleMedium;

TextStyle? _subtitleStyle(BuildContext context) {
  final theme = Theme.of(context);
  return theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline);
}

Widget _cancelButton(BuildContext context) => TextButton(
      onPressed: () => Navigator.pop(context),
      child: Text(tr('Cancel'), style: TextStyle(color: Theme.of(context).colorScheme.outline)),
    );

class NormalItem extends StatelessWidget {
  const NormalItem({super.key, required this.title, this.subtitle, this.leading, this.trailing, this.onTap, this.enabled = true});
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) => ListTile(
        enabled: enabled,
        onTap: onTap,
        leading: leading,
        trailing: trailing,
        title: Text(title, style: _titleStyle(context)),
        subtitle: subtitle == null ? null : Text(subtitle!, style: _subtitleStyle(context)),
      );
}

class SwitchItem extends StatelessWidget {
  const SwitchItem({super.key, required this.title, required this.value, required this.onChanged, this.subtitle, this.leading, this.onTap, this.enabled = true});
  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onTap;
  final bool enabled;

  Widget _switch() => Transform.scale(
        scale: 0.8,
        alignment: Alignment.centerRight,
        child: Switch(value: value, onChanged: enabled ? onChanged : null),
      );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final split = onTap != null;
    final subtitleText = subtitle == null ? null : Text(subtitle!, style: _subtitleStyle(context));
    final titleStyle = split && !value ? _titleStyle(context)?.copyWith(color: colors.outline) : _titleStyle(context);
    final tile = ListTile(
      enabled: enabled,
      leading: leading,
      title: Text(title, style: titleStyle),
      subtitle: subtitleText,
      trailing: split ? null : _switch(),
      onTap: split ? onTap : () => onChanged(!value),
    );
    // One stop for the screen reader: the title read with the switch's
    // state, not an unnamed switch beside it.
    if (!split) return MergeSemantics(child: tile);
    return Row(children: [
      Expanded(child: tile),
      SizedBox(height: 25, width: 1, child: ColoredBox(color: colors.outline.withValues(alpha: 0.3))),
      Padding(padding: const EdgeInsets.only(left: 4, right: 24), child: Semantics(label: title, child: _switch())),
    ]);
  }
}

class PopupItem<T> extends StatelessWidget {
  const PopupItem({super.key, required this.title, required this.value, required this.values, required this.onSelected, this.leading, this.enabled = true});
  final String title;
  final Widget? leading;
  final T value;
  final List<(T, String)> values;
  final ValueChanged<T> onSelected;
  final bool enabled;

  String get _currentLabel {
    for (final (v, label) in values) {
      if (v == value) return label;
    }
    return value.toString();
  }

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    final left = origin.dx + (leading == null ? 16 : 72);
    final picked = await showMenu<T>(
      context: context,
      requestFocus: false,
      initialValue: value,
      position: RelativeRect.fromLTRB(left, origin.dy + 5, left, 0),
      items: [
        for (final (v, label) in values) CheckedPopupMenuItem<T>(value: v, checked: v == value, child: Text(label)),
      ],
    );
    if (picked != null && picked != value) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      enabled: enabled,
      leading: leading,
      title: Text(title, style: theme.textTheme.titleMedium),
      subtitle: Text(
        _currentLabel,
        style: theme.textTheme.labelMedium?.copyWith(color: enabled ? theme.colorScheme.secondary : theme.disabledColor),
      ),
      onTap: () => _open(context),
    );
  }
}

class SelectDialog<T> extends StatelessWidget {
  const SelectDialog({required this.values, required this.title, super.key, this.value, this.subtitleBuilder});
  final T? value;
  final List<(T, String)> values;
  final String title;
  final Widget? Function(BuildContext context, int index)? subtitleBuilder;

  @override
  Widget build(BuildContext context) => AlertDialog(
        clipBehavior: Clip.hardEdge,
        title: Text(title),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: Material(
          type: MaterialType.transparency,
          child: RadioGroup<T>(
            groupValue: value,
            onChanged: (v) => Navigator.pop(context, v ?? value),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < values.length; i++)
                  RadioListTile<T>(
                    dense: true,
                    value: values[i].$1,
                    title: Text(values[i].$2, style: _titleStyle(context)),
                    subtitle: subtitleBuilder?.call(context, i),
                  ),
              ]),
            ),
          ),
        ),
      );
}

class SliderDialog extends StatefulWidget {
  const SliderDialog({super.key, required this.value, required this.title, required this.min, required this.max, this.divisions, this.suffix = '', this.precise = 1});
  final double value;
  final String title;
  final double min;
  final double max;
  final int? divisions;
  final String suffix;
  final int precise;

  @override
  State<SliderDialog> createState() => _SliderDialogState();
}

class _SliderDialogState extends State<SliderDialog> {
  late double _current = widget.value.clamp(widget.min, widget.max);

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        contentPadding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
        content: SizedBox(
          height: 40,
          child: Material(
            type: MaterialType.transparency,
            child: Slider(
              value: _current,
              min: widget.min,
              max: widget.max,
              divisions: widget.divisions,
              label: '${_current.toStringAsFixed(widget.precise)}${widget.suffix}',
              onChanged: (v) => setState(() => _current = double.parse(v.toStringAsFixed(widget.precise))),
            ),
          ),
        ),
        actions: [
          _cancelButton(context),
          TextButton(onPressed: () => Navigator.pop(context, _current), child: Text(tr('OK'))),
        ],
      );
}

Future<void> pickFromDialog<T>(
  BuildContext context, {
  required String title,
  required T value,
  required List<(T, String)> values,
  required ValueChanged<T> onSelected,
}) async {
  final choice = await showDialog<T>(context: context, builder: (_) => SelectDialog<T>(value: value, values: values, title: title));
  if (choice != null && choice != value) onSelected(choice);
}

Future<void> pickWithSlider(
  BuildContext context, {
  required String title,
  required double value,
  required double min,
  required double max,
  required ValueChanged<double> onSelected, int? divisions,
  String suffix = '',
  int precise = 0,
}) async {
  final result = await showDialog<double>(
    context: context,
    builder: (_) => SliderDialog(value: value, title: title, min: min, max: max, divisions: divisions, suffix: suffix, precise: precise),
  );
  if (result != null && result != value) onSelected(result);
}

class ListEditorDialog extends StatefulWidget {
  const ListEditorDialog({
    super.key,
    required this.title,
    required this.initialItems,
    this.hintText = 'Tap the add button to add items',
    this.itemLabel = 'Items',
  });
  final String title;
  final List<String> initialItems;
  final String hintText;
  final String itemLabel;

  @override
  State<ListEditorDialog> createState() => _ListEditorDialogState();
}

class _ListEditorDialogState extends State<ListEditorDialog> {
  late final List<String> _items = List.of(widget.initialItems);
  late final List<TextEditingController> _editors = [for (final s in _items) TextEditingController(text: s)];
  late final List<FocusNode> _nodes = [for (var i = 0; i < _items.length; i++) _nodeFor(i)];
  final _addController = TextEditingController();

  FocusNode _nodeFor(int index) {
    final node = FocusNode();
    node.addListener(() {
      if (!node.hasFocus) {
        final at = _nodes.indexOf(node);
        if (at >= 0) _commitEdit(at);
      }
    });
    return node;
  }

  @override
  void dispose() {
    for (final c in _editors) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    _addController.dispose();
    super.dispose();
  }

  void _duplicateNotice() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      content: Text(tr('This {0} already exists', [tr(widget.itemLabel)])),
    ));
  }

  bool _add() {
    final text = _addController.text.trim();
    if (text.isEmpty) return true;
    if (_items.contains(text)) {
      _duplicateNotice();
      return false;
    }
    setState(() {
      _items.add(text);
      _editors.add(TextEditingController(text: text));
      _nodes.add(_nodeFor(_items.length - 1));
      _addController.clear();
    });
    return true;
  }

  bool _commitEdit(int index) {
    if (index < 0 || index >= _items.length) return true;
    final text = _editors[index].text.trim();
    if (text.isEmpty || text == _items[index]) {
      _editors[index].text = _items[index];
      return true;
    }
    final clash = [for (var i = 0; i < _items.length; i++) if (i != index) _items[i]].contains(text);
    if (clash) {
      _duplicateNotice();
      return false;
    }
    setState(() => _items[index] = text);
    _editors[index].text = text;
    return true;
  }

  void _remove(int index) {
    setState(() {
      _items.removeAt(index);
      _editors.removeAt(index).dispose();
      _nodes.removeAt(index).dispose();
    });
  }

  void _save() {
    for (var i = 0; i < _items.length; i++) {
      if (!_commitEdit(i)) return;
    }
    if (!_add()) return;
    Navigator.pop(context, List<String>.of(_items));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      actionsPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
      content: SizedBox(
        width: dialogWidth(context, 420),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _addController,
                autofocus: true,
                decoration: InputDecoration(isDense: true, hintText: tr(widget.hintText)),
                onSubmitted: (_) => _add(),
              ),
            ),
            IconButton(tooltip: tr('Add'), icon: Icon(AppIcons.plusCircle), onPressed: _add),
          ]),
          const SizedBox(height: 12),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                tr('No {0} yet', [tr(widget.itemLabel)]),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _items.length,
                itemBuilder: (context, i) => Card(
                  key: ObjectKey(_editors[i]),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                    title: TextField(
                      controller: _editors[i],
                      focusNode: _nodes[i],
                      style: theme.textTheme.bodyMedium,
                      decoration: const InputDecoration(isDense: true, border: InputBorder.none, filled: false),
                      onSubmitted: (_) => _commitEdit(i),
                      onTapOutside: (_) => _nodes[i].unfocus(),
                    ),
                    trailing: IconButton(tooltip: tr('Delete'), icon: Icon(AppIcons.trash, size: 20), onPressed: () => _remove(i)),
                  ),
                ),
              ),
            ),
        ]),
      ),
      actions: [
        _cancelButton(context),
        FilledButton(onPressed: _save, child: Text(tr('Save'))),
      ],
    );
  }
}

class ColorPalette extends StatelessWidget {
  const ColorPalette({super.key, required this.colorScheme, required this.selected});
  final ColorScheme colorScheme;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
        width: 50,
        height: 50,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: colorScheme.onInverseSurface, borderRadius: BorderRadius.circular(10)),
        child: Stack(alignment: Alignment.center, children: [
          ClipOval(
            child: Column(children: [
              Expanded(child: SizedBox.expand(child: ColoredBox(color: colorScheme.primary))),
              Expanded(
                child: Row(children: [
                  Expanded(child: SizedBox.expand(child: ColoredBox(color: colorScheme.tertiary))),
                  Expanded(child: SizedBox.expand(child: ColoredBox(color: colorScheme.primaryContainer))),
                ]),
              ),
            ]),
          ),
          if (selected)
            Container(
              width: 23,
              height: 23,
              decoration: BoxDecoration(shape: BoxShape.circle, color: colorScheme.surfaceContainer),
              child: Icon(AppIcons.check, size: 12, color: colorScheme.primary),
            ),
        ]),
      );
}

class SlideColorPicker extends StatefulWidget {
  const SlideColorPicker({super.key, required this.color});
  final Color color;

  @override
  State<SlideColorPicker> createState() => _SlideColorPickerState();
}

class _SlideColorPickerState extends State<SlideColorPicker> {
  late int _r = _channel(widget.color.r);
  late int _g = _channel(widget.color.g);
  late int _b = _channel(widget.color.b);
  late final TextEditingController _hex = TextEditingController(text: _hexText);

  static int _channel(double v) => (v * 255).round().clamp(0, 255);

  int get _rgb => (_r << 16) | (_g << 8) | _b;
  String get _hexText => _rgb.toRadixString(16).padLeft(6, '0').toUpperCase();

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _typed(String text) {
    if (text.length != 6) return;
    final parsed = int.tryParse(text, radix: 16) ?? 0;
    setState(() {
      _r = (parsed >> 16) & 0xFF;
      _g = (parsed >> 8) & 0xFF;
      _b = parsed & 0xFF;
    });
  }

  void _moved(void Function() assign) {
    setState(() {
      assign();
      _hex.text = _hexText;
    });
  }

  Widget _channelRow(String label, int value, ValueChanged<int> set) => Row(children: [
        const SizedBox(width: 16),
        SizedBox(width: 16, child: Text(label)),
        const SizedBox(width: 12),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 10),
            child: Slider(value: value.toDouble(), min: 0, max: 255, divisions: 255, onChanged: (v) => _moved(() => set(v.round()))),
          ),
        ),
        SizedBox(width: 40, child: Text('$value')),
      ]);

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(height: 100, color: Color(0xFF000000 | _rgb)),
          const SizedBox(height: 10),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _hex,
              decoration: const InputDecoration(prefixText: '#', isDense: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')), LengthLimitingTextInputFormatter(6)],
              onChanged: _typed,
            ),
          ),
          _channelRow('R', _r, (v) => _r = v),
          _channelRow('G', _g, (v) => _g = v),
          _channelRow('B', _b, (v) => _b = v),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            _cancelButton(context),
            TextButton(onPressed: () => Navigator.pop(context, Color(0xFF000000 | _rgb)), child: Text(tr('OK'))),
            const SizedBox(width: 16),
          ]),
        ]),
      );
}

Future<bool> confirmDialog(BuildContext context, {required String title, required String content, String confirm = 'OK'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        _cancelButton(context),
        TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tr(confirm))),
      ],
    ),
  );
  return ok ?? false;
}

class OrderedMultiSelectDialog<T> extends StatefulWidget {
  const OrderedMultiSelectDialog({super.key, required this.title, required this.initValues, required this.values, this.ordered = true});
  final String title;
  final Iterable<T> initValues;
  final List<(T, String, String?)> values;
  final bool ordered;

  @override
  State<OrderedMultiSelectDialog<T>> createState() => _OrderedMultiSelectDialogState<T>();
}

class _OrderedMultiSelectDialogState<T> extends State<OrderedMultiSelectDialog<T>> {
  late final List<T> _chosen = List.of(widget.initValues);

  void _toggle(T v) => setState(() => _chosen.contains(v) ? _chosen.remove(v) : _chosen.add(v));

  Widget _marker(ColorScheme colors, int position) {
    final on = position >= 0;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: on ? colors.primary : Colors.transparent,
        border: on ? null : Border.all(width: 2, color: colors.onSurfaceVariant),
      ),
      child: !on
          ? null
          : widget.ordered
              ? Text('${position + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colors.onPrimary))
              : Icon(AppIcons.check, size: 16, color: colors.onPrimary),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      clipBehavior: Clip.hardEdge,
      title: Text(widget.title),
      contentPadding: const EdgeInsets.only(top: 12),
      actionsPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      content: SizedBox(
        width: dialogWidth(context, 420),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final (v, name, description) in widget.values)
              ListTile(
                dense: true,
                leading: _marker(theme.colorScheme, _chosen.indexOf(v)),
                title: Text(name, style: theme.textTheme.titleSmall),
                subtitle: description == null ? null : Text(description, style: _subtitleStyle(context)),
                onTap: () => _toggle(v),
              ),
          ]),
        ),
      ),
      actions: [
        _cancelButton(context),
        TextButton(onPressed: _chosen.isEmpty ? null : () => Navigator.pop(context, List<T>.of(_chosen)), child: Text(tr('OK'))),
      ],
    );
  }
}

/// Text controllers for a dialog built inline, owned by the dialog so
/// they outlive its closing animation and are disposed with it.
class DialogTextFields extends StatefulWidget {
  const DialogTextFields({super.key, required this.initial, required this.builder});
  final List<String> initial;
  final Widget Function(BuildContext context, List<TextEditingController> fields) builder;

  @override
  State<DialogTextFields> createState() => _DialogTextFieldsState();
}

class _DialogTextFieldsState extends State<DialogTextFields> {
  late final List<TextEditingController> _fields = [for (final text in widget.initial) TextEditingController(text: text)];

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _fields);
}

class TextEditDialog extends StatefulWidget {
  const TextEditDialog({
    super.key,
    required this.title,
    required this.initialText,
    this.hintText,
    this.helper,
    this.monospace = false,
    this.maxLines = 1,
  });
  final String title;
  final String initialText;
  final String? hintText;
  final Widget Function(String text)? helper;
  final bool monospace;
  final int maxLines;

  @override
  State<TextEditDialog> createState() => _TextEditDialogState();
}

class _TextEditDialogState extends State<TextEditDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: widget.maxLines > 1 ? 6 : 1,
              maxLines: widget.maxLines,
              style: widget.monospace ? const TextStyle(fontFamily: 'Consolas', fontSize: 13) : null,
              decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), hintText: widget.hintText),
              onChanged: (_) => setState(() {}),
            ),
            if (widget.helper != null) ...[const SizedBox(height: 8), widget.helper!(_controller.text)],
          ]),
        ),
        actions: [
          _cancelButton(context),
          TextButton(onPressed: () => Navigator.pop(context, _controller.text), child: Text(tr('Save'))),
        ],
      );
}
