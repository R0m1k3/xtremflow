import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xtremflow/features/iptv/widgets/live_preview_controller.dart';

const _ts1 = '/api/live/1/turbo.ts?playlist=p1';
const _ts2 = '/api/live/2/turbo.ts?playlist=p1';

void main() {
  late ProviderContainer c;
  late List<LivePreviewState> seen;

  LivePreviewNotifier n() => c.read(livePreviewProvider.notifier);
  PreviewPhase phase() => c.read(livePreviewProvider).phase;

  void setUpContainer() {
    c = ProviderContainer();
    seen = [];
    c.listen<LivePreviewState>(
      livePreviewProvider,
      (_, next) => seen.add(next),
      fireImmediately: true,
    );
  }

  tearDown(() => c.dispose());

  testWidgets('two requests 200 ms apart load only the second channel', (
    tester,
  ) async {
    setUpContainer();
    n().request('1', _ts1);
    await tester.pump(const Duration(milliseconds: 200));
    n().request('2', _ts2);
    await tester.pump(const Duration(milliseconds: 400));

    final loads = seen.where((s) => s.phase == PreviewPhase.loading).toList();
    expect(loads, hasLength(1));
    expect(loads.single.streamId, '2');
    // While a channel waits, the iframe is blank.
    expect(
      seen
          .where((s) => s.phase == PreviewPhase.waiting)
          .every((s) => s.url == null),
      isTrue,
    );
    n().stop();
  });

  testWidgets('stop() while waiting goes back to idle without loading', (
    tester,
  ) async {
    setUpContainer();
    n().request('1', _ts1);
    await tester.pump(const Duration(milliseconds: 100));
    n().stop();
    await tester.pump(const Duration(seconds: 1));
    expect(phase(), PreviewPhase.idle);
    expect(seen.any((s) => s.phase == PreviewPhase.loading), isFalse);
  });

  testWidgets('no picture for 10 s: unavailable, then idle after 60 s', (
    tester,
  ) async {
    setUpContainer();
    n().request('1', _ts1);
    await tester.pump(const Duration(milliseconds: 350));
    expect(phase(), PreviewPhase.loading);
    await tester.pump(const Duration(seconds: 10));
    expect(phase(), PreviewPhase.unavailable);
    expect(c.read(livePreviewProvider).url, isNull);

    // No attempt during the cooldown, and a late "playing" is ignored.
    n().request('2', _ts2);
    n().onPlayerMessage('playing');
    expect(phase(), PreviewPhase.unavailable);

    await tester.pump(const Duration(seconds: 60));
    expect(phase(), PreviewPhase.idle);
  });

  testWidgets('an error posted by the player makes it unavailable', (
    tester,
  ) async {
    setUpContainer();
    n().request('1', _ts1);
    await tester.pump(const Duration(milliseconds: 350));
    n().onPlayerMessage('playing');
    expect(phase(), PreviewPhase.playing);
    n().onPlayerMessage('error');
    expect(phase(), PreviewPhase.unavailable);
    // stop() keeps the cooldown.
    n().stop();
    expect(phase(), PreviewPhase.unavailable);
    await tester.pump(const Duration(seconds: 60));
    expect(phase(), PreviewPhase.idle);
  });

  testWidgets('"playing" outside loading is ignored', (tester) async {
    setUpContainer();
    n().onPlayerMessage('playing');
    expect(phase(), PreviewPhase.idle);
    n().request('1', _ts1);
    n().onPlayerMessage('playing');
    expect(phase(), PreviewPhase.waiting);
    n().stop();
  });

  testWidgets('3 min without activity: idle; activity keeps it running', (
    tester,
  ) async {
    setUpContainer();
    n().request('1', _ts1);
    await tester.pump(const Duration(milliseconds: 350));
    n().onPlayerMessage('playing');
    await tester.pump(const Duration(minutes: 2));
    n().onActivity();
    await tester.pump(const Duration(minutes: 2));
    expect(phase(), PreviewPhase.playing);
    await tester.pump(const Duration(minutes: 1, seconds: 1));
    expect(phase(), PreviewPhase.idle);
  });

  testWidgets('hidden tab stops the preview', (tester) async {
    setUpContainer();
    n().request('1', _ts1);
    await tester.pump(const Duration(milliseconds: 350));
    n().onHidden();
    expect(phase(), PreviewPhase.idle);
    expect(c.read(livePreviewProvider).url, isNull);
  });

  testWidgets('setting off: request has no effect', (tester) async {
    setUpContainer();
    n().setEnabled(false);
    n().request('1', _ts1);
    await tester.pump(const Duration(seconds: 1));
    expect(phase(), PreviewPhase.idle);
    n().setEnabled(true);
    n().request('1', _ts1);
    expect(phase(), PreviewPhase.waiting);
    n().stop();
  });

  testWidgets('the url asks turbo.ts for a preview connection', (tester) async {
    setUpContainer();
    n().request('1', _ts1);
    await tester.pump(const Duration(milliseconds: 350));
    final url = c.read(livePreviewProvider).url!;
    expect(url, startsWith('player_lite.html?url='));
    expect(url, endsWith('&type=live&turbo=true&preview=1'));
    final ts = Uri.parse(url).queryParameters['url']!;
    expect(ts, '/api/live/1/turbo.ts?playlist=p1&preview=1');
    n().stop();

    expect(
      Uri.parse(LivePreviewNotifier.previewUrl('/api/live/3/turbo.ts'))
          .queryParameters['url'],
      '/api/live/3/turbo.ts?preview=1',
    );
  });
}
