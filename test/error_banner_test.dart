import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/common.dart';

void main() {
  testWidgets('a one-line error takes one line, a long one grows', (tester) async {
    Future<double> height(String message) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Align(alignment: Alignment.topCenter, child: SizedBox(width: 600, child: ErrorBanner(message, onRetry: () {}))))));
      return tester.getSize(find.byType(ErrorBanner)).height;
    }

    final short = await height('Couldn\'t load these channels right now: A, B');
    expect(short, lessThan(80));
    final long = await height(List.filled(40, 'a channel that failed').join(', '));
    expect(long, greaterThan(short * 2));
  });
}
