# XtremFlow — charte « Salle obscure » (web)

Même charte que l'application sœur xtremobile (v1.9.9) : un salon le soir, lumières éteintes,
l'écran est la seule source de lumière. L'interface reste discrète, ce sont les logos et les
affiches qui portent la couleur. Une seule chose est allumée à la fois : l'élément focalisé.

Fichiers de référence :

| Fichier | Rôle |
|---|---|
| `lib/core/theme/app_colors.dart` | jetons de couleur |
| `lib/core/theme/app_theme.dart` | police, tailles, rayons, mouvement, thème Material |
| `lib/core/theme/glass.dart` | `GlassDecoration` (verre sans flou), `AmbientBackground` |
| `lib/core/theme/app_decorations.dart` | `tvCard`, `logoTile` |
| `lib/core/widgets/tv_focusable.dart` | focus unique souris / clavier |
| `lib/core/widgets/app_dialog.dart` | fenêtres et feuilles au thème |
| `lib/core/widgets/side_rail.dart` | barre latérale du tableau de bord |
| `lib/features/iptv/widgets/live_widgets.dart` | cartes, lignes et panneau du Direct |
| `lib/features/iptv/widgets/player_osd.dart` | plaques du lecteur |

## Couleurs

Rampe graphite neutre, du plus sombre au plus clair :

| Jeton | Valeur | Usage |
|---|---|---|
| `rail` | #090A0D | barre latérale, champs dans une fenêtre |
| `background` | #101216 | fond de page |
| `surface` | #18181A | cartes, panneaux, barre du téléphone |
| `surfaceHigh` | #232326 | élément surélevé, bouton au repos |
| `track` | #2E2E31 | piste de progression |
| `hairline` | texte à 8 % | séparateurs, liseré de la barre latérale |

Texte : `textPrimary` #EDEDED, `textSecondary` #BDBDC2, `textMuted` #A8A8AE.

Un seul accent, le bleu du logo : `accent` #8FCFFF (onglet courant, étoiles, bouton principal),
`accentOnLight` sur une carte allumée, `accentFill` (bleu à 15 %) derrière l'onglet courant.

Rouge `live` #F0533F : **uniquement** la progression du programme en cours (« ligne rouge ») et le
point d'enregistrement en cours. Rien d'autre n'est rouge, hors erreurs (`error`).

Élément focalisé : carte claire `focusTop` #F4F4F2, encre sombre `onFocus` / `onFocusMuted`.

Les anciens noms (`primary`, `surfaceContainer*`, `secondaryFixed*`…) existent encore en alias sur
cette rampe ; le nouveau code utilise les jetons ci-dessus.

## Typographie

Figtree seule, en 400 / 500 / 600, fichiers statiques dans `assets/fonts/` (licence OFL) déclarés
dans `pubspec.yaml`. Aucune requête vers Google Fonts.

- `AppTheme.display(...)` titres, `AppTheme.body(...)` texte d'interface, `AppTheme.eyebrow(...)`
  petit libellé discret.
- `AppTheme.font(...)` remplace les anciens `GoogleFonts.xxx(...)` : mêmes paramètres, impose
  Figtree, ramène toute graisse > 600 à 600 et tout interlettrage négatif à 0.
- Chiffres tabulaires (`AppTheme.tabular`) pour les heures, numéros et compteurs.
- Hiérarchie par la taille et la couleur, pas par la graisse. Pas de majuscules espacées : les
  libellés sont en français, en minuscules de phrase.

Le moteur Flutter garde son repli vers Noto (fonts.gstatic.com) pour les glyphes absents de Figtree
(emoji, écritures non latines dans des noms de chaînes) : l'interface elle-même n'en dépend pas.

## Verre et profondeur

- **Pas de flou** (`BackdropFilter`) ni d'ombre portée : le flou se recalcule à chaque image.
  `GlassDecoration` peint un remplissage translucide et un liseré clair ; `lit: 1` en fait la carte
  claire focalisée.
- Fond des écrans (tableau de bord, connexion, choix de playlist, administration) :
  `AmbientBackground`, lueurs bleues précalculées une fois dans une image. Le lecteur reste noir.
