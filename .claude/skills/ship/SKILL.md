---
name: ship
description: Run the full PR lifecycle for this repo - branch, Conventional Commits, push, open PR, wait for the Test + Build Android APK checks, merge, and clean up. Also handles closing a TODO.md task (moving its entry to CHANGELOG.md) in the same PR. Use whenever a code or docs change in this repo is ready to go out, or when the user asks to "push", "open a PR", "ship this", or close out a task.
---

# Ship a change on audio-guide (AudioLens)

This encodes the git/PR workflow already documented in `AGENTS.md` —
follow it exactly rather than improvising branch names, commit formats,
or the merge command.

## 1. Branch

Sync `main` first, then branch with a prefix that matches the change:
`feature/`, `fix/`, `docs/`, `chore/`, `cleanup/`, `ci/`, followed by a
short kebab-case description (add the task ID if there is one, e.g.
`feature/t76-chunked-tts`).

```
git checkout main && git pull origin main -q
git checkout -b <prefix>/<short-description>
```

## 2. Commit

Conventional Commits format, effective 2026-08-16 (not retroactive):
`<type>[optional scope]: <description>`. Types: `feat`, `fix`, `docs`,
`refactor`, `test`, `ci`, `build`, `chore`, `style`, `perf`. Explain the
*why* in the body, not just the what.

Before committing code changes (not needed for docs-only changes):
- `flutter analyze` → must show "No issues found!"
- `flutter test` → must show all tests passing
- If native Android/Kotlin code or the CI/build scripts changed: also run
  a real local build (`scripts/build_android_local.sh`) — `flutter
  analyze`/`flutter test` don't touch `android/` at all. Requires
  `openjdk@17` on `PATH` and `JAVA_HOME` set (not the bare `java` shim).
  Clean up bootstrap side effects afterward: `git status --short` should
  only show your intended changes — revert anything else `flutter
  create`/the bootstrap touched (`.metadata`, `pubspec.lock`, stray
  `test/widget_test.dart`, etc.), then `git clean -fdX -- android/` to
  drop gitignored build artifacts.

## 3. Push and open the PR

```
git push -u origin <branch-name>
gh pr create --title "<type>: ..." --body "..."
```

PR body convention: a `## Summary` (bullets) and a `## Test plan`
(checklist of what was actually verified — `flutter analyze`, `flutter
test` counts, real build if applicable). PR titles don't strictly need
the Conventional Commits prefix (this repo uses `--merge`, not squash,
so the PR title never becomes a commit message), but matching it is
fine.

## 4. If this closes a TODO.md task

Update `TODO.md` (remove the entry) and `CHANGELOG.md` (add it under
`## ✅ Done`, most-recent-first) in the **same PR**, as a follow-up
commit once the PR number is known so the changelog entry can reference
it (`PR #<n>`). This is why it's a separate commit instead of amending.

CHANGELOG entry format:
```
- [x] **T<n>** <priority-emoji> <effort-stars> - <title>
  - **Verified**: YYYY-MM-DD (PR #<n>, commit `<hash>`)
  - **What was done**: ...
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → N/N
```

Before pushing, check for duplicate task IDs:
```
grep -o '\*\*T[0-9]\+\*\*' TODO.md CHANGELOG.md | sed 's/.*://' | sort | uniq -d
```
(should print nothing).

## 5. Wait for checks

Use the Monitor tool (not a sleep-poll loop in the main turn) with this
exact script, swapping in the PR number:

```bash
prev=""
while true; do
  s=$(gh pr checks <N> --json name,bucket 2>/dev/null || true)
  if [ -n "$s" ]; then
    cur=$(echo "$s" | jq -r '.[] | select(.bucket!="pending") | "\(.name): \(.bucket)"' | sort)
    comm -13 <(echo "$prev") <(echo "$cur")
    prev=$cur
    if echo "$s" | jq -e 'all(.bucket!="pending")' >/dev/null 2>&1; then
      echo "ALL DONE"
      break
    fi
  fi
  sleep 20
done
```

The two required checks are named `test` and `build` (job names; they
show as "Test" and "Build Android APK" in the GitHub UI).

## 6. Merge and clean up

Only after both checks pass:

```
gh pr merge <N> --merge --delete-branch
git checkout main && git pull origin main -q
git branch -D <branch-name> 2>/dev/null
```

Never `--squash` (this repo keeps individual commits) and never
`--admin`/force-merge past a failing or pending check.
