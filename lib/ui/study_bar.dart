import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../l10n/l10n.dart';
import '../shadowing.dart';
import '../study_flow.dart';
import 'app_icons.dart';
import 'theme.dart';

/// 精学: the bar under the player while a stretch of the video is studied,
/// with the four steps on top; or, when the video's study stopped before,
/// a line to go on with it. Nothing otherwise.
class StudyBar extends StatelessWidget {
  const StudyBar({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller.studyChanged, controller.shadowStage]),
      builder: (context, _) {
        final run = controller.study;
        if (run != null) return _frame(context, _Study(controller: controller, run: run));
        final resume = controller.studyResume;
        if (resume == null) return const SizedBox.shrink();
        return _frame(context, _Resume(controller: controller, resume: resume));
      },
    );
  }

  Widget _frame(BuildContext context, Widget child) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: colors.surfaceContainerHigh,
        borderRadius: AppStyle.cardRadius,
        child: Padding(padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 10), child: child),
      ),
    );
  }
}

String studyStepName(StudyStep step) => switch (step) {
      StudyStep.blind => tr('Listen blind'),
      StudyStep.read => tr('With subtitles'),
      StudyStep.shadow => tr('Shadow'),
      StudyStep.relisten => tr('Listen again'),
    };

class _Resume extends StatelessWidget {
  const _Resume({required this.controller, required this.resume});
  final AppController controller;
  final ({Duration unitStart, StudyStep step, DateTime at}) resume;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(children: [
      Icon(AppIcons.graduationCap, size: 20, color: colors.primary),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          tr('Study stopped at {0}, step {1} of 4: {2}', [_clock(resume.unitStart), resume.step.index + 1, studyStepName(resume.step)]),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.text.bodyMedium,
        ),
      ),
      TextButton(onPressed: () => unawaited(controller.startStudy(resume: true)), child: Text(tr('Go on'))),
      TextButton(onPressed: () => unawaited(controller.startStudy(fromStart: true)), child: Text(tr('From the start'))),
      IconButton(tooltip: tr('Forget'), icon: Icon(AppIcons.x, size: 18), onPressed: () => unawaited(controller.forgetStudyResume())),
    ]);
  }
}

String _clock(Duration d) {
  final s = d.inSeconds;
  final h = s ~/ 3600, m = s ~/ 60 % 60, sec = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}

