import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app_updater.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'motion.dart';
import 'select_builder.dart';
import 'theme.dart';

/// A small dot on the settings button while a new Lumtub is waiting.
class UpdateDot extends StatelessWidget {
  const UpdateDot({super.key, required this.controller, required this.child});
  final AppController controller;
  final Widget child;

  static bool shownFor(AppController controller) => controller.appUpdater?.noticeKey != null;

  @override
  Widget build(BuildContext context) => SelectBuilder(
        listenable: controller,
        select: () => shownFor(controller),
        child: child,
        builder: (context, shown, child) => Badge(smallSize: 8, isLabelVisible: shown, backgroundColor: context.colors.primary, child: child),
      );
}

/// The home page with a notice above it while a new Lumtub is ready to
/// install or can be had; closing it hides it until there is news.
class UpdateNotice extends StatelessWidget {
  const UpdateNotice({super.key, required this.controller, required this.child});
  final AppController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => SelectBuilder(
        listenable: controller,
        select: () {
          final updater = controller.appUpdater;
          return updater != null && updater.showsNotice ? (updater.noticeKey, updater.installError, updater.rejected, updater.error) : null;
        },
        child: child,
        builder: (context, shown, child) => Column(children: [
          AnimatedSize(
            duration: Motion.of(Ease.fade),
            curve: Ease.curve,
            alignment: Alignment.topCenter,
            child: shown == null ? const SizedBox(width: double.infinity) : _Bar(controller: controller, updater: controller.appUpdater!),
          ),
          Expanded(child: child!),
        ]),
      );
}

class _Bar extends StatelessWidget {
  const _Bar({required this.controller, required this.updater});
  final AppController controller;
  final AppUpdater updater;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final release = updater.available;
    final ready = updater.ready != null && updater.readyVersion != null;
    final version = ready ? updater.readyVersion! : release?.version ?? '';
    final downloadsItself = AppUpdater.canInstall && release?.asset != null && updater.rejected != release?.version;
    final String text;
    final String action;
    final VoidCallback onAction;
    if (ready) {
      text = updater.installError != null
          ? tr("The installer didn't start: {0}. Click to try again", [updater.installError!])
          : tr('Version {0} downloaded', [version]);
      action = Platform.isAndroid ? tr('Install') : tr('Restart now');
      onAction = () => unawaited(controller.restartToUpdate());
    } else if (downloadsItself) {
      text = updater.error != null ? tr('Download failed: {0}. Click to retry', [updater.error!]) : tr('Update available: {0}', [version]);
      action = tr('Start download');
      onAction = () => unawaited(updater.download());
    } else {
      text = tr('Update available: {0}', [version]);
      action = tr('Open page');
      onAction = () => unawaited(openExternal(AppUpdater.releasePage(release?.page)));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: colors.primaryContainer.withValues(alpha: 0.6),
          borderRadius: AppStyle.cardRadius,
          border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
        ),
        padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 4, 6),
        child: Row(children: [
          Icon(AppIcons.arrowCircleDown, size: 20, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: context.text.bodyMedium?.copyWith(color: colors.onPrimaryContainer))),
          const SizedBox(width: 8),
          TextButton(onPressed: onAction, child: Text(action)),
          IconButton(
            tooltip: tr('Close'),
            visualDensity: VisualDensity.compact,
            onPressed: () => unawaited(updater.dismissNotice()),
            icon: Icon(AppIcons.x, size: 18),
          ),
        ]),
      ),
    );
  }
}
