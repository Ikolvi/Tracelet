import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Runs every card on an issues tab, top to bottom (#372).
///
/// **Why it scrolls.** A card's test lives in that card's [State], and the tab's
/// `ListView` only builds the cards near the viewport — so from a standing start
/// the tab cannot reach ~70 of the ~75 tests on the page, because those widgets
/// do not exist yet. The sweep therefore walks the list: run everything mounted,
/// scroll a screen, run whatever that mounted, repeat. Cards enlist themselves
/// through [IssueCardStore] as they mount, so a card added tomorrow is swept
/// with no list to update here, and the scrolling doubles as the progress
/// indicator the old version never had.
///
/// Results are safe from the scrolling: they live in [IssueCardStore], not in
/// the cards being scrolled past.
class IssueSweep extends ChangeNotifier {
  IssueSweep({
    required this.scrollController,
    required this.scope,
    this.cardTimeout = const Duration(seconds: 60),
    this.betweenCards = const Duration(milliseconds: 250),
  });

  final ScrollController scrollController;

  /// Which tab's cards to run — see [IssueCardScope]. Must match the name the
  /// tab wraps its list in.
  final String scope;

  /// How long a single card gets before the sweep gives up on it and moves on.
  ///
  /// The old sweep awaited each test with no bound, so one card that never
  /// returned — `getCurrentPosition` waiting on a GPS fix indoors, a sync
  /// against a server that is not there — hung the whole run with no way out
  /// short of leaving the page.
  final Duration cardTimeout;

  /// Breather between cards. These tests reconfigure and restart the SDK; back
  /// to back with no gap, a card can observe the previous card's teardown.
  final Duration betweenCards;

  final Set<String> _done = <String>{};
  bool _active = false;
  bool _cancelled = false;
  String? _current;
  bool _disposed = false;

  /// Whether a sweep is in progress.
  bool get active => _active;

  /// How many cards this sweep has run so far. The total is not known up front:
  /// the list is lazy, so the sweep discovers cards as it scrolls to them.
  int get completed => _done.length;

  /// Id of the card being run, for the progress line.
  String? get current => _current;

  /// Asks the sweep to stop after the card in flight. That card is not
  /// interrupted — it is talking to the SDK, and cutting it off mid-run would
  /// leave the SDK in whatever state it had reached.
  void cancel() {
    if (!_active) return;
    _cancelled = true;
    _notify();
  }

  Future<void> start() async {
    if (_active) return;
    _active = true;
    _cancelled = false;
    _done.clear();
    _current = null;
    _notify();

    try {
      await _scrollToTop();
      while (!_cancelled) {
        await _runMountedCards();
        if (_cancelled) break;
        if (!await _scrollForward()) {
          // At the bottom. The last scroll may still have mounted cards that
          // have not run; one more pass, then there is nothing left to reach.
          final remaining = IssueCardStore.instance
              .mountedIds(scope)
              .where((id) => !_done.contains(id));
          if (remaining.isEmpty) break;
        }
      }
    } finally {
      _active = false;
      _current = null;
      _notify();
    }
  }

  Future<void> _runMountedCards() async {
    // Snapshot: scrolling during a run mounts and unmounts cards, which mutates
    // the store's list underneath us.
    final pending = IssueCardStore.instance
        .mountedIds(scope)
        .where((id) => !_done.contains(id))
        .toList();

    for (final id in pending) {
      if (_cancelled) return;
      _done.add(id);
      _current = id;
      _notify();
      await IssueCardStore.instance
          .run(id)
          .timeout(
            cardTimeout,
            onTimeout: () {
              // The test is still out there — `timeout` bounds the wait, not the
              // work — so it may yet overwrite this with its real result. Say so
              // rather than leaving a card that reads as though it never ran.
              IssueCardStore.instance.setStatus(
                id,
                '⏱ TIMED OUT: still running after '
                '${cardTimeout.inSeconds}s, so Execute All moved on. Run this '
                'card on its own to see how it finishes.',
              );
              IssueCardStore.instance.setRunning(id, running: false);
            },
          );
      if (_cancelled) return;
      await Future<void>.delayed(betweenCards);
    }
  }

  Future<void> _scrollToTop() async {
    if (!scrollController.hasClients) return;
    if (scrollController.position.pixels <= 0) return;
    await scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    await _settle();
  }

  /// Advances roughly a screen. Returns false once the list is at its end.
  Future<bool> _scrollForward() async {
    if (!scrollController.hasClients) return false;
    final position = scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 1) {
      await _settle();
      return false;
    }
    final target = math.min(
      position.pixels + position.viewportDimension * 0.75,
      position.maxScrollExtent,
    );
    await scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
    );
    await _settle();
    return true;
  }

  /// Waits for the frame that builds whatever the scroll just revealed, so those
  /// cards have registered before the next pass looks for them.
  Future<void> _settle() async {
    await SchedulerBinding.instance.endOfFrame;
    await SchedulerBinding.instance.endOfFrame;
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelled = true;
    super.dispose();
  }
}

/// The progress strip shown under an issues tab's toolbar while a sweep runs.
class IssueSweepBanner extends StatelessWidget {
  const IssueSweepBanner({required this.sweep, super.key});

  final IssueSweep sweep;

  @override
  Widget build(BuildContext context) {
    if (!sweep.active) return const SizedBox.shrink();
    final current = sweep.current;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const LinearProgressIndicator(minHeight: 3),
          const SizedBox(height: 6),
          Text(
            current == null
                ? 'Execute All: starting…'
                : 'Execute All: running $current — ${sweep.completed} card(s) '
                      'done',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