- `GlassContainer` garde son ancienne API et peint `GlassDecoration` (ses options de bordure et
  d'ombre sont ignorées).

## Focus : souris et clavier

`TVFocusable` porte le focus de toute l'application :

- survoler un élément lui donne le focus : une seule carte allumée, qu'on vienne de la souris ou du
  clavier ;
- le survol ne prend jamais le focus à un champ de saisie ;
- un focus venu du survol ne fait pas défiler la liste (seul le clavier la fait défiler) ;
- `paintsOwnFocus: true` : l'enfant lit `TVFocusable.isFocused(context)` et devient la carte claire.

## Barre latérale

`SideRail`, posée au-dessus du contenu (décalé de 88 px fixes) :

- repliée à 88 px (icônes), dépliée à 240 px (icônes + libellés) au survol, ou quand le focus clavier
  y entre ; libellés masqués sous 160 px ;
- de haut en bas : logo, Rechercher, Direct, Films, Séries, Enregistrements, puis IPTV active,
  Réglages, Compte (Administration, Se déconnecter) ;
- élément de 48 px, rayon 12 ; onglet courant sur `accentFill` en `accent` ; élément focalisé en
  verre allumé ;
- flèche droite : retour au contenu. « Rechercher » donne le focus au champ de recherche de l'onglet
  (Direct, Films ou Séries).

## Direct

- Vue groupes : « Favoris » (grille de 3 : « Chaînes favorites » puis les groupes épinglés),
  « Tous les groupes » (grille de cartes de 300 px max). L'étoile d'une carte épingle le groupe
  (clic, ou appui long sur Entrée).
- Vue chaînes : liste numérotée (logo, nom complet, programme, horaires, ligne rouge) et panneau à
  droite (`min(40 %, 560 px)`) : aperçu vidéo, nom complet, programme, temps restant, progression,
  « À suivre », boutons Plein écran / Favori / Enregistrer. Échap ramène aux groupes.

### Aperçu vidéo muet

- Une seule iframe `player_lite.html?…&preview=1` dont l'adresse suit `livePreviewProvider`
  (`live_preview_controller.dart`, testé sur la VM).
- Chargée 350 ms après l'arrivée sur une chaîne ; abandonnée après 10 s sans image ; après un
  échec, plus d'aperçu pendant 60 s (logo et programme seulement).
- Arrêtée en quittant la liste ou le Direct, quand l'onglet du navigateur est caché, après 3 min
  sans souris ni clavier, et avant le plein écran.
- En `preview=1`, `xf-player-core.js` lit en muet, sans interface, sans aucune reprise ni journal,
  et envoie `preview_state` (`playing` / `error`) au parent.
- Côté serveur, `turbo.ts?preview=1` inscrit sa connexion amont comme toujours cédable
  (`preview_<id>_<n>`) : l'ouverture suivante du même compte (autre aperçu, plein écran,
  enregistrement via le proxy local) la coupe aussitôt.
- Réglage « Aperçu vidéo dans le Direct » (Réglages → Lecture), activé par défaut.

## Lecteur

Rien en haut de l'image. En bas, une plaque à 88 % d'opacité :

- direct : logo, nom, programme, progression, « À suivre » ; boutons Chaînes, Son, Qualité,
  Plein écran. La liste des chaînes s'ouvre à droite (bouton « Chaînes » ou touche C) : ↑/↓
  parcourent la liste, Entrée zappe, Échap ferme la liste ;
- films, séries, enregistrements : titre, barre de lecture (plage déjà disponible), −10 s / +10 s
  (60 s avec Maj), vitesse, son, plein écran.

Les raccourcis clavier existants sont inchangés.

## Fenêtres

`showAppDialog` + `AppDialog` / `AppDialogButton` / `AppDialogTile`, `showAppConfirm`,
`showAppTextInput`, `showAppSheet` : carte graphite au liseré bleu, bouton focalisé allumé.

## Téléphone

Largeur < 768 px : écrans `lib/mobile/`, barre de navigation en bas (`NavigationBar`, fond
`surface`, indicateur `accentFill`), mêmes jetons et même police.

## Mouvement

Une seule courbe, `AppTheme.curveFocus` = `Cubic(0.22, 1, 0.36, 1)`. Focus en 150 ms
(`durationFocus`), transitions en 220 ms (`durationNormal`), 300 / 400 ms pour les grands
déplacements.
