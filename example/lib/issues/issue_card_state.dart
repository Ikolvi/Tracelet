import 'package:flutter/widgets.dart';
import 'package:tracelet_example/issues/issue_run_harness.dart';

/// A card's primary action — what its Run button does, and what Execute All
/// invokes on its behalf.
typedef IssueRunner = Future<void> Function();

/// What one issue card remembers between builds: the last status it printed and
/// whether its test is currently in flight (#373).
///
/// This is deliberately two fields and a listener list. Nothing here references
/// a [Widget], [Element] or [RenderObject], so an entry costs a short string
/// even for a card that has been scrolled past a hundred times.
class IssueCardEntry extends ChangeNotifier {
  String _status = 'Idle';
  bool _running = false;

  /// The last message the card printed. `'Idle'` until it is first run.
  String get status => _status;

  /// Whether the card's test is running right now — drives the disabled Run
  /// button, and is set from the test itself rather than from the widget, so it
  /// clears correctly even if the card was unmounted mid-run.
  bool get running => _running;

  void _setStatus(String value) {
    if (_status == value) return;
    _status = value;
    notifyListeners();
  }

  void _setRunning(bool value) {
    if (_running == value) return;
    _running = value;
    notifyListeners();
  }
}

class _Registration {
  const _Registration({
    required this.owner,
    required this.run,
    required this.prepare,
    required this.scope,
  });

  /// Which tab's list the card is in. The store is app-wide but a sweep belongs
  /// to one tab, and `TabBarView` can have both tabs built at once while a swipe
  /// is in flight — without this, a sweep could reach across and run the other
  /// tab's cards.
  final String scope;

  /// Whoever registered this runner — the card's [State], or the
  /// [IssueRunnerScope] element for tab-built cards. Used so a stale owner
  /// cannot unregister a runner that has since been replaced.
  final Object owner;
  final IssueRunner run;

  /// Whether [prepareIssueRun] should run first, mirroring what the card's own
  /// Run button does.
  final bool prepare;
}

/// Holds every issue card's result outside the widget tree, and tracks which
/// cards are currently mounted so Execute All can drive them (#372, #373).
///
/// **Why a store rather than keep-alive.** The Issues page is one long
/// `ListView` whose children are unmounted as they leave the viewport, which is
/// what discards a card's result. The one-line fix is
/// `AutomaticKeepAliveClientMixin`, and it is the wrong one: it pins each card's
/// whole element and render subtree for the lifetime of the page and turns the
/// list into a non-virtualized one, so scrolling to the bottom once leaves ~70
/// laid-out card subtrees resident — a number that only grows as cards are
/// added. Keeping the *result* instead costs a map entry and a string per card,
/// and leaves the widgets free to be recycled exactly as they are today.
///
/// The runner registry is scoped to mounted cards on purpose: a runner closes
/// over a live [State], so holding one for every card ever seen would quietly
/// reintroduce the retention this store exists to avoid.
class IssueCardStore {
  IssueCardStore._();

  static final IssueCardStore instance = IssueCardStore._();

  final Map<String, IssueCardEntry> _entries = <String, IssueCardEntry>{};
  final Map<String, _Registration> _runners = <String, _Registration>{};
  final List<String> _mountOrder = <String>[];

  /// The remembered state for [id], created on first use.
  IssueCardEntry entry(String id) =>
      _entries.putIfAbsent(id, IssueCardEntry.new);

  void setStatus(String id, String status) => entry(id)._setStatus(status);

  void setRunning(String id, {required bool running}) =>
      entry(id)._setRunning(running);

  /// Ids of [scope]'s cards that are mounted right now, in the order they
  /// mounted.
  ///
  /// Sweeping the list downward mounts cards top to bottom, so for Execute All
  /// this reads as list order without the tab having to maintain a second,
  /// hand-synchronised list of every card on the page.
  List<String> mountedIds(String scope) => List<String>.unmodifiable(
    _mountOrder.where((id) => _runners[id]?.scope == scope),
  );

  void registerRunner({
    required String id,
    required Object owner,
    required IssueRunner run,
    required String scope,
    bool prepare = true,
  }) {
    if (!_runners.containsKey(id)) _mountOrder.add(id);
    _runners[id] = _Registration(
      owner: owner,
      run: run,
      prepare: prepare,
      scope: scope,
    );
  }

  /// Drops [id]'s runner, but only if [owner] still owns it. A card that is
  /// scrolled back into view mounts its new [State] before the old one is
  /// disposed, and without this check the newcomer's registration would be
  /// removed by its predecessor's `dispose`.
  void unregisterRunner({required String id, required Object owner}) {
    if (_runners[id]?.owner != owner) return;
    _runners.remove(id);
    _mountOrder.remove(id);
  }

  bool isRegistered(String id) => _runners.containsKey(id);

  /// Runs [id] the way its own Run button would, including the shared
  /// [prepareIssueRun] preamble. Returns normally when [id] has no runner.
  Future<void> run(String id) async {
    final registration = _runners[id];
    if (registration == null) return;
    if (registration.prepare) {
      try {
        await prepareIssueRun();
      } catch (e) {
        // Same call as the Run button makes, and the same handling: report the
        // failure through the card rather than abandoning the run, so it lands
        // somewhere the user can read it.
        debugPrint('prepareIssueRun failed for $id: $e');
      }
    }
    await registration.run();
  }
}

