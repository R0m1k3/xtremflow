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
    this._destroyed = false;
    this._reportedTime = 0;
    this._hlsDuration = 0;

    // Écouteurs posés par cette instance, retirés à la destruction : sans
    // ça, une relance après échec laisserait l'ancienne instance réagir aux
    // commandes du parent et republier des positions périmées.
    this._listeners = [];
  }

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

      hls.loadSource(self.url);
      hls.attachMedia(self.video);

      hls.on(Hls.Events.MANIFEST_PARSED, function () {
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
        if (d.type === Hls.ErrorTypes.NETWORK_ERROR) {
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
        // Rattrapage du direct : sans lui, chaque micro-coupure fait dériver
        // la lecture derrière le direct (latence qui s'accumule). Activé
        // uniquement en profil « fast » — les profils élargis privilégient
        // la stabilité du buffer.
        liveBufferLatencyChasing: isLive && this.profile.name === 'fast',
        liveBufferLatencyMaxLatency: 5,
        liveBufferLatencyMinRemain: 1,
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
      self._escalate('erreur MPEG-TS');
      // Recréation propre avec le nouveau profil.
      setTimeout(function () {
        if (self._destroyed) return;
        try {
          player.unload();
          player.detachMediaElement();
          player.destroy();
        } catch (e) {}
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
      self._started = true;
      self.onReady();
      self.send({ type: 'playback_status', status: 'playing' });
    });

    this._on(v, 'pause', function () {
      self.send({ type: 'playback_status', status: 'paused' });
    });

    this._on(v, 'waiting', function () { self._noteStall(); });
    this._on(v, 'stalled', function () { self._noteStall(); });

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
})(window);
