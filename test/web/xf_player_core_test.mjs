// Tests du moteur de lecture web (web/xf-player-core.js).
//
// Lancement : node --test "test/web/*_test.mjs"
//
// Le moteur est un script navigateur (IIFE sur `window`) : on l'exécute dans
// un contexte vm avec un DOM minimal et un faux mpegts.js qui capture la
// configuration reçue.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(
  new URL('../../web/xf-player-core.js', import.meta.url),
  'utf8',
);

function fakeEventTarget() {
  return { addEventListener() {}, removeEventListener() {} };
}

/** Charge le moteur et renvoie la config passée à mpegts.createPlayer. */
function liveMpegtsConfig({ profile } = {}) {
  const created = [];
  const video = {
    ...fakeEventTarget(),
    canPlayType: () => '',
    play: () => Promise.resolve(),
    buffered: { length: 0 },
    seekable: { length: 0 },
  };
  const window = {
    ...fakeEventTarget(),
    console: { log() {} },
    location: { origin: 'https://xf.test', href: 'https://xf.test/', search: '' },
    parent: { postMessage() {} },
    mpegts: {
      isSupported: () => true,
      Events: { MEDIA_INFO: 'media_info', ERROR: 'error' },
      createPlayer(mediaDataSource, config) {
        created.push({ mediaDataSource, config });
        return { on() {}, attachMediaElement() {}, load() {} };
      },
    },
  };
  const context = vm.createContext({
    window,
    location: window.location,
    document: fakeEventTarget(),
    URLSearchParams,
    setInterval: () => 0,
    clearInterval() {},
    setTimeout,
  });
  vm.runInContext(source, context);

  const XFPlayer = window.XFPlayer;
  const player = new XFPlayer({
    video,
    url: '/api/live/1/turbo.ts',
    type: 'live',
  });
  if (profile) player.profile = window.XFPlayerProfiles[profile];
  player._createMpegts(true);
  assert.equal(created.length, 1);
  return created[0].config;
}

// Les panneaux Xtream relaient souvent une source HLS : le flux arrive par
// rafales d'environ 6 s séparées de silences complets (mesuré en prod).
const UPSTREAM_BURST_GAP_S = 7;

for (const profile of ['fast', 'balanced', 'safe']) {
  test(`live (${profile}) : la marge gardée après rattrapage couvre un silence amont`, () => {
    const c = liveMpegtsConfig({ profile });
    if (!c.liveBufferLatencyChasing) return; // pas de saut = rien à vérifier
    assert.ok(
      c.liveBufferLatencyMinRemain >= UPSTREAM_BURST_GAP_S,
      `MinRemain ${c.liveBufferLatencyMinRemain}s < silence amont ${UPSTREAM_BURST_GAP_S}s : ` +
        'chaque rafale déclenche un saut puis une coupure',
    );
  });

  test(`live (${profile}) : une rafale normale ne déclenche pas de saut`, () => {
    const c = liveMpegtsConfig({ profile });
    if (!c.liveBufferLatencyChasing) return;
    // Après une rafale, le buffer vaut la marge + une rafale entière.
    assert.ok(
      c.liveBufferLatencyMaxLatency >=
        c.liveBufferLatencyMinRemain + 2 * UPSTREAM_BURST_GAP_S,
      'seuil de rattrapage trop proche de la marge : sauts à chaque rafale',
    );
  });
}

test('live : le retard est résorbé en douceur (liveSync) plutôt que par sauts', () => {
  const c = liveMpegtsConfig();
  assert.equal(c.liveSync, true);
  assert.ok(c.liveSyncPlaybackRate > 1 && c.liveSyncPlaybackRate <= 1.2);
  assert.ok(c.liveSyncTargetLatency < c.liveSyncMaxLatency);
  assert.ok(c.liveSyncMaxLatency <= c.liveBufferLatencyMaxLatency);
});

test('live : le buffer déjà lu est purgé (sinon QuotaExceeded en séance longue)', () => {
  const c = liveMpegtsConfig();
  assert.equal(c.autoCleanupSourceBuffer, true);
  assert.ok(
    c.autoCleanupMinBackwardDuration < c.autoCleanupMaxBackwardDuration,
  );
});
