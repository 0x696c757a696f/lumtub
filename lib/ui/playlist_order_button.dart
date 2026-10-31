import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';

/// 正序 / 倒序 for playlist [id]: the list shows and plays last to first.
class PlaylistOrderButton extends StatelessWidget {
  const PlaylistOrderButton({super.key, required this.controller, required this.id, this.onReversed});
  final AppController controller;
  final String id;
  /// Called when the order turns to last to first.
  final VoidCallback? onReversed;

  @override
  Widget build(BuildContext context) {
    final reversed = controller.isReversed(id);
    return TextButton.icon(
      onPressed: () {
        unawaited(controller.setReversed(id, !reversed));
        if (!reversed) onReversed?.call();
      },
      icon: Icon(reversed ? AppIcons.sortDescending : AppIcons.sortAscending, size: 18),
      label: Text(reversed ? tr('倒序') : tr('正序')),
    );
  }
}
