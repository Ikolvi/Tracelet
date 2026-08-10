import 'package:flutter/material.dart';
import 'package:tracelet_example/issues/issue_run_harness.dart';

/// Propagates the current issue-search query down to every [IssueCardShell] so
/// each card can filter itself against its own on-screen text (title +
/// description + [IssueCardShell.keywords]) — not just an issue number.
///
/// The tab wraps the issue list in one of these; because [IssueCardShell]
/// depends on it via [of], changing [query] rebuilds only the shells (even
/// `const` cards), which then show or hide themselves.
class IssueSearchScope extends InheritedWidget {
  const IssueSearchScope({
    required this.query,
    required super.child,
    super.key,
  });

  /// The active, already-lowercased search query. Empty means "show all".
  final String query;

  /// Returns the nearest scope's query, or an empty string when there is none
  /// (so cards used outside a search context simply always render).
  static String of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<IssueSearchScope>();
    return scope?.query ?? '';
  }

  @override
  bool updateShouldNotify(IssueSearchScope oldWidget) =>
      query != oldWidget.query;
}

/// Shared visual shell for the issue verification cards (#212/#213/#214…):
/// title, description, a monospace status box, and a single Run button.
///
/// The shell also participates in search: when an [IssueSearchScope] is present
/// and its query matches neither the [title], [description], nor [keywords],
/// the card hides itself. This makes free-text search work against the real
/// text shown on the card, with no per-card wiring.
///
/// Tapping Run calls [prepareIssueRun] before [onRun] (unless [prepare] is
/// false), which is what makes a card runnable straight from a cold start
/// instead of only after the home page's Initialize, and pins the config every
/// card begins from. See that function for what each of those was costing.
class IssueCardShell extends StatelessWidget {
  const IssueCardShell({
    required this.title,
    required this.description,
    required this.status,
    required this.running,
    required this.onRun,
    super.key,
    this.runLabel = 'Run Test',
    this.keywords = '',
    this.prepare = true,
  });

  final String title;
  final String description;
  final String status;
  final bool running;

  /// Invoked when the Run button is tapped. May be async; the return value is
  /// ignored (a `Future<void> Function()` is assignable to `VoidCallback`).
  final VoidCallback onRun;
  final String runLabel;

  /// Extra search terms that are not already present in [title]/[description]
  /// (e.g. API names or symptoms a user might search for). Matched in addition
  /// to the visible text.
  final String keywords;

  /// Whether to run [prepareIssueRun] before [onRun] — `ready()` plus the demo
  /// baseline config, so the card does not depend on the home page having been
  /// initialized, nor on whichever card ran before it. Set false only for a
  /// card that must observe an unconfigured SDK.
  final bool prepare;

  @override
  Widget build(BuildContext context) {
    final query = IssueSearchScope.of(context);
    if (query.isNotEmpty) {
      final haystack = '$title $description $keywords'.toLowerCase();
      if (!haystack.contains(query)) {
        return const SizedBox.shrink();
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(description),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                status,
                // Explicit dark text: the box background is always light
                // (grey.shade100), so without this the status is invisible in
                // dark mode (default text color becomes light → white-on-white).
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: running
                  ? null
                  : () async {
                      if (prepare) {
                        try {
                          await prepareIssueRun();
                        } catch (e) {
                          // Best effort: run the card anyway so it reports the
                          // failure in its own status box, where it is visible,
                          // rather than the tap doing nothing at all.
                          debugPrint('prepareIssueRun failed: $e');
                        }
                      }
                      onRun();
                    },
              icon: const Icon(Icons.play_arrow),
              label: Text(runLabel),
            ),
          ],
        ),
      ),
    );
  }
}
