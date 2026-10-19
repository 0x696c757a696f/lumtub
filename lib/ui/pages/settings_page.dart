// Layout adapted from PiliNara (lib/pages/setting/view.dart): a list of
// settings groups with a search box, and the chosen group beside it on wide
// windows or on its own page on narrow ones.
//
// PiliNara: https://github.com/Starfallan/PiliNara
// Copyright (C) PiliNara contributors.
// Adapted for YTPlus under the GNU General Public License, version 3 or
// later. Changes: GetX routing is replaced with local state and a
// MaterialPageRoute, and the groups are YTPlus's own.

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../theme.dart';
import 'settings_sections.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller, this.initial = SettingsCategory.account});
  final AppController controller;
  final SettingsCategory initial;

  /// Below this width the groups and their rows no longer fit side by side.
  static const wideWidth = 720.0;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late SettingsCategory _category = widget.initial;
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  AppController get _controller => widget.controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= SettingsPage.wideWidth;
        if (!wide) return _list(context, wide: false);
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(flex: 4, child: _list(context, wide: true)),
          VerticalDivider(width: 1, color: context.colors.outline.withValues(alpha: 0.1)),
          Expanded(flex: 6, child: _query.isEmpty ? _Entries(controller: _controller, category: _category) : _SearchResults(controller: _controller, query: _query)),
        ]);
      });

  Widget _list(BuildContext context, {required bool wide}) {
    final theme = Theme.of(context);
    final searching = _query.isNotEmpty;
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: TextField(
          controller: _search,
          onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: theme.colorScheme.onInverseSurface,
            hintText: '搜索设置',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: searching
                ? IconButton(
                    tooltip: '清除',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(() {
                      _search.clear();
                      _query = '';
                    }),
                  )
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(50), borderSide: BorderSide.none),
          ),
        ),
      ),
      // On narrow windows the matches replace the groups; wide windows show
      // them in the detail pane.
      if (searching && !wide)
        ..._SearchResults.rows(context, _controller, _query)
      else
        for (final category in SettingsCategory.values)
          ListTile(
            tileColor: wide && !searching && category == _category ? theme.colorScheme.onInverseSurface : null,
            leading: Icon(category.icon),
            title: Text(category.title, style: theme.textTheme.titleMedium),
            subtitle: Text(category.subtitle, style: theme.textTheme.labelMedium!.copyWith(color: theme.colorScheme.outline)),
            onTap: () {
              if (wide) {
                setState(() {
                  _category = category;
                  _search.clear();
                  _query = '';
                });
              } else {
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    appBar: AppBar(title: Text(category.title)),
                    body: _Entries(controller: _controller, category: category),
                  ),
                ));
              }
            },
          ),
    ]);
  }
}

/// The rows of one group, rebuilt whenever a setting changes.
class _Entries extends StatelessWidget {
  const _Entries({required this.controller, required this.category});
  final AppController controller;
  final SettingsCategory category;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => ListView(padding: const EdgeInsets.only(top: 4, bottom: 24), children: [
          for (final entry in settingEntries(category, controller)) entry.builder(context),
        ]),
      );
}

/// Rows from every group whose title or keywords contain the query.
class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.controller, required this.query});
  final AppController controller;
  final String query;

  static List<Widget> rows(BuildContext context, AppController controller, String query) {
    final rows = <Widget>[
      for (final category in SettingsCategory.values)
        for (final entry in settingEntries(category, controller))
          if (entry.matches(query) || category.title.toLowerCase().contains(query)) entry.builder(context),
    ];
    if (rows.isNotEmpty) return rows;
    return [
      Padding(
        padding: const EdgeInsets.all(32),
        child: Text('没有找到相关设置', textAlign: TextAlign.center, style: TextStyle(color: context.colors.outline)),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => ListView(padding: const EdgeInsets.only(top: 4, bottom: 24), children: rows(context, controller, query)),
      );
}
