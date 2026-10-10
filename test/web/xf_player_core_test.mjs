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

test('télémétrie : une coupure (waiting → playing) est remontée avec sa durée', async () => {
  const sent = [];
  const listeners = {};
  const video = {
    addEventListener(type, fn) { (listeners[type] ||= []).push(fn); },
    removeEventListener() {},
    canPlayType: () => '',
    play: () => Promise.resolve(),
    buffered: { length: 0 },
    seekable: { length: 0 },
    currentTime: 12,
    playbackRate: 1,
  };
  const fire = (type) => (listeners[type] || []).forEach((fn) => fn());
  const window = {
    addEventListener() {}, removeEventListener() {},
    console: { log() {} },
    location: { origin: 'https://xf.test', href: 'https://xf.test/', search: '' },
    parent: { postMessage() {} },
    localStorage: { getItem: () => 'tok' },
  };
  let now = 1000;
  const context = vm.createContext({
    window,
    location: window.location,
    document: { addEventListener() {}, removeEventListener() {} },
    URLSearchParams,
    setInterval: () => 0,
    clearInterval() {},
    setTimeout,
    Date: { now: () => now },
    fetch: (url, opts) => { sent.push({ url, body: JSON.parse(opts.body) }); return Promise.resolve(); },
  });
  vm.runInContext(source, context);
  const player = new window.XFPlayer({ video, url: '/api/live/554034/turbo.ts', type: 'live' });
  player._wireVideoEvents();

  fire('playing');            // premier affichage
  now += 1000; fire('waiting');
  now += 4200; fire('playing'); // reprise 4,2 s plus tard

  const stall = sent.map((s) => s.body).find((b) => b.event === 'stall');
  assert.ok(stall, 'aucun événement stall envoyé');
  assert.equal(stall.ms, 4200);
  assert.equal(stall.ch, '554034');
  assert.equal(sent[0].url, '/api/player-log');
});

// Freeze mesuré en prod (télémétrie) : le panneau s'est tu ~15-20 s sur une
// connexion restée ouverte, alors que le lecteur n'avait gardé que 11-16 s.
const PROVIDER_OUTAGE_S = 18;

test('live : la réserve visée couvre un silence du panneau de ~18 s', () => {
  const c = liveMpegtsConfig();
  // liveSync ramène le retard vers la cible : c'est la réserve en régime
  // établi. Elle doit dépasser le silence mesuré.
  assert.ok(c.liveSyncTargetLatency > PROVIDER_OUTAGE_S,
    `cible ${c.liveSyncTargetLatency}s < silence mesuré ${PROVIDER_OUTAGE_S}s`);
  assert.ok(c.liveBufferLatencyMinRemain > PROVIDER_OUTAGE_S);
});

test('live : la rafale de rattrapage après un silence ne fait pas sauter le programme', () => {
  // Mesuré en prod : après un silence, le panneau renvoie d'un coup tout le
  // retard ; l'avance a dépassé 45 s et le lecteur a sauté 2 fois de 20 s
  // (programme perdu). Le retard doit se résorber en douceur (liveSync).
  const observedPeakAhead = 45;
  const c = liveMpegtsConfig();
  assert.ok(c.liveBufferLatencyMaxLatency >= 2 * observedPeakAhead - 10,
    `saut dès ${c.liveBufferLatencyMaxLatency}s d'avance : la rafale de rattrapage le déclenche`);
  assert.ok(c.liveSyncMaxLatency < observedPeakAhead,
    'liveSync doit déjà accélérer avant ce niveau');
});

test('live : la vidéo déjà vue est purgée plus tôt, l\'avance étant plus grande', () => {
  const c = liveMpegtsConfig();
  assert.ok(c.autoCleanupMaxBackwardDuration <= 30);
});

test('reprise après coupure : attendre une vraie réserve avant de relire', () => {
  const calls = [];
  const listeners = {};
  let ahead = 0;
  const video = {
    addEventListener(type, fn) { (listeners[type] ||= []).push(fn); },
    removeEventListener() {},
    canPlayType: () => '',
    play: () => { calls.push('play'); return Promise.resolve(); },
    pause: () => { calls.push('pause'); },
    get buffered() { return { length: 1, start: () => 0, end: () => 100 + ahead }; },
    seekable: { length: 0 },
    currentTime: 100,
    playbackRate: 1,
    seeking: false,
  };
  const fire = (type) => (listeners[type] || []).forEach((fn) => fn());
  const window = {
    addEventListener() {}, removeEventListener() {},
    console: { log() {} },
    location: { origin: 'https://xf.test', href: 'https://xf.test/', search: '' },
    parent: { postMessage() {} },
  };
  const context = vm.createContext({
    window, location: window.location,
    document: { addEventListener() {}, removeEventListener() {} },
    URLSearchParams, setInterval: () => 0, clearInterval() {}, setTimeout, Date,
  });
  vm.runInContext(source, context);
  const player = new window.XFPlayer({ video, url: '/api/live/1/turbo.ts', type: 'live' });
  player.mpegts = {}; // flux MPEG-TS en cours
  player._wireVideoEvents();

  fire('playing');
  fire('waiting');            // le panneau se tait
  assert.deepEqual(calls.slice(-1), ['pause'], 'le lecteur doit se mettre en attente');

  ahead = 1;                  // 1 s arrive : trop peu, ne pas repartir
  player._checkHold();
  assert.ok(!calls.slice(1).includes('play'), 'reparti avec 1 s : recoupera aussitôt');

  ahead = 5;                  // vraie réserve reconstituée
  player._checkHold();
  assert.equal(calls.at(-1), 'play');
});

test('live : le buffer déjà lu est purgé (sinon QuotaExceeded en séance longue)', () => {
  const c = liveMpegtsConfig();
  assert.equal(c.autoCleanupSourceBuffer, true);
  assert.ok(
    c.autoCleanupMinBackwardDuration < c.autoCleanupMaxBackwardDuration,
  );
});
