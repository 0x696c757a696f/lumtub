import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../l10n/l10n.dart';
import '../app_icons.dart';
import '../common.dart';
import '../skin_paint.dart';
import '../theme.dart';
import '../update_notice.dart';
import 'account_settings.dart';
import 'settings_sections.dart';

void openSettingsCategory(BuildContext context, AppController controller, SettingsCategory category) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      appBar: SkinAppBar(AppBar(title: Text(category.title))),
      body: _CategoryRows(controller: controller, category: category),
    ),
  ));
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller, this.initial = SettingsCategory.account});
  final AppController controller;
  final SettingsCategory initial;

  /// Page width from which the groups and their rows sit side by side.
  static const double wideWidth = 720;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late SettingsCategory _selected = widget.initial;
  final _search = TextEditingController();
  String _query = '';

  AppController get _controller => widget.controller;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setQuery(String text) => setState(() => _query = text.trim().toLowerCase());

  void _clearSearch() {
    _search.clear();
    _setQuery('');
  }

  void _choose(SettingsCategory category, bool wide) {
    if (!wide) {
      openSettingsCategory(context, _controller, category);
      return;
    }
    _search.clear();
    setState(() {
      _selected = category;
      _query = '';
    });
  }

  Future<void> _signOut() async {
    final forget = await confirmSignOut(
      context,
      title: tr('Sign out?'),
      content: tr('The sign-ins saved on this device will be deleted. Subscriptions and playlists stay on this device.'),
    );
    if (forget == null) return;
    _controller.webSignIn?.signOut();
    if (_controller.account?.signedIn ?? false) await _controller.account?.signOut();
    if (forget) _controller.account?.forgetSynced();
  }

  List<Widget> _matchingRows(BuildContext context) {
    final rows = <Widget>[];
    for (final category in SettingsCategory.values) {
      final wholeGroup = category.title.toLowerCase().contains(_query);
      for (final entry in settingEntries(category, _controller)) {
        if (wholeGroup || entry.matches(_query)) rows.add(entry.builder(context));
      }
    }
    if (rows.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Center(child: Text(tr('No matching settings'), style: TextStyle(color: context.colors.outline))),
        ),
      ];
    }
    return rows;
  }

  Widget _searchBox() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: LeavesByKeys(
          child: TextField(
            controller: _search,
            onChanged: _setQuery,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: context.colors.onInverseSurface,
              hintText: tr('Search settings'),
              prefixIcon: Icon(AppIcons.magnifyingGlass, size: 20),
              suffixIcon: _query.isEmpty ? null : IconButton(tooltip: tr('Clear'), icon: Icon(AppIcons.x, size: 18), onPressed: _clearSearch),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(50), borderSide: BorderSide.none),
            ),
          ),
        ),
      );

  Widget _categoryTile(SettingsCategory category, bool wide, {bool withSubtitle = true, Widget? leading}) {
    final theme = Theme.of(context);
    final highlighted = wide && _query.isEmpty && category == _selected;
    return ListTile(
      tileColor: highlighted ? theme.colorScheme.onInverseSurface : null,
      leading: leading ?? Icon(category.icon),
      title: Text(category.title, style: theme.textTheme.titleMedium),
      subtitle: withSubtitle ? Text(category.subtitle, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline)) : null,
      onTap: () => _choose(category, wide),
    );
  }

  Widget _categoryList(bool wide) => ListenableBuilder(
        listenable: Listenable.merge([_controller, _controller.account]),
        builder: (context, _) {
          final searching = _query.isNotEmpty;
          return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            _searchBox(),
            if (searching && !wide)
              ..._matchingRows(context)
            else ...[
              for (final c in SettingsCategory.values)
                if (c != SettingsCategory.account && c != SettingsCategory.about) _categoryTile(c, wide),
              _categoryTile(SettingsCategory.account, wide, withSubtitle: false),
              if (_controller.account?.active ?? false)
                ListTile(
                  leading: Icon(AppIcons.signOut),
                  title: Text(tr('Sign out'), style: Theme.of(context).textTheme.titleMedium),
                  onTap: _signOut,
                ),
              _categoryTile(
                SettingsCategory.about,
                wide,
                withSubtitle: false,
                leading: UpdateDot(controller: _controller, child: Icon(SettingsCategory.about.icon)),
              ),
            ],
          ]);
        },
      );

  Widget _rightPane() {
    if (_query.isEmpty) return _CategoryRows(controller: _controller, category: _selected);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => ListView(padding: const EdgeInsets.only(top: 4, bottom: 24), children: _matchingRows(context)),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= SettingsPage.wideWidth;
          if (!wide) return _categoryList(false);
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: 4, child: _categoryList(true)),
            VerticalDivider(width: 1, thickness: 1, color: context.colors.outline.withValues(alpha: 0.1)),
            Expanded(flex: 6, child: _rightPane()),
          ]);
        },
      );
}

class _CategoryRows extends StatelessWidget {
  const _CategoryRows({required this.controller, required this.category});
  final AppController controller;
  final SettingsCategory category;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final entries = settingEntries(category, controller);
          return ListView.builder(
            padding: const EdgeInsets.only(top: 4, bottom: 24),
            itemCount: entries.length,
            itemBuilder: (context, i) => entries[i].builder(context),
          );
        },
      );
}
