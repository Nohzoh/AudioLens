#!/usr/bin/env python3
"""Runs the fixed benchmark dataset against the Gemini API, reproducing
*exactly* the prompt and request shape used in production by
lib/services/gemini_api_service.dart (T-benchmark).

This intentionally duplicates that Dart file's prompt string rather than
importing/parsing it, so a change to the real prompt is a visible diff
in both places (see PROTOCOL.md's note on results/CHANGES.md) instead of
silently drifting apart unnoticed.

Usage:
    python3 run_cloud_benchmark.py --api-key YOUR_KEY
    python3 run_cloud_benchmark.py --api-key YOUR_KEY --model gemini-3.5-flash
    python3 run_cloud_benchmark.py --api-key YOUR_KEY --prompt-override "..."

Network: calls generativelanguage.googleapis.com directly. Not runnable
from a sandboxed environment without egress to that host.
"""
import argparse
import base64
import json
import sys
import time
import urllib.request
import urllib.error
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DATASET_DIR = REPO_ROOT / "benchmark" / "dataset"
RESULTS_DIR = REPO_ROOT / "benchmark" / "results"

# Mirrors RemoteConfigService's defaults (lib/services/remote_config_service.dart)
# as of 2026-08-22. If production remote config has since diverged, pass
# --model / --max-tokens / --temperature / --thinking-budget to match the
# actual values in effect at benchmark time, and note the drift in
# results/CHANGES.md — remote config values are themselves a variable
# worth tracking across quarters.
DEFAULT_MODEL = "gemini-3.5-flash"
DEFAULT_MODEL_FALLBACKS = ["gemini-2.5-flash-preview-05-20", "gemini-1.5-flash"]
DEFAULT_API_URL = "https://generativelanguage.googleapis.com/v1"
DEFAULT_MAX_TOKENS = 1024
DEFAULT_TEMPERATURE = 0.7
DEFAULT_THINKING_BUDGET = 512


def build_prompt(location_context: str | None, style: str | None, override: str | None) -> str:
    """Exact reproduction of GeminiApiService.analyzeImage's prompt
    construction (gemini_api_service.dart lines ~57-78)."""
    if override:
        return override

    context_part = (
        f"\n\nContexte et informations factuelles disponibles :\n{location_context}"
        if location_context
        else ""
    )
    word_count = "Entre 100 et 150 mots" if style == "concise" else "Entre 300 et 400 mots"

    return (
        "Tu es un guide audio de musee, passionne et erudit. "
        "Redige deux choses en JSON valide uniquement, sans markdown : "
        '{"title": "titre court et evocateur (5-8 mots max)", "script": "le texte du guide"} '
        "Le titre doit nommer precisement l'oeuvre ou le lieu si reconnu, sinon evoquer ce qu'on voit. "
        f"{style_guidance(style)} "
        "Si tu reconnais l'oeuvre, nomme-la avec des faits reels. "
        "Si le contexte fourni mentionne un lieu identifie, une adresse ou une enseigne, "
        "utilise-le en priorite pour identifier precisement l'endroit reel plutot que de "
        "rester generique, et cherche les faits marquants qui s'y rattachent (tournages, "
        "evenements historiques, personnalites) plutot que de decrire seulement ce qui est visible. "
        f"{context_part} "
        f"{word_count} pour le script, sans mise en forme ni asterisque. "
        "Ne montre jamais ton raisonnement interne. "
        "Ne commente pas le nombre de mots. "
        "Ecris uniquement le JSON final, rien d'autre."
    )


