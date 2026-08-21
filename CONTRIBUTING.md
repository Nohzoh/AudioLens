# Contributing to AudioLens

Thanks for taking a look. This is a small, actively-developed Flutter
project (Android today) — contributions, bug reports, and forks are
welcome. This file covers the practical basics; the fuller day-to-day
conventions (how PRs get reviewed, how releases are versioned, how the
CI is structured) live in [`AGENTS.md`](AGENTS.md) — worth a skim if
you're planning more than a one-off fix.

## Local setup

Requirements (macOS/Linux, one-time):

```bash
brew install --cask temurin@17
brew install --cask android-commandlinetools
brew install gnu-sed   # macOS only — CI runs on Linux, gnu-sed matches its sed behavior locally
```

Then:

```bash
flutter pub get
bash scripts/build_android_local.sh   # builds a debug APK, patches the Android manifest/Gradle files identically to CI
```

Run the test suite and static analysis before opening a PR:

```bash
flutter analyze
flutter test
```

## Architecture

Start with [`README.md`](README.md) for the feature overview and
[`ARCHITECTURE.md`](ARCHITECTURE.md) for the pipeline design
(photo → GPS → Wikipedia → AI → TTS → audio) and diagrams.

## Workflow

`main` is protected — no direct pushes. Every change goes through a
branch and a pull request:

```bash
git checkout -b <branch-name>
# ... commit your change(s) ...
git push -u origin <branch-name>
gh pr create --title "..." --body "..."
```

Both the `Build Android APK` and `Test` CI checks (Flutter analyze +
test, plus a real Android build) must pass before a PR can merge. Both
are skipped automatically (not run, reported as `skipped`) for changes
that only touch `.md` files, to keep docs-only PRs fast.

### Commit messages

[Conventional Commits](https://www.conventionalcommits.org/):
`<type>[optional scope]: <description>`.

Types used in this project: `feat`, `fix`, `docs`, `refactor`, `test`,
`ci`, `build`, `chore`, `style`, `perf`. Scope is optional (e.g.
`feat(tts): ...`). Keep the summary line under ~72 characters; put the
"why" in the body if it's not obvious from the summary alone.

```
feat: run analysis in the background and notify when audio is ready
fix(location): stop leaking the GPS listener on cancel
docs: translate TODO.md and CHANGELOG.md to English
```

### Backlog

Planned work and known issues are tracked directly in the repo:
[`TODO.md`](TODO.md) for what's next, [`CHANGELOG.md`](CHANGELOG.md)
for what's already shipped and how it was verified. If you're picking
up a `TODO.md` item, mention it in your PR description.

## Reporting issues

Open a [GitHub issue](https://github.com/Nohzoh/AudioLens/issues) with
what you expected vs. what happened, and your Android version if it's
device-specific. For anything security-related, please don't open a
public issue — see [`PRIVACY.md`](PRIVACY.md) for contact details.
