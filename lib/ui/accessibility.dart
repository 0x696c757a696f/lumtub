import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// What assistive technology asks of the interface, read the same way on
/// every system.
abstract final class Accessibility {
  static final _systemParametersInfo = Platform.isWindows
      ? DynamicLibrary.open('user32.dll').lookupFunction<
          Int32 Function(Uint32, Uint32, Pointer<Int32>, Uint32),
          int Function(int, int, Pointer<Int32>, int)>('SystemParametersInfoW')
      : null;
  static const _spiGetScreenReader = 0x0046;

  /// Whether a screen reader is running: TalkBack, VoiceOver and Orca say
  /// so through Flutter; on Windows, Narrator, NVDA and JAWS set the
  /// system's screen reader flag, which Flutter does not pass on.
  static bool screenReader(BuildContext context) {
    if (MediaQuery.maybeAccessibleNavigationOf(context) ?? false) return true;
    // VoiceOver is what turns semantics on in a Mac app; elsewhere other
    // tools (automation, password managers) can too.
    if (Platform.isMacOS) return SemanticsBinding.instance.semanticsEnabled;
    final call = _systemParametersInfo;
    if (call == null) return false;
    // Asked at most every two seconds, however often the bars hide.
    if (_asked.isRunning && _asked.elapsed < const Duration(seconds: 2)) return _windowsReader;
    _asked
      ..reset()
      ..start();
    final value = calloc<Int32>();
    try {
      return _windowsReader = call(_spiGetScreenReader, 0, value, 0) != 0 && value.value != 0;
    } finally {
      calloc.free(value);
    }
  }

  /// Whether the system asks for described sound: Android 13's and iOS's
  /// Audio Descriptions setting.
  static bool systemAudioDescription = false;

  /// Whether the system has closed captions turned on (Android's caption
  /// preferences, iOS's Subtitles & Captioning).
  static bool systemCaptions = false;

  /// [readSystemSettings] under way, for start-up to wait for.
  static Future<void>? reading;

  /// Reads the system's accessibility settings Flutter does not pass on.
  static Future<void> readSystemSettings() => reading ??= _read();

  static Future<void> _read() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    const shell = MethodChannel('lumtub/windows_shell');
    Future<bool> ask(String method) async {
      try {
        return await shell.invokeMethod<bool>(method).timeout(const Duration(seconds: 2)) ?? false;
      } on Object {
        return false;
      }
    }

    systemAudioDescription = await ask('audioDescriptionRequested');
    systemCaptions = await ask('captionsRequested');
  }

  static final _asked = Stopwatch();
  static bool _windowsReader = false;

  /// Says [message] through the screen reader, when one listens: nothing
  /// is built or sent otherwise.
  static void announce(BuildContext context, String message) {
    if (message.isEmpty || !SemanticsBinding.instance.semanticsEnabled) return;
    final view = View.maybeOf(context);
    if (view == null) return;
    unawaited(SemanticsService.sendAnnouncement(
        view, message, Directionality.maybeOf(context) ?? TextDirection.ltr));
  }

  static String _spoken = '';

  /// Says a subtitle [line] once, when it is new and a screen reader
  /// listens, in the direction of its own script.
  static void speak(String line) {
    final text = line.trim();
    if (text == _spoken) return;
    _spoken = text;
    if (text.isEmpty || !SemanticsBinding.instance.semanticsEnabled) return;
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    // Android has given up announcements: there a live region says it.
    if (!dispatcher.accessibilityFeatures.supportsAnnounce) {
      spokenLine.value = text;
      return;
    }
    final view = dispatcher.implicitView ?? dispatcher.views.firstOrNull;
    if (view == null) return;
    unawaited(SemanticsService.sendAnnouncement(
        view, text, rightToLeft(text) ? TextDirection.rtl : TextDirection.ltr));
  }

  /// The subtitle line for [SpokenLine] to say where announcements are not
  /// supported.
  static final spokenLine = ValueNotifier('');

  /// Whether [text]'s first strong letter is Hebrew, Arabic, Syriac,
  /// Thaana or N'Ko.
  static bool rightToLeft(String text) {
    for (final c in text.runes) {
      if ((c >= 0x0590 && c <= 0x08FF) ||
          (c >= 0xFB1D && c <= 0xFDFF) ||
          (c >= 0xFE70 && c <= 0xFEFF)) {
        return true;
      }
      if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c >= 0x00C0) return false;
    }
    return false;
  }
}

/// One stop for the screen reader in place of the many pieces of text and
/// badges [child] draws: [label] says all of it in reading order, and
/// [actions] carry what the pieces' own small buttons do. Leaving the
/// pieces out also keeps the semantics tree of a long feed small.
class SpokenAs extends StatelessWidget {
  const SpokenAs(
      {super.key, required this.label, required this.child, this.button = true, this.actions});
  final String label;
  final bool button;
  final Map<CustomSemanticsAction, VoidCallback>? actions;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        button: button,
        customSemanticsActions: actions,
        excludeSemantics: true,
        child: child,
      );
}

/// An invisible live region that says [Accessibility.spokenLine] as it
/// changes, on systems without announcements.
class SpokenLine extends StatelessWidget {
  const SpokenLine({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: Accessibility.spokenLine,
        builder: (context, line, _) => line.isEmpty
            ? const SizedBox.shrink()
            : Semantics(
                liveRegion: true,
                label: line,
                textDirection:
                    Accessibility.rightToLeft(line) ? TextDirection.rtl : TextDirection.ltr,
                child: const SizedBox(width: 1, height: 1)),
      );
}

/// Parts of a sentence for the screen reader, empty ones left out.
String spokenParts(Iterable<String?> parts) =>
    parts.whereType<String>().where((p) => p.trim().isNotEmpty).join(', ');
