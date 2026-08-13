import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';
import 'package:tracelet_example/issues/issue_sweep.dart';

/// A stand-in for a real issue card: same shape (store-backed status, a runner
/// that reports into it), none of the SDK.
class _FakeCard extends StatefulWidget {
  const _FakeCard({required this.id, this.body, this.height = 400});

  final String id;
  final Future<void> Function(void Function(String) report)? body;
  final double height;

  @override
  State<_FakeCard> createState() => _FakeCardState();
}

class _FakeCardState extends State<_FakeCard> with IssueCardRun<_FakeCard> {
  @override
  String get cardId => widget.id;

  @override
  bool get prepareBeforeRun => false;

  @override
  IssueRunner? get cardRunner => widget.body == null ? null : _run;

  Future<void> _run() async {
    setRunning(running: true);
    try {
      await widget.body!(setStatus);
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: widget.height, child: Text('${widget.id}: $status'));
}

Widget _host({
  required List<Widget> cards,
  required ScrollController controller,
  String scope = 'test',
  double viewport = 600,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: viewport,
        child: IssueCardScope(
          name: scope,
          child: ListView(controller: controller, children: cards),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a result survives the card being scrolled out of view', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        controller: controller,
        cards: [
          _FakeCard(
            id: 'card-a',
            body: (report) async => report('✅ SUCCESS: proved it'),
          ),
          const _FakeCard(id: 'card-b', height: 2000),
        ],
      ),
    );

    await IssueCardStore.instance.run('card-a');
    await tester.pump();
    expect(find.text('card-a: ✅ SUCCESS: proved it'), findsOneWidget);

    // Far enough that the ListView unmounts card-a entirely.
    controller.jumpTo(1800);
    await tester.pump();
    expect(find.textContaining('card-a'), findsNothing);

    controller.jumpTo(0);
    await tester.pump();
    expect(find.text('card-a: ✅ SUCCESS: proved it'), findsOneWidget);
  });

  testWidgets('a result reported after the card is unmounted is not lost', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final finish = Completer<void>();

    await tester.pumpWidget(
      _host(
        controller: controller,
        cards: [
          _FakeCard(
            id: 'slow-card',
            body: (report) async {
              report('Running…');
              await finish.future;
              report('✅ SUCCESS: finished off-screen');
            },
          ),
          const _FakeCard(id: 'filler', height: 2000),
        ],
      ),
    );

    final run = IssueCardStore.instance.run('slow-card');
    await tester.pump();

    controller.jumpTo(1800);
    await tester.pump();
    expect(find.textContaining('slow-card'), findsNothing);

    finish.complete();
    await run;

    controller.jumpTo(0);
    await tester.pump();
    expect(
      find.text('slow-card: ✅ SUCCESS: finished off-screen'),
      findsOneWidget,
    );
    expect(IssueCardStore.instance.entry('slow-card').running, isFalse);
  });

  testWidgets('the sweep reaches cards that start off-screen', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final ran = <String>[];

    await tester.pumpWidget(
      _host(
        controller: controller,
        cards: [
          for (var i = 0; i < 8; i++)
            _FakeCard(
              id: 'sweep-$i',
              body: (report) async {
                ran.add('sweep-$i');
                report('done');
              },
            ),
        ],
      ),
    );

    // Only the first screenful is built to begin with — which is exactly why
    // the old ladder could not reach the rest.
    expect(IssueCardStore.instance.mountedIds('test').length, lessThan(8));

    final sweep = IssueSweep(
      scrollController: controller,
      scope: 'test',
      betweenCards: Duration.zero,
    );
    addTearDown(sweep.dispose);

    final done = sweep.start();
    await tester.pumpAndSettle();
    await done;

    expect(ran, [for (var i = 0; i < 8; i++) 'sweep-$i']);
    expect(sweep.completed, 8);
    expect(sweep.active, isFalse);
  });

  testWidgets('a card that never returns does not stall the sweep', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final hang = Completer<void>();
    addTearDown(() {
      if (!hang.isCompleted) hang.complete();
    });
    final ran = <String>[];

    await tester.pumpWidget(
      _host(
        controller: controller,
        cards: [
          _FakeCard(
            id: 'hangs',
            body: (report) async {
              ran.add('hangs');
              await hang.future;
            },
          ),
          _FakeCard(
            id: 'after',
            body: (report) async {
              ran.add('after');
              report('done');
            },
          ),
        ],
      ),
    );

    final sweep = IssueSweep(
      scrollController: controller,
      scope: 'test',
      cardTimeout: const Duration(milliseconds: 50),
      betweenCards: Duration.zero,
    );
    addTearDown(sweep.dispose);

    final done = sweep.start();
    await tester.pumpAndSettle();
    await done;

    expect(ran, ['hangs', 'after']);
    expect(
      IssueCardStore.instance.entry('hangs').status,
      contains('TIMED OUT'),
    );
    expect(IssueCardStore.instance.entry('hangs').running, isFalse);
  });

  testWidgets("a sweep only runs its own tab's cards", (tester) async {
    final mine = ScrollController();
    final theirs = ScrollController();
    addTearDown(mine.dispose);
    addTearDown(theirs.dispose);
    final ran = <String>[];

    Widget card(String id) => _FakeCard(
      id: id,
      height: 80,
      body: (report) async {
        ran.add(id);
        report('done');
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                height: 200,
                child: IssueCardScope(
                  name: 'mine',
                  child: ListView(controller: mine, children: [card('mine-1')]),
                ),
              ),
              SizedBox(
                height: 200,
                child: IssueCardScope(
                  name: 'theirs',
                  child: ListView(
                    controller: theirs,
                    children: [card('theirs-1')],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final sweep = IssueSweep(
      scrollController: mine,
      scope: 'mine',
      betweenCards: Duration.zero,
    );
    addTearDown(sweep.dispose);

    final done = sweep.start();
    await tester.pumpAndSettle();
    await done;

    expect(ran, ['mine-1']);
  });
}
