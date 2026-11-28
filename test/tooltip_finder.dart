import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Widgets with a [Tooltip] whose message is [message]: `find.byTooltip`
/// looks only for the Tooltip of `package:flutter/material.dart`.
Finder byTooltip(String message) => find.byWidgetPredicate(
    (widget) =>
        widget is Tooltip &&
        (widget.message == message || widget.richMessage?.toPlainText() == message),
    description: 'tooltip "$message"');
