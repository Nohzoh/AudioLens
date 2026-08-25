---
name: ship
description: Cut and publish a new AudioLens release - decide the version bump, update the Play Store release notes, land the release-bump PR, wait for the AAB build, publish to Play Store, and rotate the "Next release" milestone. Use when the user asks to "push a new version", "cut a release", "publish", or "ship it" after one or more issues have already been landed on main. Distinct from the `land` skill, which only merges a single change onto main — this is the periodic step that actually gets a batch of already-landed changes into users' hands.
---

# Ship a release on AudioLens

Run this after one or more changes are already merged to `main` (each
via the `land` skill) and it's time to cut an actual release. Follow
`AGENTS.md`'s "Version Numbering" and "Publishing to Play Store"
sections exactly rather than improvising.

## 1. Decide the version bump

List what's in the "Next release" milestone to know what's actually
shipping:

```
gh issue list --milestone "Next release" --state all --json number,title,state
```

`pubspec.yaml`'s `version: X.Y.Z+build` — only ever touch `X.Y.Z`, never
`+build` (that's the Android `versionCode`, set automatically by CI via
`--build-number=${{ github.run_number }}`).

- **Z (patch)**: the default. Bump this unless a genuine new
  user-facing *feature* shipped (not just a fix/polish/internal
  refactor) — internal refactors, dev tooling, and benchmark-only
  changes never justify more than a patch bump on their own.
- **Y (minor)**: bump instead of Z, resetting Z to 0, when the release
  ships a genuine new user-facing feature. This is the one judgment
  call — make it explicitly and say why in the release commit.
- **X (major)**: reserved for `1.0.0` and later breaking/major-redesign
  releases — essentially never triggered by a routine ship.

## 2. Update the Play Store release notes

Update both `distribution/whatsnew/whatsnew-en-US` and
`distribution/whatsnew/whatsnew-fr-FR` — owned by the agent, not the
user: summarize what's user-visible since the last publish, in plain
tester-facing language, not `CHANGELOG.md`'s technical wording.

- Only mention things a tester would actually notice. Skip internal
  refactors, dev tooling, and benchmark-only changes entirely.
- `New:` / `Fixes:` sections as needed (French: `Nouveautés :` /
  `Corrections :`).
- Google enforces a hard 500-character limit **per file** — check with
  `wc -c` before committing. If left unchanged, testers just see the
  previous release's notes again.

## 3. Branch, commit, PR

```
git checkout main && git pull --ff-only
git checkout -b chore/publish-v<X.Y.Z>
```

Edit `pubspec.yaml` and both `whatsnew-*` files, then:

```
git add pubspec.yaml distribution/whatsnew/whatsnew-en-US distribution/whatsnew/whatsnew-fr-FR
git commit -m "chore(release): bump to <X.Y.Z>, update release notes

<one line: patch or minor, and why — which issue(s) justified a minor
bump if applicable, or 'no new user-facing feature' if patch>"
git push -u origin chore/publish-v<X.Y.Z>
gh pr create --title "chore(release): bump to <X.Y.Z>, update release notes" --body "..."
```

PR body: a `## Summary` listing the issues covered since the last
publish (pull this from the milestone list in step 1) and a one-line
justification of the version bump; a `## Test plan` confirming both
`whatsnew` files are under the 500-char limit (`wc -c`).

## 4. Wait for checks, then merge

Same mechanism as `land` — poll `gh pr checks <N>` (or use the Monitor
tool) until `test` and `build` both leave `pending`, then:

```
gh pr merge <N> --merge --delete-branch
git checkout main && git pull --ff-only
```

## 5. Wait for the AAB build on main

The merge triggers a fresh `push` run of `build-android.yml` on `main`,
which builds the AAB `publish-play-store.yml` will consume:

```
gh run list --workflow=build-android.yml --branch main --limit 3 --json databaseId,status,conclusion,event,headSha,createdAt
```

Find the run whose `headSha` matches the merge commit and wait for
`status: completed`. **Concurrency gotcha**: this workflow's
`concurrency` group cancels an in-flight run when a newer commit lands
on `main` — if you push any follow-up commit (e.g. a changelog fix)
after starting this wait, re-check `gh run list` for the newer run
rather than assuming the one you were watching will finish.

If no fresh build exists yet for the commit you need (rare — normally
the merge above triggers one), use `build-android.yml`'s own
`workflow_dispatch` instead (full fresh build + publish in one run) per
`AGENTS.md`, rather than waiting on a build that isn't coming.

## 6. Publish — always confirm the track first

Publishing is a real, externally-visible production action — **always
ask the user which Play Store track before triggering this**, even if
recent releases have consistently used the same one (state what track
past releases used, but don't assume it without asking):

```
gh workflow run publish-play-store.yml -f track=<internal|alpha|beta|production>
```

Then find and wait for the new run:

```
gh run list --workflow=publish-play-store.yml --limit 1 --json databaseId,status,conclusion,createdAt
```

## 7. Rotate the milestone

Once publish succeeds, close and rename "Next release" to the version
just shipped, then create a fresh empty one for what's next:

```
gh api repos/Nohzoh/AudioLens/milestones --jq '.[] | {number, title, state}'
gh api repos/Nohzoh/AudioLens/milestones/<next-release-number> -X PATCH -f title="v<X.Y.Z>" -f state="closed"
gh api repos/Nohzoh/AudioLens/milestones -f title="Next release"
```

## 8. Report back

Tell the user: the version shipped, which track it published to, and
that the milestone rotated — they don't need to ask, but they do need
to know it actually happened.
