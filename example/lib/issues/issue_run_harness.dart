import 'package:tracelet/tracelet.dart';
import 'package:tracelet_example/demo_config.dart';

/// Puts the SDK into the state every issue card is written against, before the
/// card's own body runs. [IssueCardShell] calls this for you on every Run tap.
///
/// Two things went wrong without it.
///
/// **The SDK was not ready.** A card that calls `start()`, `setConfig()` or any
/// location API on an SDK that has never had `ready()` gets
/// `PlatformException(NOT_READY, "Call ready() before start()")`, which the
/// card reports as a red failure of the issue it is testing. The workaround was
/// to go back to the home page and press Initialize first — so a card's result
/// depended on how the app had been driven before it, and the failure it
/// printed named the wrong thing.
///
/// **The config was whatever ran last.** `ready()` and `setConfig()` both merge
/// into the persisted config rather than replacing it, so a card that sets two
/// keys inherits every other key from the last thing that configured the SDK:
/// the home page if Initialize was pressed, otherwise SDK defaults, plus
/// anything a previously-run card changed. That is a real difference in what
/// the card is testing — the demo config, for one, runs a more trigger-happy
/// motion setup than the defaults do (`shakeThreshold: 2` against 2.5,
/// `stopTimeout: 1`, `speedStationaryDelay: 30`) — and it moved depending on
/// run order.
///
/// Applying [buildDemoConfig] first pins both: the cards keep the exact
/// configuration they were written and verified against, and they get it
/// whether or not the home page was ever visited and whichever card ran before.
/// A card that needs something else still says so in its own body afterwards
/// and wins, because the merge is applied in that order.
Future<void> prepareIssueRun() async {
  // Location permission is the SDK's own precondition, not config: ready()
  // succeeds without it but start() answers PERMISSION_DENIED. Only asked for
  // when it has never been decided — a denial is the user's answer and
  // re-prompting on every Run tap would be obnoxious. Cards that need
  // background ("always") still check and report that themselves.
  final status = await Tracelet.getLocationAuthorization();
  if (status == AuthorizationStatus.notDetermined) {
    await Tracelet.requestLocationAuthorization();
  }

  await Tracelet.ready(buildDemoConfig());
}
