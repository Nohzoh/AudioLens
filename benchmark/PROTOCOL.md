# Protocole de benchmark : Gemini API (cloud) vs Gemini Nano (on-device)

## Objectif

Suivre, trimestre après trimestre, comment évoluent les deux moteurs de
génération de script audio-guide utilisés par AudioLens :

- **Gemini API** (`lib/services/gemini_api_service.dart`) — cloud
- **Gemini Nano** (`lib/services/gemini_nano_service.dart` +
  `android/app/src/main/kotlin/io/nohzoh/audiolens/GeminiNanoPlugin.kt`) —
  on-device, via ML Kit GenAI

Ce document est la référence stable : le jeu de données et la grille de
notation ne doivent **pas** changer d'un trimestre à l'autre (sauf
décision explicite, documentée dans `results/CHANGES.md`), sinon les
comparaisons dans le temps perdent leur sens.

Ce même protocole sert aussi de plus petite échelle : tester un
changement de prompt ou de configuration (température, contexte fourni,
etc.) sur le jeu de données fixe, sans que ce soit un run trimestriel
"officiel" (voir [Runs ad hoc](#runs-ad-hoc--tests-de-prompt)).

## ⚠️ Point important : ce n'est pas juste "même prompt, deux modèles"

Les deux moteurs suivent des pipelines différents en production — le
benchmark compare le résultat final réel (ce que l'utilisateur entend),
pas une exécution symétrique du même prompt :

| | Gemini API (cloud) | Gemini Nano (on-device) |
|---|---|---|
| Appels | 1 seul appel | 3 appels séquentiels (description → contexte historique → conclusion) |
| Sortie | JSON structuré `{title, script}` | Texte brut concaténé, titre = 1ère phrase |
| Longueur cible | 300-400 mots (100-150 en mode "concise") | ~3 segments de 1-3 phrases chacun (nettement plus court) |
| Budget de tokens | `maxOutputTokens` configurable (1024 par défaut) | 256 tokens par segment |
| Contexte de lieu | Injecté en un bloc texte libre dans le prompt | Injecté uniquement dans le 1er segment, sous forme `(prise à : ...)` |

Si un jour ces deux pipelines convergent (ou divergent davantage), c'est
en soi un résultat à noter dans le suivi trimestriel.

## Jeu de données fixe

Situé dans `benchmark/dataset/`. Structure :

```
benchmark/dataset/
  manifest.json       # liste des cas de test
  photos/              # les photos elles-mêmes (référencées par manifest.json)
```

Chaque entrée de `manifest.json` doit rester **strictement identique**
d'un trimestre à l'autre (même photo, mêmes coordonnées, même
`location_context` gelé — voir ci-dessous) : seule l'entrée du run
change (date, moteur, modèle, résultats).

### Pourquoi le `location_context` est gelé, pas recalculé en direct

En production, `LocationContextResolver` va chercher un POI proche et
des extraits Wikipedia en temps réel
(`lib/services/location_context_resolver.dart`). Si le benchmark
refaisait cet appel à chaque run, le contenu injecté dans le prompt
changerait avec le temps (une page Wikipedia éditée, un POI qui
disparaît) — un facteur de variation qui n'a rien à voir avec les
modèles eux-mêmes. Le manifeste fige donc directement le texte
`location_context` tel qu'il aurait été résolu au moment de la création
du jeu de données, pour isoler la variable qu'on veut vraiment observer :
le modèle.

### Catégories à couvrir (recommandé, à ajuster selon les photos disponibles)

Pour que le jeu de données soit représentatif des conditions réelles
d'usage, viser une couverture des cas suivants (voir les tickets #151 et
#152 pour deux d'entre eux, déjà identifiés comme sources de variation) :

1. Monument célèbre, très documenté (test de reconnaissance + richesse factuelle)
2. Lieu local peu connu, sans article Wikipedia (test du comportement "je ne reconnais pas")
3. Élément architectural moderne / non touristique
4. Site naturel (parc, paysage) sans bâtiment identifiable
5. Photo prise en intérieur (musée, œuvre d'art)
6. Photo de galerie sans GPS EXIF (chemin `map_picker_screen.dart`, cf. #123)
7. Photo au format paysage (test du recadrage `BoxFit.cover`, cf. #151)
8. Photo avec une orientation EXIF non standard (cf. #152)
9. Photo où le sujet n'est pas clairement identifiable (cas ambigu)
10. Un même lieu testé dans les 4 styles (`immersive`, `academic`, `anecdotal`, `concise`) pour vérifier le respect de la consigne de ton

Un jeu de 12 à 15 cas couvrant cette liste suffit largement — la
richesse de l'analyse vient de la répétition trimestrielle, pas du
volume.

### Format d'une entrée `manifest.json`

Voir le fichier lui-même pour le schéma et un exemple commenté.

## Exécution — côté cloud (automatisable)

`benchmark/scripts/run_cloud_benchmark.py` reproduit **exactement** le
prompt et la structure de requête de `gemini_api_service.dart` (même
gabarit de prompt, même `generationConfig`, même logique de fallback de
modèle). Il tourne :

- **En local** : `python3 benchmark/scripts/run_cloud_benchmark.py --api-key <clé>`
- **Via GitHub Actions** : workflow `benchmark.yml`, déclenché
  manuellement (`workflow_dispatch`) depuis l'onglet Actions du dépôt.
  Nécessite un secret de dépôt `GEMINI_API_KEY` (Settings → Secrets and
  variables → Actions) — à configurer une seule fois.

Le script écrit un fichier `results/cloud_<date>.json` (et un résumé
lisible dans `$GITHUB_STEP_SUMMARY` quand il tourne en CI) avec, pour
chaque cas de test : modèle réellement utilisé (après fallback
éventuel), latence, titre, script, nombre de mots, et tout échec brut.

## Exécution — côté Nano (manuelle, obligatoirement sur appareil)

Gemini Nano ne peut pas être appelé depuis ce script ni depuis la CI —
c'est une inférence on-device via ML Kit GenAI/AICore, qui exige un
appareil Android réel (ou un émulateur compatible) avec le modèle
téléchargé, l'app au premier plan (cf. le commentaire sur
`GeminiNanoBackgroundRestrictedException`).

Procédure (depuis #477, via le Nano Prompt Lab) :

1. Transférer les photos de `benchmark/dataset/photos/` sur l'appareil.
2. Ouvrir Réglages → Outils → Nano Prompt Lab, mode « pipeline
   complet ». Choisir la variante de modèle à mesurer.
3. Pour chaque cas : choisir la photo, saisir les coordonnées du
   manifeste et l'identifiant du cas (`id` de `manifest.json`), lancer.
   Faire deux runs par cas et par variante : le premier après
   changement de variante est « à froid » (`prior_runs_for_variant` à
   0), les suivants « à chaud ».
4. « Exporter les runs » produit un fichier JSON au format de
   `results/nano_template.json` : l'enregistrer sous
   `results/nano_<date>.json`.

L'export contient, sans saisie manuelle : le modèle et la version
d'Android, la version d'AICore, la version et le commit de l'app, la
version de ML Kit GenAI, la variante demandée et le nom du modèle
réellement chargé, la latence totale et par segment, et le contexte de
localisation résolu sur l'appareil.

Le nom du modèle et la version d'AICore sont des facteurs de confusion
à part entière : le modèle Nano peut se mettre à jour silencieusement
via les services Google Play, sans mise à jour de l'app.

**Mémoire** : le modèle tourne dans le processus d'AICore, que l'app ne
peut pas inspecter. L'export donne donc la mémoire système disponible
avant le run et son minimum pendant le run ; leur différence
(`peak_memory_drop_mb`) est une approximation du coût mémoire de
l'inférence, sensible à ce que le reste du système fait au même moment.
À comparer entre variantes sur le même appareil, pas en valeur absolue.

## Grille de notation

Appliquée à chaque résultat (cloud et Nano), consignée dans
`tracker/audiolens_benchmark_tracker.xlsx` :

| Critère | Type | Échelle |
|---|---|---|
| Sujet reconnu correctement | Automatique/manuel | Oui / Non / Partiel |
| Exactitude factuelle | Manuel (vérifier contre une source fiable) | 1-5 |
| Qualité narrative / engageant | Manuel | 1-5 |
| Respect de la consigne (longueur, JSON, pas de méta-commentaire) | Automatique | 1-5 |
| Respect du ton demandé (style) | Manuel | 1-5 |
| Latence | Automatique (cloud) / chronométré à la main (Nano) | ms |
| Échec / erreur | Automatique | Oui / Non + message |

Le nombre de mots et la latence sont calculés automatiquement par le
script côté cloud ; à saisir à la main côté Nano.

## Runs ad hoc — tests de prompt

Pour tester une variante de prompt ou de configuration (sans que ce soit
le run trimestriel de référence) :

1. Dupliquer `run_cloud_benchmark.py` en changeant uniquement ce qui est
   testé (ou passer un prompt alternatif via `--prompt-override`, voir
   `--help`).
2. Lancer sur le même jeu de données fixe.
3. Consigner le résultat dans le tracker avec un `prompt_variant_id`
   distinct (colonne dédiée) — ces lignes sont exclues des moyennes
   "officielles" par trimestre (filtrées par la colonne
   `is_quarterly_baseline`), mais permettent de comparer une variante à
   la référence du trimestre en cours.

## Question ouverte : impact du contexte de localisation

Hypothèse de départ (à confirmer/infirmer empiriquement, pas à prendre
pour acquis) : l'apport du GPS/`location_context` devrait varier
fortement selon que le sujet est déjà reconnaissable par la seule image
(un monument mondialement connu) ou non (un lieu local, peu documenté).
Sans localisation, le modèle risque de rester générique dans le second
cas, mais de s'en sortir presque aussi bien dans le premier.

Pour tester ça sur le jeu de données fixe, sans créer une seconde
"version" du dataset : lancer le script cloud avec
`--strip-location-context` (ou cocher l'option équivalente dans le
workflow GitHub Actions), qui envoie exactement le même prompt que le
run normal mais sans le bloc de contexte — chaque case garde son
`location_context` dans `manifest.json` (pour le run de référence), il
est juste ignoré pour ce run-là. Donner à ce run un
`prompt_variant_id` du type `no_location_context` et
`is_quarterly_baseline = non` dans le tracker, pour comparer côte à côte
avec le run `baseline` du même trimestre sans polluer la moyenne
officielle.

## Cadence

Un run "officiel" par trimestre (viser le même mois calendaire à chaque
fois, par exemple mi-janvier / mi-avril / mi-juillet / mi-octobre, pour
limiter les effets de saisonnalité de disponibilité des modèles). Chaque
run officiel :

1. Tourne le script cloud (local ou Action).
2. Fait le run Nano manuel sur le même jeu de données.
3. Remplit la grille de notation dans le tracker.
4. Ajoute une ligne dans `results/CHANGES.md` si quoi que ce soit a
   changé dans le protocole, le prompt de prod, ou la config par défaut
   depuis le dernier run (ces changements sont le signal le plus
   important à ne pas perdre).