def style_guidance(style: str | None) -> str:
    """Exact reproduction of GeminiApiService._styleGuidance."""
    if style == "academic":
        return (
            "Le script : documentaire et rigoureux, tu t'adresses au visiteur avec \"vous\". "
            "Privilegie les faits verifies, dates precises et contexte historique "
            "detaille plutot que l'emotion. Commence par le fait le plus "
            "significatif ou la date cle, sans effet de style superflu. "
            "Construis : mise en contexte factuelle, developpement historique, "
            "details techniques ou artistiques, conclusion sur l'importance "
            "du lieu ou de l'oeuvre."
        )
    if style == "anecdotal":
        return (
            "Le script : complice et plein de curiosites, tu t'adresses au "
            "visiteur avec \"vous\". Varie toujours l'accroche d'ouverture : ne "
            "commence jamais par \"Arrêtez-vous\", \"Regardez\", \"Devant vous\", "
            "\"Contemplez\" ou toute formule repetitive. Mets l'accent sur les "
            "anecdotes, secrets et petites histoires peu connues plutot qu'une "
            "description exhaustive, comme un ami qui partage ce qu'il sait de "
            "plus surprenant. Construis : accroche par une anecdote, "
            "enchainement de curiosites, conclusion sur ce qui rend l'histoire "
            "memorable."
        )
    if style == "concise":
        return (
            "Le script : direct et efficace, tu t'adresses au visiteur avec "
            "\"vous\". Va droit au but : l'essentiel seulement, sans digression "
            "ni developpement long. Une accroche courte, un ou deux faits "
            "marquants, une conclusion breve."
        )
    return (
        "Le script : narratif et immersif, tu t'adresses au visiteur "
        "avec \"vous\". Varie toujours l'accroche d'ouverture : ne commence "
        "jamais par \"Arrêtez-vous\", \"Regardez\", \"Devant vous\", \"Contemplez\" "
        "ou toute formule repetitive. Sois inventif : commence par un fait "
        "surprenant, une question, une anecdote, une sensation, une date "
        "marquante, ou plonge directement dans l'histoire. Construis : "
        "accroche originale, details fascinants, contexte historique, "
        "anecdote marquante, conclusion emotionnelle."
    )


def extract_json_object(text: str) -> str | None:
    """Same balanced-brace, string-aware scan as
    GeminiApiService._extractJsonObject, so malformed model output is
    handled identically to production rather than just crashing the
    benchmark run."""
    start = text.find("{")
    if start == -1:
        return None
    depth = 0
    in_string = False
    escaped = False
    for i in range(start, len(text)):
        ch = text[i]
        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            continue
        if ch == '"':
            in_string = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[start : i + 1]
    return None


def call_gemini(
    api_key: str,
    api_url: str,
    models: list[str],
    image_bytes: bytes,
    prompt: str,
    max_tokens: int,
    temperature: float,
    thinking_budget: int,
    timeout_s: int = 30,
) -> dict:
    b64_image = base64.b64encode(image_bytes).decode("ascii")
    body = json.dumps(
        {
            "contents": [
                {
                    "parts": [
                        {"inline_data": {"mime_type": "image/jpeg", "data": b64_image}},
                        {"text": prompt},
                    ]
                }
            ],
            "generationConfig": {
                "maxOutputTokens": max_tokens,
                "temperature": temperature,
                "thinkingConfig": {"thinkingBudget": thinking_budget, "includeThoughts": False},
            },
        }
    ).encode("utf-8")

    attempts = []
    for model in models:
        url = f"{api_url}/models/{model}:generateContent?key={api_key}"
        req = urllib.request.Request(
            url, data=body, headers={"Content-Type": "application/json"}, method="POST"
        )
        t0 = time.monotonic()
        try:
            with urllib.request.urlopen(req, timeout=timeout_s) as resp:
                latency_ms = round((time.monotonic() - t0) * 1000)
                raw = resp.read().decode("utf-8")
                attempts.append(f"✓ {model}")
                return _parse_response(raw, model, latency_ms, attempts)
        except urllib.error.HTTPError as e:
            latency_ms = round((time.monotonic() - t0) * 1000)
            err_body = e.read().decode("utf-8", errors="replace")
            attempts.append(f"✗ {model} ({e.code}): {err_body[:120]}")
            if e.code in (429, 404, 503):
                continue
            return {
                "model_used": None,
                "latency_ms": latency_ms,
                "error": f"HTTP {e.code}: {err_body[:300]}",
                "attempts": attempts,
            }
        except Exception as e:  # noqa: BLE001 - benchmark script, want to record any failure
            attempts.append(f"✗ {model} (exception): {e}")
            continue

    return {"model_used": None, "latency_ms": None, "error": "all models failed", "attempts": attempts}


