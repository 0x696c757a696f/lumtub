import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';

/// Asks once, on the first run, which block lists to turn on. Both start
/// unticked; closing the dialog any way saves the answer.
Future<void> askBlockLists(BuildContext context, AppController controller) async {
  var groups = controller.preferences.blockGroups;
  var media = controller.preferences.blockStateMedia;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(tr('Block lists')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Lumtub can leave some channels out of recommendations, Explore and search. Nothing is blocked unless you tick it, and you can change this later in Settings.')),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(AppIcons.prohibitFill),
                title: Text(tr('Block controversial religious groups')),
                value: groups,
                onChanged: (v) => setState(() => groups = v == true),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(AppIcons.megaphone),
                title: Text(tr('Block state propaganda media')),
                value: media,
                onChanged: (v) => setState(() => media = v == true),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Done'))),
        ],
      ),
    ),
  );
  await controller.savePreferences(controller.preferences.copyWith(blockGroups: groups, blockStateMedia: media, listsAsked: true));
}