/// Names the list a card is in, so Execute All on one tab sweeps that tab.
///
/// Each issues tab wraps its list in one of these; cards look it up rather than
/// being told, so a card can be moved between tabs without rewiring.
class IssueCardScope extends InheritedWidget {
  const IssueCardScope({required this.name, required super.child, super.key});

  final String name;

  /// The enclosing list's name, or `'default'` for a card used outside a tab.
  static String of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<IssueCardScope>()?.name ??
      'default';

  @override
  bool updateShouldNotify(IssueCardScope oldWidget) => name != oldWidget.name;
}

/// Card state that lives in [IssueCardStore] instead of in the [State].
///
/// A card mixes this in and drops its own `_status`/`_running` fields. Two
/// things follow. Its result survives being scrolled out of view, because the
/// result was never in the widget to begin with. And a test that finishes after
/// its card was unmounted still reports — the old `if (mounted) setState(...)`
/// guard silently discarded those, which is precisely what a scrolling Execute
/// All sweep provoked.
///
/// Mixing this in also enlists the card in Execute All, which is why
/// [cardRunner] is required.
mixin IssueCardRun<T extends StatefulWidget> on State<T> {
  /// Identity for the card's remembered state. The widget type is unique per
  /// card and stable across rebuilds, which is all this needs to be.
  String get cardId => widget.runtimeType.toString();

  /// The card's primary action — normally the same callback it hands to
  /// `IssueCardShell.onRun`.
  ///
  /// Null for a card that has to stay manual: a start/stop toggle, or a
  /// two-phase repro that needs the device rebooted or the app killed between
  /// halves. Execute All skips those rather than firing half of them.
  IssueRunner? get cardRunner;

  /// Whether Execute All should call [prepareIssueRun] before [cardRunner].
  /// Mirrors `IssueCardShell.prepare`; override alongside it.
  bool get prepareBeforeRun => true;

  IssueCardEntry get _entry => IssueCardStore.instance.entry(cardId);

  /// The card's last reported message.
  String get status => _entry.status;

  /// Whether the card's test is in flight.
  bool get running => _entry.running;

  /// Reports [value] as the card's result. Safe to call after the card has been
  /// unmounted — the message is kept and shown when the card comes back.
  void setStatus(String value) =>
      IssueCardStore.instance.setStatus(cardId, value);

  void setRunning({required bool running}) =>
      IssueCardStore.instance.setRunning(cardId, running: running);

  @override
  void initState() {
    super.initState();
    _entry.addListener(_onEntryChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Registration waits until here because it needs [IssueCardScope], and an
    // inherited widget cannot be looked up from `initState`.
    final runner = cardRunner;
    if (runner == null) return;
    IssueCardStore.instance.registerRunner(
      id: cardId,
      owner: this,
      run: runner,
      scope: IssueCardScope.of(context),
      prepare: prepareBeforeRun,
    );
  }

  @override
  void dispose() {
    _entry.removeListener(_onEntryChanged);
    IssueCardStore.instance.unregisterRunner(id: cardId, owner: this);
    super.dispose();
  }

  void _onEntryChanged() {
    if (mounted) setState(() {});
  }
}

/// Enlists a card that the tab builds itself — the older `_buildIssueCard`
/// entries, whose test lives on the tab's [State] rather than in a card widget
/// — in Execute All, with the same mounted-only lifetime the mixin gives the
/// card widgets.
///
/// Those cards keep their status on the tab, which outlives scrolling, so this
/// deals only with the runner. Pass a null [run] for a card that should stay
/// manual (a start/stop toggle, or a repro that needs the app backgrounded);
/// unregistered cards are skipped by the sweep.
class IssueRunnerScope extends StatefulWidget {
  const IssueRunnerScope({
    required this.id,
    required this.run,
    required this.child,
    super.key,
  });

  final String id;
  final IssueRunner? run;
  final Widget child;

  @override
  State<IssueRunnerScope> createState() => _IssueRunnerScopeState();
}

class _IssueRunnerScopeState extends State<IssueRunnerScope> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _register();
  }

  @override
  void didUpdateWidget(IssueRunnerScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The tab rebuilds these on every setState, handing over a fresh closure
    // each time; the registry has to point at the current one.
    if (oldWidget.id != widget.id) {
      IssueCardStore.instance.unregisterRunner(id: oldWidget.id, owner: this);
    }
    _register();
  }

  void _register() {
    final run = widget.run;
    if (run == null) return;
    IssueCardStore.instance.registerRunner(
      id: widget.id,
      owner: this,
      run: run,
      scope: IssueCardScope.of(context),
      // These predate the shared preamble and read config the home page or a
      // scanned QR left behind, so running them is left exactly as their own
      // button leaves it.
      prepare: false,
    );
  }

  @override
  void dispose() {
    IssueCardStore.instance.unregisterRunner(id: widget.id, owner: this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
