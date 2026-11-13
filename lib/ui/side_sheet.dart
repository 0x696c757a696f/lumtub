import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'motion.dart';

/// Window width from which panels open as a [showSideSheet], the width at
/// which the shell puts its side rail.
const double sideSheetBreakpoint = 720;

/// The width of a side sheet in a window [windowWidth] across: two fifths
/// of it, kept between a phone's width and a comfortable reading measure.
double sideSheetWidth(double windowWidth) => (windowWidth * 0.4).clamp(360.0, 560.0).toDouble();

/// Whether [context] is inside a sheet, a [showSideSheet] or a sheet from
/// the bottom, so a panel lays itself out as one rather than as a dialog.
bool inSheet(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SheetScope>() != null;

/// Marks the contents of a sheet for [inSheet].
class SheetScope extends InheritedWidget {
  const SheetScope({super.key, required super.child});

  @override
  bool updateShouldNotify(SheetScope oldWidget) => false;
}

/// A full-height sheet that slides in from the end edge of the window over
/// a scrim, for a panel in a wide window: the page stays in view beside it.
/// Esc, the back button and a tap on the scrim close it, and the keyboard
/// focus stays inside it while it is open.
Future<T?> showSideSheet<T>(BuildContext context, WidgetBuilder builder) {
  final navigator = Navigator.of(context, rootNavigator: true);
  return navigator.push<T>(_SideSheetRoute<T>(builder: builder, barrierLabel: tr('Close'), capturedThemes: InheritedTheme.capture(from: context, to: navigator.context)));
}

/// A dialog route that comes in more slowly than it goes, as a sheet does.
class _SideSheetRoute<T> extends RawDialogRoute<T> {
  _SideSheetRoute({required WidgetBuilder builder, required super.barrierLabel, required CapturedThemes capturedThemes})
      : super(
          barrierDismissible: true,
          barrierColor: Colors.black26,
          traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
          transitionDuration: Motion.of(const Duration(milliseconds: 300)),
          pageBuilder: (context, animation, secondary) => capturedThemes.wrap(_SideSheet(builder: builder)),
          transitionBuilder: (context, animation, secondary, child) {
            final rtl = Directionality.of(context) == TextDirection.rtl;
            return SlideTransition(
              position: Tween(begin: Offset(rtl ? -1 : 1, 0), end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: Ease.curve)),
              child: child,
            );
          },
        );

  @override
  Duration get reverseTransitionDuration => Motion.of(const Duration(milliseconds: 200));
}

class _SideSheet extends StatelessWidget {
  const _SideSheet({required this.builder});
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Semantics(
        namesRoute: true,
        label: MaterialLocalizations.of(context).dialogLabel,
        child: Material(
          // The colour of a sheet from the bottom, so a panel looks the same on a phone.
          color: theme.bottomSheetTheme.backgroundColor ?? theme.colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          shape: BorderDirectional(start: BorderSide(color: theme.colorScheme.outlineVariant)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: sideSheetWidth(MediaQuery.sizeOf(context).width),
            height: double.infinity,
            child: SafeArea(child: SheetScope(child: Builder(builder: builder))),
          ),
        ),
      ),
    );
  }
}
