# Benchmark : Gemini API vs Gemini Nano

Suivi trimestriel comparant le moteur cloud et le moteur on-device
utilisés par AudioLens pour générer les scripts audio-guide, sur un jeu
de données fixe.

- **Méthodologie complète** : [`PROTOCOL.md`](./PROTOCOL.md) — à lire en
  premier.
- **Jeu de données** : [`dataset/manifest.json`](./dataset/manifest.json)
  + photos dans `dataset/photos/`.
- **Script d'exécution (cloud)** :
  [`scripts/run_cloud_benchmark.py`](./scripts/run_cloud_benchmark.py).
- **Résultats bruts par run** : `results/`.
- **Tableau de suivi / notation** :
  [`tracker/audiolens_benchmark_tracker.xlsx`](./tracker/audiolens_benchmark_tracker.xlsx).

## Lancer un run cloud

**Localement :**

```bash
python3 benchmark/scripts/run_cloud_benchmark.py --api-key "$GEMINI_API_KEY"
```

**Via GitHub Actions** : onglet *Actions* → workflow *Gemini Benchmark*
→ *Run workflow*. Nécessite le secret de dépôt `GEMINI_API_KEY`
(Settings → Secrets and variables → Actions), à configurer une seule
fois.

Le run Nano (on-device) reste manuel — voir la section dédiée dans
`PROTOCOL.md`.

<!-- verification commit: confirms benchmark-only changes skip Build/Test CI -->
