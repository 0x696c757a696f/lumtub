import 'package:flutter/material.dart';

import 'ui/home_page.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const YtPlusApp());
}

class YtPlusApp extends StatelessWidget {
  const YtPlusApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'YTPlus',
        theme: buildAppTheme(),
        home: const HomePage(),
      );
}
