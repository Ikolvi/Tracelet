import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';
import 'package:tracelet_example/issues_page.dart';

void main() {
  testWidgets('the issues page builds and enlists its cards in Execute All', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: IssuesPage()));
    await tester.pump();

    expect(find.text('Execute All'), findsOneWidget);

    // The cards visible on the Recent tab have registered themselves, so
    // Execute All has something to run before it has scrolled anywhere. The old
    // sweep could reach five hard-coded ids and nothing else.
    expect(IssueCardStore.instance.mountedIds('recent'), isNotEmpty);
  });
}