class _Study extends StatelessWidget {
  const _Study({required this.controller, required this.run});
  final AppController controller;
  final StudyRun run;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final unit = run.current;
    final store = controller.studyStore;
    final unitSeconds = store?.unitLength.inSeconds ?? studyUnitDefault.inSeconds;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Icon(AppIcons.graduationCap, size: 20, color: colors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            tr('Study · part {0} of {1} · {2}–{3}', [run.unit + 1, run.units.length, _clock(unit.start), _clock(unit.end)]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.titleSmall,
          ),
        ),
        PopupMenuButton<int>(
          tooltip: tr('Part length'),
          initialValue: unitSeconds,
          onSelected: (seconds) => unawaited(controller.setStudyUnitLength(Duration(seconds: seconds))),
          itemBuilder: (context) => [
            for (final seconds in const [60, 90, 120, 150, 180]) PopupMenuItem(value: seconds, child: Text(tr('Parts of about {0} s', [seconds]))),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(tr('{0} s', [unitSeconds]), style: context.text.labelMedium?.copyWith(color: colors.outline)),
          ),
        ),
        IconButton(tooltip: tr('Stop studying'), icon: Icon(AppIcons.x, size: 18), onPressed: () => unawaited(controller.stopStudy())),
      ]),
      const SizedBox(height: 6),
      Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: _Steps(run: run, onTap: (step) => unawaited(controller.studyGoTo(step)))),
      const SizedBox(height: 8),
      Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: _body(context)),
    ]);
  }

  Widget _body(BuildContext context) {
    final colors = context.colors;
    Widget hint(String text) => Text(text, style: context.text.bodyMedium);
    Widget buttons(List<Widget> children) => Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: children));
    final skip = TextButton(onPressed: () => unawaited(controller.studySkip()), child: Text(tr('Skip this step')));
    final replay = OutlinedButton.icon(onPressed: () => unawaited(controller.studyReplay()), icon: Icon(AppIcons.arrowCounterClockwise, size: 16), label: Text(tr('Again')));
    if (run.done) {
      final rated = run.rated;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        hint(rated == null
            ? tr('This part is done.')
            : run.lastUnit
                ? tr('Every part is done. You understood about {0}% of the last one.', [rated])
                : tr('This part is done. You understood about {0}%.', [rated])),
        buttons([
          if (!run.lastUnit) FilledButton(onPressed: () => unawaited(controller.studyNextUnit()), child: Text(tr('Next part'))),
          OutlinedButton(onPressed: () => unawaited(controller.studyGoTo(StudyStep.blind)), child: Text(tr('Study this part again'))),
          TextButton(onPressed: () => unawaited(controller.stopStudy()), child: Text(tr('Finish'))),
        ]),
      ]);
    }
    switch (run.step) {
      case StudyStep.blind:
        final seconds = (blindEnd(run.lines, run.current) - run.current.start).inSeconds;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          hint(tr('Listen to the first {0} s without subtitles, just for the gist. Then it goes on with subtitles.', [seconds])),
          buttons([
            if (!run.revealed) FilledButton.tonalIcon(onPressed: controller.studyReveal, icon: Icon(AppIcons.eye, size: 16), label: Text(tr('Show subtitles'))),
            replay,
            skip,
          ]),
        ]);
      case StudyStep.read:
        final hard = run.hardLines.length;
        final player = controller.player;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          hint(tr('Line by line with subtitles: it pauses after each one. Play a line again when it is unclear; a line played twice is marked hard.')),
          buttons([
            replay,
            // Follows the line playing, which changes without the study.
            StreamBuilder<Duration>(
              stream: player?.stream.position,
              builder: (context, _) {
                final position = player?.state.position;
                final line = position == null ? null : run.lineAt(position);
                final marked = line != null && run.isHard(line);
                return OutlinedButton.icon(
                  onPressed: line == null ? null : controller.studyToggleHard,
                  icon: Icon(marked ? AppIcons.starFill : AppIcons.star, size: 16, color: marked ? colors.tertiary : null),
                  label: Text(marked ? tr('Hard line') : tr('Mark as hard')),
                );
              },
            ),
            Text(tr('{0} hard lines', [hard]), style: context.text.labelMedium?.copyWith(color: colors.outline)),
            skip,
          ]),
        ]);
      case StudyStep.shadow:
        return _shadow(context, hint, buttons, skip);
      case StudyStep.relisten:
        if (run.rating) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            hint(tr('How much did you understand?')),
            buttons([
              for (final percent in const [30, 70, 90]) FilledButton.tonal(onPressed: () => unawaited(controller.studyRate(percent)), child: Text(tr('About {0}%', [percent]))),
              replay,
            ]),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          hint(tr('Now the whole part once more, without subtitles and at normal speed.')),
          buttons([replay, skip]),
        ]);
    }
  }

  Widget _shadow(BuildContext context, Widget Function(String) hint, Widget Function(List<Widget>) buttons, Widget skip) {
    final colors = context.colors;
    final line = run.shadowLine;
    final chunks = run.chunks;
    if (line == null || chunks.isEmpty) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [hint(tr('No line to shadow.')), buttons([skip])]);
    final chunk = chunks[run.chunk.clamp(0, chunks.length - 1)];
    final fromHard = run.isHard(line);
    final store = controller.studyStore;
    final rate = store?.slowRate ?? 0.85;
    final recording = controller.shadowStage.value == ShadowStage.recording;
    final whole = run.chunk >= chunks.length - 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      hint(fromHard
          ? tr('Say the hard lines after the video, slower, from the end: first the last words, then a little more each time.')
          : tr('No hard lines, so here is the longest one. Say it after the video, slower, from the end: first the last words, then a little more each time.')),
      const SizedBox(height: 8),
      Text.rich(
        TextSpan(children: [
          if (chunk.before.isNotEmpty) TextSpan(text: '${chunk.before} ', style: TextStyle(color: colors.outline)),
          TextSpan(text: chunk.text, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
        style: context.text.titleMedium,
      ),
      const SizedBox(height: 2),
      Text(
        tr('Line {0} of {1} · part {2} of {3}', [run.shadowAt + 1, run.shadowLines.length, run.chunk + 1, chunks.length]),
        style: context.text.labelMedium?.copyWith(color: colors.outline),
      ),
      buttons([
        OutlinedButton.icon(onPressed: () => unawaited(controller.studyReplay()), icon: Icon(AppIcons.arrowCounterClockwise, size: 16), label: Text(tr('Again'))),
        if (!whole) FilledButton.tonalIcon(onPressed: () => unawaited(controller.studyLonger()), icon: Icon(AppIcons.plus, size: 16), label: Text(tr('A little more'))),
        FilledButton.tonal(onPressed: () => unawaited(controller.studyNextLine()), child: Text(run.shadowAt + 1 >= run.shadowLines.length ? tr('Done shadowing') : tr('Next line'))),
        IconButton(
          tooltip: recording ? tr('Stop recording') : tr('Record yourself'),
          isSelected: recording,
          icon: Icon(recording ? AppIcons.stop : AppIcons.microphoneStage, size: 20, color: recording ? colors.error : null),
          onPressed: () => unawaited(controller.toggleShadowing()),
        ),
        PopupMenuButton<double>(
          tooltip: tr('Shadowing speed'),
          initialValue: rate,
          onSelected: (value) => unawaited(controller.setStudySlowRate(value)),
          itemBuilder: (context) => [for (final value in const [0.75, 0.8, 0.85, 0.9, 1.0]) PopupMenuItem(value: value, child: Text('${value}x'))],
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), child: Text('${rate}x', style: context.text.labelLarge)),
        ),
        skip,
      ]),
    ]);
  }
}

