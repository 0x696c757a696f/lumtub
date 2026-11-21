import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../l10n/l10n.dart';
import '../shadowing.dart';
import 'app_icons.dart';
import 'player_panel.dart';
import 'study_bar.dart';
import 'theme.dart';

/// One part of the learning drawer: built in [order] (lower first), under
/// [title] when there is one. [shown] leaves it out for videos it has
/// nothing for.
class LearningDrawerSection {
  const LearningDrawerSection({required this.id, required this.order, required this.build, this.title, this.shown});
  final String id;
  final int order;
  final String Function()? title;
  final bool Function(AppController controller)? shown;
  final Widget Function(BuildContext context, AppController controller) build;
}

final _sections = <String, LearningDrawerSection>{
  'study': LearningDrawerSection(id: 'study', order: 10, shown: (c) => c.playing?.isLive != true, build: (context, c) => _StudySection(controller: c)),
  'lines': LearningDrawerSection(id: 'lines', order: 20, title: () => tr('Line by line'), build: (context, c) => _LineSection(controller: c)),
};

/// What the drawer's 精学 part shows while [studyUnlocked] says no: set by
/// the learning pack (its pitch and a way to buy it).
Widget Function(BuildContext context, AppController controller)? studyLockedView;

/// Adds [section] to the learning drawer, or replaces the one with its id.
/// Other learning features put their own parts in this way.
void addLearningDrawerSection(LearningDrawerSection section) => _sections[section.id] = section;

/// The parts of the learning drawer, in order.
List<LearningDrawerSection> get learningDrawerSections => _sections.values.toList()..sort((a, b) => a.order.compareTo(b.order));

/// Slides the learning drawer out from the player's edge.
Future<void> showLearningDrawer(BuildContext context, AppController controller) =>
    showPlayerPanel(context, title: tr('Learning'), width: 380, builder: (context) => LearningDrawer(controller: controller));

class LearningDrawer extends StatelessWidget {
  const LearningDrawer({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, controller.studyChanged, controller.shadowStage]),
      builder: (context, _) {
        final sections = [for (final s in learningDrawerSections) if (s.shown?.call(controller) ?? true) s];
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          children: [
            for (final (i, section) in sections.indexed) ...[
              if (i > 0) Divider(height: 24, color: context.colors.outlineVariant),
              if (section.title?.call() case final title?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(title, style: context.text.labelMedium?.copyWith(color: context.colors.outline)),
                ),
              section.build(context, controller),
            ],
          ],
        );
      },
    );
  }
}

class _StudySection extends StatelessWidget {
  const _StudySection({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final studying = controller.study != null;
    final resume = controller.studyResume;
    void close() => unawaited(Navigator.of(context, rootNavigator: true).maybePop());
    final locked = !controller.studyAllowed && !studying;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(AppIcons.graduationCap, size: 22, color: colors.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(tr('Study this video'), style: context.text.titleSmall)),
      ]),
      const SizedBox(height: 4),
      Text(
        tr('Part by part, in four steps: listen blind, read along, shadow the hard lines, listen again.'),
        style: context.text.bodySmall?.copyWith(color: colors.outline),
      ),
      const SizedBox(height: 8),
      if (locked)
        studyLockedView?.call(context, controller) ?? Text(tr('Study mode is part of the learning pack'), style: context.text.bodySmall)
      else
      Wrap(spacing: 8, runSpacing: 4, children: [
        if (studying)
          OutlinedButton(onPressed: () => unawaited(controller.stopStudy()), child: Text(tr('Stop studying')))
        else if (resume != null) ...[
          FilledButton(
            onPressed: () {
              close();
              unawaited(controller.startStudy(resume: true));
            },
            child: Text(tr('Go on')),
          ),
          OutlinedButton(
            onPressed: () {
              close();
              unawaited(controller.startStudy(fromStart: true));
            },
            child: Text(tr('From the start')),
          ),
        ] else
          FilledButton(
            onPressed: () {
              close();
              unawaited(controller.startStudy());
            },
            child: Text(tr('Start studying')),
          ),
      ]),
      if (!locked && !studying && resume != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            tr('Study stopped at {0}, step {1} of 4: {2}', [studyClock(resume.unitStart), resume.step.index + 1, studyStepName(resume.step)]),
            style: context.text.bodySmall?.copyWith(color: colors.outline),
          ),
        ),
    ]);
  }
}

class _LineSection extends StatelessWidget {
  const _LineSection({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    final colors = context.colors;
    final recording = controller.shadowStage.value == ShadowStage.recording;
    Widget toggle(String title, String detail, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: Text(detail, style: TextStyle(fontSize: 11, color: colors.outline)),
          value: value,
          onChanged: onChanged,
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      toggle(tr('Pause after each line'), tr('Playback pauses as each subtitle line ends.'), settings.pauseEachLine,
          (on) => unawaited(controller.saveSettings(controller.settings.copyWith(pauseEachLine: on)))),
      toggle(tr('Blur the translation'), tr('Hover over the second subtitle or tap it to see it.'), settings.blurSecondary, (on) => unawaited(controller.setBlurSecondary(on))),
      const SizedBox(height: 4),
      Wrap(spacing: 8, runSpacing: 4, children: [
        OutlinedButton.icon(
          onPressed: () => unawaited(controller.toggleLineLoop()),
          icon: Icon(AppIcons.repeat, size: 16, color: controller.loopB != null ? colors.primary : null),
          label: Text(tr('Loop this line')),
        ),
        OutlinedButton.icon(
          onPressed: () => unawaited(controller.toggleShadowing()),
          icon: Icon(recording ? AppIcons.stop : AppIcons.microphoneStage, size: 16, color: recording ? colors.error : null),
          label: Text(recording ? tr('Stop recording') : tr('Record yourself')),
        ),
      ]),
    ]);
  }
}

/// The handle on the player's edge that opens the learning drawer.
class LearningDrawerHandle extends StatelessWidget {
  const LearningDrawerHandle({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tr('Learning'),
      child: Material(
        color: const Color(0x99000000),
        borderRadius: const BorderRadiusDirectional.horizontal(start: Radius.circular(10)).resolve(Directionality.of(context)),
        child: InkWell(
          borderRadius: const BorderRadiusDirectional.horizontal(start: Radius.circular(10)).resolve(Directionality.of(context)),
          onTap: () => unawaited(showLearningDrawer(context, controller)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(AppIcons.graduationCap, size: 20, color: Colors.white),
              const SizedBox(height: 4),
              Icon(AppIcons.caretLeft, size: 12, color: Colors.white70),
            ]),
          ),
        ),
      ),
    );
  }
}
