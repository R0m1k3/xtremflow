/* =====================================================================
 * XtremFlow — Moteur de lecture partagé
 * ---------------------------------------------------------------------
 * Objectifs :
 *   1. ZAP RAPIDE   — premier frame le plus tôt possible.
 *   2. ADAPTATIF    — si le réseau décroche, le buffer s'élargit tout seul.
 *   3. ZÉRO CDN     — hls.js / mpegts.js servis en local, chargés à la demande.
 *
 * Utilisé par player.html, player_lite.html et player_mobile.html.
 * ===================================================================== */
(function (global) {
  'use strict';

  // ------------------------------------------------------------------
  // Profils de buffer — escalade automatique en cas de micro-coupures
  // ------------------------------------------------------------------
  var PROFILES = {
    // Démarrage : le plus agressif possible.
    fast: {
      name: 'fast',
      hls: {
        maxBufferLength: 24,
        maxMaxBufferLength: 60,
        liveSyncDurationCount: 2,
        liveMaxLatencyDurationCount: 8,
        initialLiveManifestSize: 1
      },
      mpegtsStash: 64 * 1024
    },
    // 2 coupures : on respire.
    balanced: {
      name: 'balanced',
      hls: {
        maxBufferLength: 60,
        maxMaxBufferLength: 120,
        liveSyncDurationCount: 4,
        liveMaxLatencyDurationCount: 14,
        initialLiveManifestSize: 2
      },
      mpegtsStash: 192 * 1024
    },
    // 4 coupures : priorité absolue à la stabilité.
    safe: {
      name: 'safe',
      hls: {
        maxBufferLength: 120,
        maxMaxBufferLength: 240,
        liveSyncDurationCount: 8,
        liveMaxLatencyDurationCount: 24,
        initialLiveManifestSize: 3
      },
      mpegtsStash: 512 * 1024
    }
  };

  var ORDER = ['fast', 'balanced', 'safe'];

  // Erreurs MPEG-TS tolérées sur 60 s avant de basculer sur HLS.
  var MPEGTS_MAX_ERRORS = 3;

  // Après une coupure en direct, réserve à reconstituer avant de relire.
  // Repartir dès la première seconde reçue transformait un silence du
  // panneau en cascade de micro-coupures (6,3 s puis 1,7 s puis 2,0 s,
  // mesuré) ; comme mpv (cache-pause), on attend une vraie réserve.
  var REBUFFER_SECONDS = 4;
  // Au-delà, on relance quand même avec ce qu'on a.
  var REBUFFER_MAX_WAIT_MS = 15000;

  // Régulateur de vitesse du direct MPEG-TS (voir _tuneRate).
  //
  // La réserve ne venait que de l'avance envoyée par le panneau au
  // démarrage : 28 s une fois, 18 s une autre — et avec 13-20 s, un silence
  // du panneau a fini en coupure de 5,5 s (télémétrie). Sous lowAhead, on
  // lit à x0,97 (hauteur du son préservée) jusqu'à reconstituer targetAhead ;
  // au-delà de highAhead (rafale de rattrapage du panneau), x1,1 jusqu'à
  // settleHigh. Les seuils d'entrée et de sortie diffèrent : pas
  // d'oscillation de vitesse.
  var LIVE_TUNING = {
    lowAhead: 20,
    targetAhead: 25,
    settleHigh: 28,
    highAhead: 35,
    slowRate: 0.97,
    fastRate: 1.1
  };

  // ------------------------------------------------------------------
  // Chargement paresseux des libs (aucune requête inutile)
  // ------------------------------------------------------------------
  var _scriptCache = {};

  function _delay(ms) {
    return new Promise(function (resolve) { setTimeout(resolve, ms); });
  }

  function _injectScript(src) {
    return new Promise(function (resolve, reject) {
      var s = document.createElement('script');
      s.src = src;
      s.async = true;
      s.onload = function () { resolve(); };
      s.onerror = function () {
        // Laisser une balise morte dans le <head> ferait échouer une
        // éventuelle nouvelle tentative sur le même src.
        if (s.parentNode) s.parentNode.removeChild(s);
        reject(new Error('script error'));
      };
      document.head.appendChild(s);
    });
  }

  /**
   * Précise la cause d'un échec pour le message affiché et les logs :
   * 404 = lib absente de l'image déployée, 429 = quota du rate limiter,
   * échec réseau = lien coupé. Sans cela, toutes les causes se
   * ressemblaient à l'écran.
   */
  function _describeFailure(src) {
    if (typeof fetch !== 'function') return Promise.resolve('');
    return fetch(src, { credentials: 'same-origin', cache: 'no-store' })
      .then(function (r) { return r.ok ? '' : ' (HTTP ' + r.status + ')'; })
      .catch(function () { return ' (réseau injoignable)'; });
  }

  /**
   * Charge une lib vendorisée, avec une seconde tentative qui contourne le
   * cache HTTP : les libs sont servies en `max-age=86400`, donc une entrée
   * tronquée par une coupure réseau condamnait le lecteur jusqu'au vidage
   * manuel du cache navigateur. Seuls les succès sont mémorisés — une
   * promesse rejetée gardée en cache rendait tout réessai impossible pour
   * le reste de la session.
   */
  function loadScript(src) {
    if (_scriptCache[src]) return _scriptCache[src];

    var attempt = _injectScript(src)
      .catch(function () {
        return _delay(400).then(function () {
          return _injectScript(
            src + (src.indexOf('?') === -1 ? '?' : '&') + 'reload=' + Date.now()
          );
        });
      })
      .catch(function () {
        return _describeFailure(src).then(function (why) {
          throw new Error('Échec du chargement : ' + src + why);
        });
      });

    _scriptCache[src] = attempt;
    attempt.catch(function () { delete _scriptCache[src]; });
    return attempt;
  }

  /** Ouvre la connexion vers l'hôte du flux avant même de connaître l'URL finale. */
  function preconnect(url) {
    try {
      var origin = new URL(url, location.href).origin;
      if (origin === location.origin) return;
      ['preconnect', 'dns-prefetch'].forEach(function (rel) {
        var l = document.createElement('link');
        l.rel = rel;
        l.href = origin;
        l.crossOrigin = 'anonymous';
        document.head.appendChild(l);
      });
    } catch (e) { /* URL relative ou invalide : rien à préconnecter */ }
  }

  // ------------------------------------------------------------------
  // Moteur
  // ------------------------------------------------------------------
  function XFPlayer(options) {
    this.video = options.video;
    this.vendorPath = options.vendorPath || 'vendor/';
    this.logPrefix = options.logPrefix || '[XFPlayer]';

    // Callbacks UI (toutes optionnelles)
    this.onLoading = options.onLoading || function () {};
    this.onReady = options.onReady || function () {};
    this.onError = options.onError || function () {};
    this.onBlocked = options.onBlocked || function () {};
    this.onProfileChange = options.onProfileChange || function () {};

    var p = new URLSearchParams(location.search);
    this.params = p;
    this.url = options.url || p.get('url');
    this.type = options.type || p.get('type') || '';
    this.startTime = parseFloat(p.get('t') || '0');
    this.injectedDuration = parseFloat(p.get('duration') || '0');
    this.isRecording = p.get('is_recording') === 'true';

    // Décalage du média par rapport au début du contenu. Un enregistrement
    // ouvert à 45 min est transcodé par FFmpeg *depuis* 45 min : le média
    // commence à 0 alors que la lecture, elle, est à 2700 s. Tout ce qui
    // sort du lecteur (position, recherche) est exprimé en temps absolu.
    this.mediaOffset = parseFloat(p.get('offset') || '0');
    if (!isFinite(this.mediaOffset) || this.mediaOffset < 0) this.mediaOffset = 0;

    // Profil de départ : forçable via ?buffer=balanced|safe
    var forced = p.get('buffer');
    this.profile = PROFILES[forced] ? PROFILES[forced] : PROFILES.fast;
    this.profileLocked = !!PROFILES[forced];

    this.hls = null;
    this.mpegts = null;
    this._started = false;
    this._stalls = 0;
    this._stallTimes = [];
    this._mpegtsErrorTimes = [];
    this._destroyed = false;
    this._reportedTime = 0;
    this._hlsDuration = 0;

    // Écouteurs posés par cette instance, retirés à la destruction : sans
    // ça, une relance après échec laisserait l'ancienne instance réagir aux
    // commandes du parent et republier des positions périmées.
    this._listeners = [];

    // Télémétrie des incidents (voir _report) : chaque freeze vécu par
    // l'utilisateur finit dans les logs du serveur, avec sa cause.
    this._t0 = Date.now();
    this._session = Math.random().toString(36).slice(2, 8);
    var idMatch = /\/api\/(?:live|vod|recordings\/stream)\/([^/?#.]+)/.exec(this.url || '');
    this._channel = idMatch ? idMatch[1] : '';
    this._stallSince = null;
    this._stats = { stalls: 0, stallMs: 0, seeks: 0, errors: 0 };
    this._lastPos = 0;
    var self = this;
    var userOnError = this.onError;
    this.onError = function (msg) {
      self._report('error_shown', { detail: String(msg) });
      userOnError(msg);
    };
  }

  // ---------------- Télémétrie ----------------

  /** Secondes d'avance dans le buffer à la position courante. */
  XFPlayer.prototype._bufferAhead = function () {
    var v = this.video;
    try {
      for (var i = 0; i < v.buffered.length; i++) {
        if (v.buffered.start(i) <= v.currentTime + 0.5 &&
            v.buffered.end(i) >= v.currentTime) {
          return v.buffered.end(i) - v.currentTime;
        }
      }
    } catch (e) {}
    return 0;
  };

  /**
   * Remonte un incident au serveur (`POST /api/player-log`, écrit dans les
   * logs `[Player] …`). Jamais bloquant : erreurs ignorées, aucun envoi
   * sans session.
   */
  XFPlayer.prototype._report = function (event, data) {
    try {
      var token = null;
      try { token = global.localStorage.getItem('auth_token'); } catch (e) {}
      if (!token || typeof fetch !== 'function') return;
      var payload = {
        event: event,
        session: this._session,
        ch: this._channel,
        t: (Date.now() - this._t0) / 1000,
        mode: this.hls ? 'hls' : (this.mpegts ? 'ts' : 'direct'),
        profile: this.profile.name,
        buffer: this._bufferAhead(),
        pos: this.video.currentTime || 0
      };
      for (var k in data) {
        if (Object.prototype.hasOwnProperty.call(data, k)) payload[k] = data[k];
      }
      fetch('/api/player-log', {
        method: 'POST',
        keepalive: true,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + token
        },
        body: JSON.stringify(payload)
      }).catch(function () {});
    } catch (e) {}
  };

  /** addEventListener + mémorisation pour un retrait propre. */
  XFPlayer.prototype._on = function (target, type, handler, options) {
    target.addEventListener(type, handler, options);
    this._listeners.push({ target: target, type: type, handler: handler });
  };

  XFPlayer.prototype.log = function (m) {
    if (global.console && console.log) console.log(this.logPrefix + ' ' + m);
  };

  XFPlayer.prototype.send = function (msg) {
    // Cible restreinte à notre origine : l'iframe est toujours même-origine
    // que le parent Flutter, un wildcard '*' livrerait l'état du player à
    // n'importe quelle page qui embarquerait player.html.
    try { global.parent.postMessage(msg, global.location.origin); } catch (e) {}
  };

  // ---------------- Démarrage ----------------

  XFPlayer.prototype.start = function () {
    var self = this;
    if (!this.url) { this.onError('Aucun flux fourni'); return Promise.resolve(); }

    preconnect(this.url);
    this._wireVideoEvents();
    this._wireParentMessages();

    var lower = this.url.toLowerCase();
    var isHls = lower.indexOf('.m3u8') !== -1;
    var isLive = this.type === 'live';

    this.onLoading('Ouverture du flux');
    this._report('start', {});

    // Safari / iOS : HLS natif = le chemin le plus rapide, aucune lib à charger.
    if (isHls && this._canPlayNativeHls()) {
      this.log('HLS natif (Safari/iOS)');
      return Promise.resolve(this._playDirect(this.url));
    }

    if (isHls) return this._startHls();
    if (isLive || lower.indexOf('.ts') !== -1) return this._startMpegts(isLive || true);

    // VOD progressif (mp4, mkv…) : lecture directe.
    return Promise.resolve(this._playDirect(this.url));
  };

  XFPlayer.prototype._canPlayNativeHls = function () {
    return this.video.canPlayType('application/vnd.apple.mpegurl') !== '';
  };

  // ---------------- HLS ----------------

  XFPlayer.prototype._hlsConfig = function () {
    var prof = this.profile.hls;
    var isLive = this.type === 'live';

    return {
      enableWorker: true,
      lowLatencyMode: false,

      // ---- Fenêtre de buffer (pilotée par le profil) ----
      maxBufferLength: prof.maxBufferLength,
      maxMaxBufferLength: prof.maxMaxBufferLength,
      backBufferLength: 30,
      maxBufferSize: 30 * 1000 * 1000,

      // ---- Démarrage rapide ----
      // 1 seul segment suffit pour commencer (au lieu de 3) : ~2 segments
      // de latence en moins au zap, soit souvent 4 à 12 secondes gagnées.
      initialLiveManifestSize: prof.initialLiveManifestSize,
      startFragPrefetch: true,   // précharge le 1er fragment pendant le parse
      testBandwidth: false,      // pas de mesure préalable : on joue tout de suite

      // ---- Début de lecture ----
      // Un enregistrement (ou un film) est transcodé au fil de l'eau : sa
      // playlist n'a pas encore d'`EXT-X-ENDLIST`, donc hls.js la considère
      // comme du direct. Sans consigne explicite il démarre alors au « bord
      // du direct », c'est-à-dire collé au front d'encodage : la lecture
      // partait au milieu du programme et se coupait aussitôt, faute de
      // segments d'avance. `0` = au début, comme attendu d'un contenu
      // à la demande. En direct, -1 conserve le démarrage au bord du direct.
      startPosition: isLive ? -1 : (this.startTime > 0 ? this.startTime : 0),

      // ---- Live ----
      liveSyncDurationCount: prof.liveSyncDurationCount,
      // Hors direct, ces deux réglages doivent être neutralisés : ils
      // accélèrent la lecture et finissent par forcer un saut en avant pour
      // « rattraper » un direct qui n'existe pas.
      // 86400 segments = hors d'atteinte, sans recourir à Infinity dont
      // hls.js fait ensuite des multiplications.
      liveMaxLatencyDurationCount: isLive
        ? prof.liveMaxLatencyDurationCount
        : 86400,
      maxLiveSyncPlaybackRate: isLive ? 1.15 : 1,

      // ---- Robustesse ----
      nudgeOffset: 0.6,
      nudgeMaxRetries: 20,
      abrEwmaDefaultEstimate: 2000000,
      // Hors direct, la première requête de playlist peut légitimement
      // bloquer le temps que FFmpeg démarre et produise ses premiers
      // segments. Le défaut de 10 s de hls.js transformait ce démarrage en
      // « erreur de chargement » — il fallait relancer la lecture pour
      // tomber sur une session déjà chaude.
      manifestLoadingTimeOut: isLive ? 10000 : 45000,
      levelLoadingTimeOut: isLive ? 10000 : 45000,
      manifestLoadingRetryDelay: 500,
      levelLoadingRetryDelay: 500,
      fragLoadingRetryDelay: 500,
      manifestLoadingMaxRetry: 4,
      levelLoadingMaxRetry: 4,
      fragLoadingMaxRetry: 6
    };
  };

  XFPlayer.prototype._startHls = function () {
    var self = this;
    return loadScript(this.vendorPath + 'hls.min.js').then(function () {
      if (!global.Hls || !global.Hls.isSupported()) {
        if (self._canPlayNativeHls()) return self._playDirect(self.url);
        self.onError('HLS non supporté par ce navigateur');
        return;
      }

      var Hls = global.Hls;
      var hls = new Hls(self._hlsConfig());
      self.hls = hls;
      global.hlsInstance = hls; // compat : code existant qui inspecte l'instance

      // Faux tant que la première playlist n'a pas été obtenue : voir le
      // traitement des erreurs réseau plus bas.
      var manifestParsed = false;

      hls.loadSource(self.url);
      hls.attachMedia(self.video);

      hls.on(Hls.Events.MANIFEST_PARSED, function () {
        manifestParsed = true;
        // Démarrage immédiat : on ne sonde plus le buffer toutes les 200 ms.
        // Si le réseau ne suit pas, l'escalade de profil s'en chargera.
        self._attemptPlay();
      });

      hls.on(Hls.Events.LEVEL_LOADED, function (e, d) {
        if (d.details && d.details.totalduration > self._hlsDuration) {
          self._hlsDuration = d.details.totalduration;
          global.currentHlsDuration = self._hlsDuration;
        }
      });

      hls.on(Hls.Events.ERROR, function (e, d) {
        if (!d.fatal) return;
        self.log('Erreur HLS fatale : ' + d.details);
        self._stats.errors++;
        self._report('hls_error', { detail: d.type + '/' + d.details });
        if (d.type === Hls.ErrorTypes.NETWORK_ERROR) {
          // Playlist jamais obtenue (transcodeur en échec → 502, serveur trop
          // chargé → délai dépassé), après les relances internes de hls.js.
          // `startLoad()` ne relance pas ce chargement-là : le lecteur
          // restait muet sur un spinner infini. On remonte l'erreur pour que
          // la page relance un lecteur neuf ou l'affiche.
          if (!manifestParsed) {
            self.onError('Flux indisponible : le serveur n\'a pas pu le préparer');
            return;
          }
          self._escalate('erreur réseau');
          hls.startLoad();
        } else if (d.type === Hls.ErrorTypes.MEDIA_ERROR) {
          self._escalate('erreur média');
          hls.recoverMediaError();
        } else {
          self.onError('Erreur HLS : ' + d.details);
        }
      });
    }).catch(function (err) {
      // hls.js indisponible : plutôt que d'échouer, tenter les chemins qui
      // ne demandent aucune lib (HLS natif Safari/iOS, sinon lecture directe
      // si le navigateur sait décoder le conteneur).
      self.log(err.message);
      if (self._canPlayNativeHls()) { self._playDirect(self.url); return; }
      self.onError(err.message);
    });
  };

  // ---------------- MPEG-TS ----------------

  XFPlayer.prototype._startMpegts = function (isLive) {
    var self = this;
    return loadScript(this.vendorPath + 'mpegts.min.js').then(function () {
      if (!global.mpegts || !global.mpegts.isSupported()) {
        return self._playDirect(self.url);
      }
      self._createMpegts(isLive);
    }).catch(function (err) {
      // mpegts.js indisponible (build incomplet, coupure réseau, quota du
      // rate limiter…) : le même flux reste lisible par la route HLS, où
      // FFmpeg réencode déjà l'audio en AAC. Une seconde de latence en plus
      // vaut mieux qu'un écran d'erreur sur une chaîne parfaitement lisible.
      var hlsUrl = self._hlsEquivalent(self.url);
      self.log(err.message + (hlsUrl ? ' — bascule sur le chemin HLS' : ''));
      if (hlsUrl) {
        self.url = hlsUrl;
        self.onLoading('Ouverture du flux');
        if (self._canPlayNativeHls()) { self._playDirect(hlsUrl); return; }
        return self._startHls();
      }
      // Aucun équivalent HLS (flux direct fourni par la playlist) : dernier
      // recours, laisser le navigateur décoder lui-même le conteneur.
      if (self.video.canPlayType('video/mp2t') !== '') {
        self._playDirect(self.url);
        return;
      }
      self.onError(err.message);
    });
  };

  XFPlayer.prototype._createMpegts = function (isLive) {
    var self = this;
    var mpegts = global.mpegts;

    var player = mpegts.createPlayer(
      { type: 'mpegts', isLive: isLive, url: this.url },
      {
        enableWorker: true,
        enableStashBuffer: true,
        // Le stash initial conditionne directement le délai avant la 1re image.
        // 64 Ko en profil « fast » contre 512 Ko auparavant.
        stashInitialSize: this.profile.mpegtsStash,
        maxStashSize: 30 * 1024 * 1024,
        // POURQUOI ces seuils : les panneaux Xtream relaient le plus souvent
        // une source HLS et livrent le flux par RAFALES (~6 s de contenu d'un
        // coup, puis plusieurs secondes de silence total — mesuré en prod).
        // L'ancien rattrapage (5 s max, 1 s de marge) sautait en avant à
        // chaque rafale puis tombait à sec pendant le silence suivant :
        // coupure toutes les 3-4 s et contenu sauté (12 sauts et 14 coupures
        // en 30 s sur une chaîne FHD). La marge de 12 s couvre deux silences ;
        // le saut ne sert plus qu'à borner un retard réellement accumulé.
        //
        // 25 s et non plus 12 : la télémétrie a mesuré un silence du panneau
        // de ~15-20 s sur une connexion restée ouverte, alors que le lecteur
        // n'avait gardé que 11-16 s — il venait de « consommer » à x1,1
        // l'avance que le panneau envoie au démarrage. On la garde : ~25 s
        // de retard sur le direct, en échange d'une lecture qui traverse ces
        // silences sans figer.
        //
        // Saut seulement au-delà de 90 s : après un silence, le panneau
        // renvoie d'un coup tout le retard. Avec un seuil à 45 s, l'avance
        // le dépassait et le lecteur sautait 20 s de programme (2 fois en
        // 1 min, mesuré). Le régulateur de vitesse (_tuneRate) résorbe
        // désormais cet excédent en douceur.
        liveBufferLatencyChasing: isLive,
        liveBufferLatencyMaxLatency: 90,
        liveBufferLatencyMinRemain: 25,
        // liveSync de mpegts.js désactivé : il ne sait qu'accélérer et remet
        // la vitesse à 1 sous sa cible, ce qui annulerait le ralenti de
        // _tuneRate qui reconstitue la réserve.
        liveSync: false,
        // Purge du buffer déjà lu : sans elle, une longue séance finit par
        // saturer le SourceBuffer (QuotaExceededError → erreur MPEG-TS).
        // Avance jusqu'à 90 s : la vidéo déjà vue est purgée plus tôt pour
        // rester sous le quota du SourceBuffer (~150 Mo en vidéo sur Chrome).
        autoCleanupSourceBuffer: true,
        autoCleanupMaxBackwardDuration: 30,
        autoCleanupMinBackwardDuration: 15,
        lazyLoad: false
      }
    );

    this.mpegts = player;
    this._mpegtsIsLive = isLive;

    // mpegts.js ne démuxe que l'AAC et le MP3. Une chaîne diffusée en E-AC3
    // (stream_type 0x87) ou en AC-3 (0x81) est donc lue sans aucune piste
    // audio, sans erreur ni avertissement : l'image passe, le son est
    // simplement absent. On bascule alors sur le chemin HLS, où FFmpeg
    // réencode systématiquement l'audio en AAC.
    player.on(mpegts.Events.MEDIA_INFO, function (mediaInfo) {
      if (self._destroyed || self._audioFallbackDone) return;
      if (mediaInfo && mediaInfo.hasAudio) return;

      var hlsUrl = self._hlsEquivalent(self.url);
      if (!hlsUrl) return;

      self._audioFallbackDone = true;
      self.log('Aucune piste audio démuxée (codec non supporté) — bascule HLS');
      self._report('fallback_hls', { detail: 'no_audio' });
      self.onLoading('Piste audio incompatible — réencodage');

      try {
        player.unload();
        player.detachMediaElement();
        player.destroy();
      } catch (e) {}
      self.mpegts = null;

      self.url = hlsUrl;
      if (self._canPlayNativeHls()) self._playDirect(hlsUrl);
      else self._startHls();
    });

    player.on(mpegts.Events.ERROR, function (type, detail) {
      self.log('Erreur MPEG-TS : ' + type + ' / ' + detail);
      if (self._destroyed) return;
      self._stats.errors++;
      self._report('mpegts_error', { detail: type + '/' + detail });

      // Chaque recréation relance un FFmpeg côté serveur : sur un serveur
      // déjà saturé, recréer sans fin toutes les 1,2 s ne faisait
      // qu'aggraver la charge. Au-delà de quelques échecs rapprochés, on
      // passe par la route HLS, qui renvoie un vrai code d'erreur.
      var now = Date.now();
      self._mpegtsErrorTimes = self._mpegtsErrorTimes.filter(function (t) {
        return now - t < 60000;
      });
      self._mpegtsErrorTimes.push(now);
      if (self._mpegtsErrorTimes.length > MPEGTS_MAX_ERRORS) {
        try {
          player.unload();
          player.detachMediaElement();
          player.destroy();
        } catch (e) {}
        self.mpegts = null;

        var hlsUrl = self._hlsEquivalent(self.url);
        if (!hlsUrl) {
          self.onError('Flux indisponible');
          return;
        }
        self.log('Erreurs MPEG-TS répétées — bascule HLS');
        self._report('fallback_hls', { detail: 'repeated_mpegts_errors' });
        self.onLoading('Ouverture du flux');
        self.url = hlsUrl;
        if (self._canPlayNativeHls()) self._playDirect(hlsUrl);
        else self._startHls();
        return;
      }

      self._escalate('erreur MPEG-TS');
      // Recréation propre avec le nouveau profil.
      setTimeout(function () {
        if (self._destroyed) return;
        try {
          player.unload();
          player.detachMediaElement();
          player.destroy();
        } catch (e) {}
        self._report('recreate', {});
        self._createMpegts(self._mpegtsIsLive);
      }, 1200);
    });

    player.attachMediaElement(this.video);
    player.load();
    this._attemptPlay();
  };

  /// `/api/live/<id>/turbo.ts` (ou l'ancien `/api/live/<id>.ts`)
  /// → `/api/live/<id>/source/playlist.m3u8`.
  ///
  /// Filet de sécurité : la route turbo réencode déjà l'audio en AAC côté
  /// serveur, donc ce fallback ne devrait plus jamais se déclencher — il
  /// reste pour couvrir un flux sans piste audio exploitable du tout.
  /// Renvoie `null` si l'URL n'est pas un flux live direct — rien à tenter.
  XFPlayer.prototype._hlsEquivalent = function (url) {
    var match = /^(.*\/api\/live\/)([^/?#]+)(?:\/turbo)?\.ts(\?.*)?$/.exec(url);
    if (!match) return null;
    return match[1] + match[2] + '/source/playlist.m3u8';
  };

  // ---------------- Lecture directe ----------------

  XFPlayer.prototype._playDirect = function (url) {
    var self = this;
    this.video.src = url;
    this.video.load();
    this._attemptPlay();
    this.video.addEventListener('error', function () {
      self.onError('Format non supporté');
    }, { once: true });
    return true;
  };

  XFPlayer.prototype._attemptPlay = function () {
    var self = this;
    var p = this.video.play();
    if (p && typeof p.catch === 'function') {
      p.catch(function () {
        // Autoplay refusé (Safari/iOS) : on tente en sourdine, sinon overlay.
        self.video.muted = true;
        var q = self.video.play();
        if (q && typeof q.catch === 'function') {
          q.catch(function () { self.onBlocked(); });
        }
      });
    }
  };

  // ---------------- Escalade adaptative ----------------

  /**
   * Passe au profil supérieur après des coupures répétées.
   * Fenêtre glissante de 60 s : deux stalls rapprochés déclenchent l'escalade,
   * des stalls isolés dans le temps ne pénalisent pas la latence.
   */
  XFPlayer.prototype._escalate = function (reason) {
    if (this.profileLocked || this._destroyed) return;

    var idx = ORDER.indexOf(this.profile.name);
    if (idx >= ORDER.length - 1) return; // déjà au maximum

    var next = PROFILES[ORDER[idx + 1]];
    this.profile = next;
    this.log('Escalade buffer → ' + next.name + ' (' + reason + ')');
    this._report('profile', { detail: reason });
    this.onProfileChange(next.name, reason);

    // HLS : les fenêtres de buffer sont modifiables à chaud, pas besoin de
    // recharger le flux — donc aucune coupure visible pour l'utilisateur.
    if (this.hls) {
      try {
        this.hls.config.maxBufferLength = next.hls.maxBufferLength;
        this.hls.config.maxMaxBufferLength = next.hls.maxMaxBufferLength;
        this.hls.config.liveSyncDurationCount = next.hls.liveSyncDurationCount;
        this.hls.config.liveMaxLatencyDurationCount =
          next.hls.liveMaxLatencyDurationCount;
      } catch (e) {}
    }
    // MPEG-TS : le stash est figé à la création — appliqué à la prochaine
    // recréation du lecteur (déclenchée par le handler d'erreur).
  };

  /**
   * Direct MPEG-TS à sec : se mettre en pause jusqu'à [REBUFFER_SECONDS] de
   * réserve (voir la constante). HLS gère déjà sa propre reprise.
   */
  XFPlayer.prototype._holdUntilBuffered = function () {
    if (this._holding || !this.mpegts || this.type !== 'live') return;
    var self = this;
    this._holding = true;
    this._holdSince = Date.now();
    try { this.video.pause(); } catch (e) {}
    this._holdTimer = setInterval(function () { self._checkHold(); }, 250);
  };

  /**
   * Ajuste la vitesse du direct MPEG-TS selon l'avance (voir LIVE_TUNING).
   * Appelé chaque seconde ; sans effet en pause, en attente de réserve,
   * hors direct ou en HLS.
   */
  XFPlayer.prototype._tuneRate = function () {
    var v = this.video;
    if (!this.mpegts || this.type !== 'live' || !this._started ||
        this._holding || v.paused) {
      return;
    }
    var ahead = this._bufferAhead();
    var t = LIVE_TUNING;
    var mode = this._rateMode || 'normal';
    if (mode === 'slow' && ahead >= t.targetAhead) mode = 'normal';
    else if (mode === 'fast' && ahead <= t.settleHigh) mode = 'normal';
    else if (mode === 'normal' && ahead < t.lowAhead) mode = 'slow';
    else if (mode === 'normal' && ahead > t.highAhead) mode = 'fast';
    // Un saut de rattrapage peut faire passer directement d'un extrême à
    // l'autre.
    if (mode === 'slow' && ahead > t.highAhead) mode = 'fast';
    if (mode === 'fast' && ahead < t.lowAhead) mode = 'slow';
    this._rateMode = mode;

    var rate = mode === 'slow' ? t.slowRate : (mode === 'fast' ? t.fastRate : 1);
    if (v.playbackRate !== rate) {
      try { v.playbackRate = rate; } catch (e) {}
    }
  };

  /** Relance la lecture dès que la réserve est reconstituée. */
  XFPlayer.prototype._checkHold = function () {
    if (!this._holding) return;
    if (this._destroyed) { clearInterval(this._holdTimer); return; }
    var waited = Date.now() - this._holdSince;
    if (this._bufferAhead() < REBUFFER_SECONDS && waited < REBUFFER_MAX_WAIT_MS) {
      return;
    }
    clearInterval(this._holdTimer);
    this._holding = false;
    this._attemptPlay();
  };

  XFPlayer.prototype._noteStall = function () {
    if (!this._started) return; // les attentes d'amorçage ne comptent pas
    var now = Date.now();
    this._stallTimes.push(now);
    this._stallTimes = this._stallTimes.filter(function (t) {
      return now - t < 60000;
    });
    if (this._stallTimes.length >= 2) {
      this._stallTimes = [];
      this._escalate('coupures répétées');
    }
  };

  // ---------------- Événements vidéo & pont Flutter ----------------

  XFPlayer.prototype._wireVideoEvents = function () {
    var self = this;
    var v = this.video;

    this._on(v, 'loadedmetadata', function () {
      if (self.startTime > 0 && self.startTime < v.duration) {
        v.currentTime = self.startTime;
      }
    });

    this._on(v, 'playing', function () {
      if (!self._started) {
        self._report('first_frame', { ms: Date.now() - self._t0 });
      }
      if (self._stallSince !== null) {
        var stallMs = Date.now() - self._stallSince;
        self._stallSince = null;
        // < 250 ms : imperceptible, ne pas noyer les logs.
        if (stallMs >= 250) {
          self._stats.stalls++;
          self._stats.stallMs += stallMs;
          self._report('stall', { ms: stallMs });
        }
      }
      self._started = true;
      self.onReady();
      self.send({ type: 'playback_status', status: 'playing' });
    });

    this._on(v, 'pause', function () {
      // Pause posée par l'attente de réserve : pas une pause utilisateur,
      // l'interface ne doit pas basculer sur « lecture ».
      if (self._holding) return;
      self.send({ type: 'playback_status', status: 'paused' });
    });

    this._on(v, 'waiting', function () {
      if (self._started && self._stallSince === null) {
        self._stallSince = Date.now();
      }
      self._noteStall();
      if (self._started) self._holdUntilBuffered();
    });
    this._on(v, 'stalled', function () { self._noteStall(); });

    // Sauts (rattrapage du direct, recherche) : d'où, vers où.
    this._on(v, 'timeupdate', function () {
      if (!v.seeking) self._lastPos = v.currentTime;
    });
    this._on(v, 'seeking', function () {
      if (!self._started) return;
      self._stats.seeks++;
      self._report('seek', { from: self._lastPos, to: v.currentTime });
    });

    // Régulateur de vitesse du direct (voir LIVE_TUNING).
    this._rateTimer = setInterval(function () { self._tuneRate(); }, 1000);

    // Bilan toutes les 60 s : nombre et durée cumulée des coupures.
    this._beatTimer = setInterval(function () {
      if (!self._started) return;
      self._report('heartbeat', {
        stalls: self._stats.stalls,
        stallMs: self._stats.stallMs,
        seeks: self._stats.seeks,
        errors: self._stats.errors,
        rate: v.playbackRate
      });
    }, 60000);

    this._on(v, 'ended', function () {
      self.send({
        type: 'playback_ended',
        duration: self._totalDuration()
      });
    });

    // Le front de transcodage avance : le parent doit pouvoir griser la
    // portion pas encore navigable de la barre de progression. `progress`
    // se déclenche à chaque bloc reçu — bridé à 2 s, sinon chaque segment
    // provoquerait une reconstruction de l'interface Flutter.
    this._on(v, 'progress', function () {
      if (!self._started) return;
      var now = Date.now();
      if (now - (self._lastProgressSent || 0) < 2000) return;
      self._lastProgressSent = now;
      self._sendPosition();
    });

    this._on(v, 'seeked', function () { self._sendPosition(); });

    // Remontée de position (5 s) — même contrat qu'avant.
    this._posTimer = setInterval(function () { self._reportPosition(); }, 5000);

    // Activité utilisateur → masquage auto des contrôles côté Flutter.
    function activity() { self.send({ type: 'user_activity' }); }
    this._on(document, 'mousemove', activity, { passive: true });
    this._on(document, 'touchstart', activity, { passive: true });
    this._on(document, 'click', activity, { passive: true });
  };

  /** Fin de la plage réellement navigable, en temps média. */
  XFPlayer.prototype._seekableEnd = function () {
    var v = this.video;
    try {
      if (v.seekable && v.seekable.length > 0) {
        return v.seekable.end(v.seekable.length - 1);
      }
    } catch (e) {}
    try {
      if (v.buffered && v.buffered.length > 0) {
        return v.buffered.end(v.buffered.length - 1);
      }
    } catch (e) {}
    return isFinite(v.duration) ? v.duration : 0;
  };

  /** Durée totale du contenu (et non du seul média chargé), en secondes. */
  XFPlayer.prototype._totalDuration = function () {
    var v = this.video;
    var duration = v.duration;
    var hlsDur = this._hlsDuration || 0;
    if (!isFinite(duration) || isNaN(duration) || duration < 1) {
      duration = hlsDur;
    } else if (hlsDur > duration) {
      duration = hlsDur;
    }

    // Temps absolu : le média peut commencer après le début du contenu.
    var total = duration > 0 ? this.mediaOffset + duration : 0;

    // La durée annoncée par l'app fait foi tant que le média n'en connaît
    // qu'une fraction — cas d'une playlist `event` encore en cours de
    // transcodage, où la durée grandirait sous la barre de progression.
    // Au-delà, le média a raison : les métadonnées Xtream sont approximatives.
    if (this.injectedDuration > 0 && total < this.injectedDuration * 0.98) {
      return this.injectedDuration;
    }
    return total;
  };

  XFPlayer.prototype._reportPosition = function () {
    var v = this.video;
    if (!(v.currentTime > 0) || v.paused || v.readyState <= 2) return;
    if (Math.abs(v.currentTime - this._reportedTime) < 1) return;
    this._reportedTime = v.currentTime;
    this._sendPosition();
  };

  /** Envoi immédiat de l'état de lecture (position, durée, zone navigable). */
  XFPlayer.prototype._sendPosition = function () {
    this.send({
      type: 'playback_position',
      currentTime: this.mediaOffset + this.video.currentTime,
      duration: this._totalDuration(),
      seekableEnd: this.mediaOffset + this._seekableEnd()
    });
  };

  /**
   * Recherche à un instant ABSOLU du contenu.
   *
   * Tant que la cible est dans la zone déjà transcodée, c'est une simple
   * affectation de `currentTime`. Au-delà, aucune quantité d'attente ne la
   * rendra disponible rapidement : le parent est prévenu pour relancer le
   * flux à cet instant (nouvelle session FFmpeg `?start=`).
   */
  XFPlayer.prototype.seekTo = function (absolute) {
    if (!isFinite(absolute)) return;
    var v = this.video;
    var target = absolute - this.mediaOffset;
    var end = this._seekableEnd();

    if (target < 0) {
      // Avant le début du média chargé : cette portion n'est pas dans cette
      // session de transcodage, il faut en relancer une plus tôt.
      this.send({ type: 'seek_out_of_range', value: Math.max(0, absolute) });
      return;
    }

    // Marge de 10 s : juste devant le front de transcodage, attendre coûte
    // moins cher que relancer un encodeur.
    if (end > 0 && target > end + 10) {
      this.send({ type: 'seek_out_of_range', value: absolute });
      return;
    }

    try {
      v.currentTime = end > 0 ? Math.min(target, Math.max(0, end - 0.5)) : target;
    } catch (e) {
      this.send({ type: 'seek_out_of_range', value: absolute });
      return;
    }
    this._reportedTime = v.currentTime;
    this._sendPosition();
  };

  XFPlayer.prototype._wireParentMessages = function () {
    var self = this;
    this._on(global, 'message', function (event) {
      // N'accepter que les commandes émises par notre propre origine
      // (le côté Flutter filtre déjà les messages entrants de la même façon).
      if (event.origin !== global.location.origin) return;
      var d = event.data;
      if (!d || !d.type) return;
      var v = self.video;
      switch (d.type) {
        case 'play':
          self._attemptPlay();
          break;
        case 'pause':
          // Pause voulue par l'utilisateur : l'attente de réserve ne doit
          // pas relancer la lecture derrière son dos.
          if (self._holding) {
            clearInterval(self._holdTimer);
            self._holding = false;
          }
          v.pause();
          break;
        case 'seek':
          self.seekTo(d.value);
          break;
        case 'set_rate':
          if (isFinite(d.value) && d.value > 0) {
            try { v.playbackRate = Math.max(0.25, Math.min(4, d.value)); } catch (e) {}
          }
          break;
        case 'set_volume':
          v.volume = Math.max(0, Math.min(1, d.value));
          v.muted = v.volume === 0;
          break;
        case 'unmute':
          v.muted = false;
          if (v.volume === 0) v.volume = 1;
          break;
      }
    });
  };

  XFPlayer.prototype.destroy = function () {
    this._destroyed = true;
    clearInterval(this._posTimer);
    clearInterval(this._beatTimer);
    clearInterval(this._holdTimer);
    clearInterval(this._rateTimer);
    this._listeners.forEach(function (l) {
      try { l.target.removeEventListener(l.type, l.handler); } catch (e) {}
    });
    this._listeners = [];
    try { if (this.hls) this.hls.destroy(); } catch (e) {}
    try {
      if (this.mpegts) {
        this.mpegts.unload();
        this.mpegts.detachMediaElement();
        this.mpegts.destroy();
      }
    } catch (e) {}
  };

  global.XFPlayer = XFPlayer;
  global.XFPlayerProfiles = PROFILES;
  global.XFPlayerLiveTuning = LIVE_TUNING;
})(window);
