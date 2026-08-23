# Journal des changements affectant le benchmark

Une ligne par changement constaté ou apporté qui affecte la
comparabilité d'un trimestre à l'autre : évolution du prompt de prod,
changement de config par défaut (modèle, température, tokens), mise à
jour du protocole ou du jeu de données lui-même, changement d'appareil
de test pour Nano, etc.

| Date | Changement | Impact attendu sur la comparabilité |
|---|---|---|
| 2026-08-22 | Création initiale du protocole et du jeu de données | — (référence de départ) |
| 2026-08-22 | Run #1 (baseline) : échec sur les 2 cas — texte vide renvoyé par `gemini-3.5-flash`, cause probable : le budget de réflexion ("thinking") consomme tout `maxOutputTokens` (1024) avant que le JSON attendu ne soit généré. Bug de fiabilité applicatif réel identifié en parallèle : la boucle de repli entre modèles ne se déclenche pas sur ce cas (200 OK avec texte vide traité comme succès définitif) — voir issue #158. | Aucune évaluation de qualité possible sur ce run — à refaire une fois #158 corrigé, ou en attendant via un run `prompt_variant_id` distinct forçant `--model gemini-1.5-flash` (pas de réflexion, contourne le problème) pour au moins juger la qualité du texte généré. |