/// The four steps in a row, the one now filled; a tap goes to one.
class _Steps extends StatelessWidget {
  const _Steps({required this.run, required this.onTap});
  final StudyRun run;
  final ValueChanged<StudyStep> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final now = run.done ? StudyStep.values.length : run.step.index;
    return Row(children: [
      for (final step in StudyStep.values) ...[
        if (step.index > 0) const SizedBox(width: 6),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => onTap(step),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 4,
                decoration: BoxDecoration(
                  color: step.index < now ? colors.primary.withValues(alpha: 0.45) : step.index == now ? colors.primary : colors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tr('{0}. {1}', [step.index + 1, studyStepName(step)]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelSmall?.copyWith(
                  color: step.index == now ? colors.primary : colors.outline,
                  fontWeight: step.index == now ? FontWeight.w600 : null,
                ),
              ),
            ]),
          ),
        ),
      ],
    ]);
  }
}

/// 精学 in the subtitle menu's language learning part: starts studying
/// the video, or stops it.
class StudyEntry extends StatelessWidget {
  const StudyEntry({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final studying = controller.study != null;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: Icon(AppIcons.graduationCap, size: 20, color: colors.primary),
      title: Text(tr('Study this video')),
      subtitle: Text(
        tr('Part by part, in four steps: listen blind, read along, shadow the hard lines, listen again.'),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: colors.outline),
      ),
      trailing: studying
          ? TextButton(onPressed: () => unawaited(controller.stopStudy()), child: Text(tr('Stop studying')))
          : FilledButton.tonal(
              onPressed: () {
                unawaited(Navigator.of(context, rootNavigator: true).maybePop());
                unawaited(controller.startStudy(resume: controller.studyResume != null));
              },
              child: Text(tr('Start studying')),
            ),
    );
  }
}

/// Blurs [child] (the subtitle list) while 盲听 or 复听 hides the
/// subtitles, so the lines cannot be read there either.
class StudyVeil extends StatelessWidget {
  const StudyVeil({super.key, required this.controller, required this.child});
  final AppController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller.studyChanged,
      child: child,
      builder: (context, child) {
        final hidden = controller.studyHidesSubtitles;
        // Always there, so the list keeps its state as it blurs.
        return ImageFiltered(enabled: hidden, imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6), child: IgnorePointer(ignoring: hidden, child: child));
      },
    );
  }
}