def _parse_response(raw: str, model: str, latency_ms: int, attempts: list[str]) -> dict:
    data = json.loads(raw)
    text = data["candidates"][0]["content"]["parts"][0]["text"]

    json_blob = extract_json_object(text)
    title, script = None, None
    if json_blob:
        try:
            parsed = json.loads(json_blob)
            title = (parsed.get("title") or "").strip()
            script = (parsed.get("script") or "").strip()
        except json.JSONDecodeError:
            pass

    word_count = len(script.split()) if script else None
    return {
        "model_used": model,
        "latency_ms": latency_ms,
        "title": title,
        "script": script,
        "word_count": word_count,
        "raw_text": text if not (title and script) else None,
        "error": None if (title and script) else "could not parse title/script JSON",
        "attempts": attempts,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api-key", required=True)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--fallback-models", nargs="*", default=DEFAULT_MODEL_FALLBACKS)
    parser.add_argument("--api-url", default=DEFAULT_API_URL)
    parser.add_argument("--max-tokens", type=int, default=DEFAULT_MAX_TOKENS)
    parser.add_argument("--temperature", type=float, default=DEFAULT_TEMPERATURE)
    parser.add_argument("--thinking-budget", type=int, default=DEFAULT_THINKING_BUDGET)
    parser.add_argument("--prompt-override", default=None, help="For ad hoc prompt experiments (see PROTOCOL.md)")
    parser.add_argument(
        "--strip-location-context",
        action="store_true",
        help="Ignore each case's location_context (send the prompt as if GPS/location "
        "context were unavailable), to isolate its effect on script quality — see "
        "PROTOCOL.md, 'Question ouverte : impact du contexte de localisation'.",
    )
    parser.add_argument("--prompt-variant-id", default="baseline")
    parser.add_argument("--manifest", default=str(DATASET_DIR / "manifest.json"))
    args = parser.parse_args()

    manifest_path = Path(args.manifest)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    cases = [c for c in manifest.get("cases", []) if not c.get("is_example")]

    if not cases:
        print(
            "Aucun cas de test réel dans manifest.json (seulement l'entrée EXAMPLE). "
            "Ajoutez vos photos + entrées avant de lancer un vrai run — voir PROTOCOL.md.",
            file=sys.stderr,
        )
        return 0

    models = [args.model] + [m for m in args.fallback_models if m != args.model]
    run_started = datetime.now(timezone.utc).isoformat()
    results = []

    for case in cases:
        photo_path = DATASET_DIR / case["photo_file"]
        if not photo_path.exists():
            print(f"[skip] {case['id']}: photo manquante ({photo_path})", file=sys.stderr)
            results.append({"case_id": case["id"], "error": f"photo not found: {photo_path}"})
            continue

        image_bytes = photo_path.read_bytes()
        location_context = None if args.strip_location_context else case.get("location_context")
        prompt = build_prompt(location_context, case.get("style"), args.prompt_override)

        print(f"[run] {case['id']} (style={case.get('style', 'immersive')}) ...", file=sys.stderr)
        result = call_gemini(
            api_key=args.api_key,
            api_url=args.api_url,
            models=models,
            image_bytes=image_bytes,
            prompt=prompt,
            max_tokens=args.max_tokens,
            temperature=args.temperature,
            thinking_budget=args.thinking_budget,
        )
        result["case_id"] = case["id"]
        result["category"] = case.get("category")
        result["style"] = case.get("style", "immersive")
        result["prompt_variant_id"] = args.prompt_variant_id
        results.append(result)

    output = {
        "run_started_utc": run_started,
        "engine": "gemini_api_cloud",
        "prompt_variant_id": args.prompt_variant_id,
        "config": {
            "models_tried_in_order": models,
            "api_url": args.api_url,
            "max_tokens": args.max_tokens,
            "temperature": args.temperature,
            "thinking_budget": args.thinking_budget,
            "location_context_stripped": args.strip_location_context,
        },
        "results": results,
    }

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    out_path = RESULTS_DIR / f"cloud_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}.json"
    out_path.write_text(json.dumps(output, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"\nRésultats écrits dans {out_path}", file=sys.stderr)

    summary_path = __import__("os").environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as f:
            f.write(f"\n## Gemini Cloud Benchmark — {run_started}\n\n")
            f.write("| Cas | Modèle | Latence (ms) | Mots | Erreur |\n")
            f.write("|---|---|---|---|---|\n")
            for r in results:
                f.write(
                    f"| {r.get('case_id')} | {r.get('model_used', '-')} | "
                    f"{r.get('latency_ms', '-')} | {r.get('word_count', '-')} | "
                    f"{r.get('error') or ''} |\n"
                )

    return 0


if __name__ == "__main__":
    sys.exit(main())
