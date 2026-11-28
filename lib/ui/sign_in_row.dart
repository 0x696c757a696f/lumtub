import 'package:material_ui/material_ui.dart';

/// A sign-in's state with its buttons under the text, not beside it, so a
/// phone's width or large text never squeezes them out.
class SignInRow extends StatelessWidget {
  const SignInRow(
      {required this.title, super.key, this.leading, this.subtitle, this.actions = const []});
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(leading: leading, title: title, subtitle: subtitle),
        if (actions.isNotEmpty)
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(leading == null ? 16 : 72, 0, 16, 8),
            child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actions),
          ),
      ]);
}
