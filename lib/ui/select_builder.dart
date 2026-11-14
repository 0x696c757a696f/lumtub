import 'package:flutter/widgets.dart';

/// Builds with what [select] reads from [listenable], and builds again only
/// when that changes (==), not on every notification. A record of the
/// values a part of the window shows makes a good selection: whatever the
/// builder reads from outside its own context belongs in it.
class SelectBuilder<T> extends StatefulWidget {
  const SelectBuilder({super.key, required this.listenable, required this.select, required this.builder, this.child});
  final Listenable listenable;
  final T Function() select;
  final Widget Function(BuildContext context, T value, Widget? child) builder;
  final Widget? child;

  @override
  State<SelectBuilder<T>> createState() => _SelectBuilderState<T>();
}

class _SelectBuilderState<T> extends State<SelectBuilder<T>> {
  late T _value = widget.select();

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(SelectBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.listenable != oldWidget.listenable) {
      oldWidget.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
    // Built again from above: the selection may read new values too.
    _value = widget.select();
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final value = widget.select();
    if (value != _value) setState(() => _value = value);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value, widget.child);
}
