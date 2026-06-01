# Golden Test CI Orchestration — Design

- **Date**: 2026-06-01
- **Status**: Approved (pending user spec review)
- **Author**: Peter Jhong (with Claude Code)

## 1. Problem & Goal

PrivacyGUI has golden (screenshot) tests, but golden PNG baselines are **not committed**
to the PrivacyGUI repository (excluded by `.gitignore`: `test/**/goldens/*`,
`snapshots/*`). A scheduled diff job therefore has no baseline available *inside
PrivacyGUI* to compare against — the baseline must be stored somewhere else. That
"somewhere else" is the **orchestration repo**, which has no PNG restriction and can commit
the baseline freely.

We want a CI setup that:

1. Runs on a **fixed daily schedule**.
2. Pulls the PrivacyGUI repository at a **specified branch**.
3. Runs golden tests. This requires **two separate workflows** — and the reason is *not*
   "where can we commit PNGs" (the orchestration repo can). The reason is that **generating
   a baseline and verifying against it are different actions with different lifecycles, and
   conflating them defeats the purpose of golden testing**:
   - **Generating the baseline is a human judgement** ("this rendering is correct — freeze
     it"). It must be **manually triggered**. If generation ran automatically, every visual
     regression would silently overwrite the old baseline and become the new "correct"
     state — so no diff would ever fail and the whole check would be pointless.
   - **Verifying is the automatable check**: diff the frozen baseline against today's render.
     This runs on the **daily schedule**.
   - Each workflow also produces its own report: generation → a **gallery report**;
     verification → a **verify (diff) report**.

   (This split would hold even if PrivacyGUI itself committed its PNGs — it is about *who
   decides what "correct" looks like, and when*, not about commit permissions.)
4. Retains **verify reports for one week** (auto-delete after expiry). The **golden
   (gallery) report** is only replaced when the next baseline is generated.

## 2. Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Where the workflows live | A **new orchestration repo**, `PeterJhongLinksys/PrivacyGUI-golden-ci-test` (personal account, for testing) | PrivacyGUI does not commit PNGs; the orchestration repo can. Keeps CI concerns out of the product repo. |
| Where golden baseline is stored | Committed into the orchestration repo under `goldens/` | The repo has no PNG restriction; gives versioned, durable baselines that the daily job can `checkout`. |
| Report hosting | **GitHub Pages** of the orchestration repo | Click a URL to view the full report (with images). Verify reports stored per-date; gallery report at a fixed path. |
| Image embedding | **No `--embed`** — reports reference images by **relative path** | User preference. Means the HTML **and** its image folder must be published together, preserving relative layout. |
| Repo / Pages visibility | **Public** repo, **public** Pages | "Private Pages" (org-members-only) requires GitHub Enterprise Cloud. User does not mind the reports (UI screenshots) being public. |
| Schedule | Daily at **Taiwan 06:00** = `cron: '0 22 * * *'` (UTC) | User choice (early morning). |
| Target branch | clone PrivacyGUI at a branch, **default `main`**, overridable via `workflow_dispatch` input | Flexibility for testing other branches. |
| Failure notification | On diff/failure, **open a GitHub Issue** in the orchestration repo and `@mention` **`@PeterJhongLinksys`** | GitHub then emails / notifies that user per their own settings. Zero external setup (no SMTP), uses built-in `GITHUB_TOKEN`, and the Issue body can carry the report link. |

### Image-path note (why this matters)

`test_scripts/combine_results.dart` produces the **verify report** in two modes:
- default: image `src` is a **relative path** (relative to `test/golden_test/`);
- `--embed`: PNGs are base64-inlined → single self-contained HTML.

`test_scripts/generate_gallery_report.dart` produces the **gallery report** using
**relative paths only** (`<img src="${entry.relativePath}">`), no embed option.

Since we are **not** using `--embed`, both reports must be published **together with their
image folders**, keeping the relative directory structure intact. GitHub Pages serves a
directory tree, so relative paths resolve correctly there.

## 3. Architecture

```
Orchestration repo (new, public): PeterJhongLinksys/PrivacyGUI-golden-ci-test
├── .github/workflows/
│   ├── generate-golden.yml   # manual trigger: generate baseline + gallery report
│   └── daily-verify.yml      # daily 06:00 Taiwan + manual: diff + verify report
├── goldens/                  # golden baseline PNGs (committed)
│   └── <mirror of PrivacyGUI test/golden_test/.../goldens/*.png>
├── scripts/                  # helper scripts used by the workflows (see §6)
└── (GitHub Pages, served from gh-pages branch or Pages source)
    ├── golden/               # gallery report (fixed path, overwritten each generation)
    └── verify/YYYY-MM-DD/    # verify report per run (retained 7 days)
```

Both workflows clone PrivacyGUI (`https://github.com/linksys/PrivacyGUI.git`, public) at the
chosen branch into a sub-directory, then operate inside it.

PrivacyGUI environment facts (from inspection):
- Flutter channel `stable` (no fvm in CI).
- `ui_kit_library` is a **private** Git dependency → still needs `UI_KIT_DEPLOY_KEY` SSH
  secret + `git config url."git@github.com:".insteadOf "https://github.com/"` (mirrors the
  existing `.github/workflows/ci.yml` approach).
- Golden defaults: `locales=en`, `screens=480,1280`.

## 4. Workflow 1 — `generate-golden.yml` (manual baseline)

**Trigger**: `workflow_dispatch` with input `branch` (default `main`); optional inputs
`locales`, `screens` (defaults `en`, `480,1280`).

**Steps**:
1. Checkout orchestration repo.
2. Setup Flutter (`subosito/flutter-action@v2`, channel `stable`, cache).
3. Setup SSH for private deps (`webfactory/ssh-agent@v0.9.0` with `UI_KIT_DEPLOY_KEY`);
   configure git `insteadOf`.
4. `git clone --branch <branch> --depth 1 https://github.com/linksys/PrivacyGUI.git app`.
5. In `app/`: copy `assets/agents/env.template` → `assets/agents/.env`; `flutter pub get`.
6. Run `sh run_generate_loc_snapshots.sh -l "<locales>" -s "<screens>"` →
   generates golden PNGs under `app/test/golden_test/.../goldens/` and the gallery report
   `app/test/golden_test/golden_gallery_report.html`.
7. **Commit golden baseline back** to orchestration repo `goldens/`: clear old, copy new
   PNGs (the "next generation deletes previous" behavior), commit & push.
8. **Publish gallery report** to Pages at fixed path `golden/` (HTML + referenced PNGs),
   overwriting the previous one.

## 5. Workflow 2 — `daily-verify.yml` (scheduled diff)

**Trigger**: `schedule: '0 22 * * *'` (UTC = Taiwan 06:00) **and** `workflow_dispatch` with
input `branch` (default `main`) + optional `locales`, `screens`.

**Steps**:
1. Checkout orchestration repo (includes the committed `goldens/` baseline).
2. Setup Flutter + SSH for private deps + git `insteadOf` (same as Workflow 1).
3. `git clone --branch <branch> --depth 1 https://github.com/linksys/PrivacyGUI.git app`.
4. In `app/`: copy env template; `flutter pub get`.
5. **Restore baseline**: copy orchestration-repo `goldens/` PNGs into the matching
   `app/test/golden_test/.../goldens/` locations (so they act as masters to diff against).
6. Run `sh run_golden_verify.sh -l "<locales>" -s "<screens>"` (**no `--embed`**) →
   produces `app/test/golden_test/golden_verify_report.html` plus failure images under each
   feature's `failures/` directory.
7. **Publish verify report** (HTML + its image folders, preserving relative structure) to
   Pages at `verify/<YYYY-MM-DD>/`.
8. **Retention cleanup**: delete `verify/<date>/` directories older than 7 days.
9. **On failure** (any golden mismatch): open a GitHub Issue in the orchestration repo via
   `GITHUB_TOKEN`, body `@mention`s `@PeterJhongLinksys` and links to
   `https://<owner>.github.io/<repo>/verify/<YYYY-MM-DD>/golden_verify_report.html`.

### Determining "did it fail?"

`run_golden_verify.sh` swallows test exit codes (`|| true`) so the report always generates.
Failure detection therefore reads the **parsed result** (the combined JSON / report's
`counting.fail`) rather than the shell exit code. The workflow inspects that count to decide
whether to open the Issue.

## 6. Helper Scripts (in orchestration repo)

To keep workflows readable, small helpers live under `scripts/`:
- `sync_baseline_into_app.sh` — copy `goldens/` → `app/test/golden_test/...` before verify.
- `collect_baseline_from_app.sh` — copy generated goldens from `app/` → `goldens/` after generate.
- `publish_to_pages.sh` — copy a report dir (HTML + images) into the Pages working tree at a
  target sub-path.
- `prune_old_verify_reports.sh` — delete `verify/<date>/` older than 7 days.
- `detect_golden_failures.sh` — parse the verify result and emit a fail count / flag.

Exact mechanics (how date math is done, how the Pages branch is updated) are deferred to the
implementation plan.

## 7. Requirements Traceability

| Requirement | Implementation |
|-------------|----------------|
| 1. Run daily at a fixed time | `daily-verify.yml` `schedule: '0 22 * * *'` (Taiwan 06:00) |
| 2. Pull PrivacyGUI at a specified branch | Both workflows `git clone --branch <input>` (default `main`) |
| 3. Two actions (generate + verify) | `generate-golden.yml` + `daily-verify.yml` |
| 4. Verify reports kept one week, expire after | Pages `verify/YYYY-MM-DD/`; prune > 7 days |
| 4. Golden report replaced only on next generation | Pages fixed `golden/`; overwritten by generate workflow |
| Notification on failure | Open Issue + `@PeterJhongLinksys` mention with report link |

## 8. Open Questions / Deferred

- **Pages source mechanism**: `gh-pages` branch (e.g. `peaceiris/actions-gh-pages`) vs. the
  newer Pages "build from artifact" model. Default lean: `gh-pages` branch, because we need
  to *accumulate* dated sub-directories and prune old ones across runs, which a persistent
  branch handles naturally. To be finalized in the plan.
- **PrivacyGUI visibility**: **confirmed public** (`gh api repos/linksys/PrivacyGUI` →
  `private: false`), so the clone needs no token. **However** its dependency
  `linksys/privacyGUI-UI-kit` (used by `ui_kit_library` + `generative_ui`, ref `v2.19.0`)
  is **private**, so `flutter pub get` still requires the `UI_KIT_DEPLOY_KEY` SSH secret —
  this is not optional.
- **Locales/screens scope for daily run**: defaults `en` / `480,1280`. Can be widened later;
  wider scope = longer run + more baseline images.

## 9. Out of Scope (YAGNI)

- Slack / SMTP email integration (using GitHub Issue mention instead).
- Comparing across multiple branches in a single run.
- Auto-updating the baseline from the daily job (baseline only changes via the manual
  generate workflow — intentional, so diffs are meaningful).
- Private (org-only) Pages access control (requires Enterprise Cloud).

---

# Implementation Plan

> **Read me first (you are the Claude working inside the orchestration repo
> `PrivacyGUI-golden-ci-test`):** This plan is self-contained. You do NOT have the PrivacyGUI
> source — you only build the CI repo that *drives* PrivacyGUI. Everything you need to know
> about PrivacyGUI's scripts and layout is captured below in "Facts about PrivacyGUI". You
> are free to improve on this plan — it reflects decisions made before the repo existed; if
> something is cleaner once you can run things, change it. Sections 1–9 above are the design
> rationale; read them for the "why".

## Facts about PrivacyGUI (verified 2026-06-01, you can re-verify)

- Repo: `https://github.com/linksys/PrivacyGUI.git` — **public** (clone needs no token).
- Flutter channel: `stable`, no fvm in CI. Its scripts auto-fallback to plain `flutter`/`dart`
  when fvm is absent.
- **Private transitive dependency**: `linksys/privacyGUI-UI-kit` (pubspec deps
  `ui_kit_library` and `generative_ui`, ref `v2.19.0`). `flutter pub get` WILL fail without
  SSH access to it → the orchestration repo needs an `UI_KIT_DEPLOY_KEY` secret, and the
  workflow must `git config --global url."git@github.com:".insteadOf "https://github.com/"`.
- Env file needed before pub get: `cp assets/agents/env.template assets/agents/.env`.
- Golden generation script: `run_generate_loc_snapshots.sh -l "<locales>" -s "<screens>"`.
  - Runs `flutter test test/golden_test/ --update-goldens` per locale; then
    `dart run test_scripts/generate_gallery_report.dart <version>`.
  - Output: PNGs at `test/golden_test/**/goldens/*.png`; gallery report at
    `test/golden_test/golden_gallery_report.html` (image `src` = **relative paths**).
- Golden verify script: `run_golden_verify.sh -l "<locales>" -s "<screens>"` (do NOT pass
  `--embed`).
  - Per locale: `flutter test ... --file-reporter json` → `test_result_parser.dart` →
    per-locale `localizations-test-reports-<locale>.json`; then `combine_results.dart` →
    `test/golden_test/golden_verify_report.html`. Failure images land under each feature's
    `failures/` dir; report references them by **relative path** (relative to
    `test/golden_test/`). Both scripts swallow the test exit code (`|| true`).
- Defaults: `locales=en`, `screens=480,1280`.
- Golden PNG path shape (mirror this exactly in the baseline dir):
  `test/golden_test/page/<feature>/localizations/goldens/<tsName>-<device>-<locale>.png`.
- **Failure detection**: read the combined report. `combine_results.dart` writes a JSON-bearing
  HTML; each test record carries `result` = `success` | `error`, and the report object has
  `counting.fail`. Parse the per-locale `localizations-test-reports-*.json` (each is a JSON
  array of records with a `result` field) — if any record has `result == "error"`, the run
  failed. (Simplest robust signal; the HTML is for humans.)

## Decisions locked before repo creation

| Topic | Decision |
|-------|----------|
| Orchestration repo | `PeterJhongLinksys/PrivacyGUI-golden-ci-test`, **public** |
| Baseline storage | **TBD by you — open question, see below.** Default lean: committed to a dedicated `baseline` branch under `goldens/test/golden_test/...` mirroring PrivacyGUI's layout |
| Report hosting | GitHub Pages via a `gh-pages` branch (lets you accumulate dated dirs + prune) |
| Image embedding | None — publish HTML **with** its image folder, relative paths intact |
| Schedule | `cron: '0 22 * * *'` (UTC) = Taiwan 06:00 |
| Target branch | `workflow_dispatch` input `branch`, default `main` |
| Failure notify | Open a GitHub Issue, body `@PeterJhongLinksys` + Pages report link |

> **Open question to resolve once you can run things:** baseline on `main` vs. a dedicated
> `baseline` branch vs. a release asset. The daily job only needs to *read* it; the generate
> job *writes* it. A dedicated branch keeps `main` (the workflows) clean and is the
> recommended default — but you may pick differently if you see a problem.

## Repo file structure to build

```
PrivacyGUI-golden-ci-test/
├── README.md                      # prerequisites + how to run (see Task 6)
├── .gitignore                     # ignore the transient ./app clone, *.json scratch
├── scripts/
│   ├── collect_baseline_from_app.sh   # app goldens → baseline dir (clears old first)
│   ├── sync_baseline_into_app.sh      # baseline dir → app goldens (before verify)
│   ├── publish_to_pages.sh            # copy a report dir into gh-pages worktree subpath
│   ├── prune_old_verify_reports.sh    # delete verify/<date> older than 7 days
│   └── detect_golden_failures.sh      # parse reports → exit 1 + count if any failure
└── .github/workflows/
    ├── generate-golden.yml        # manual: build baseline + gallery report
    └── daily-verify.yml           # scheduled+manual: diff + verify report + notify
```

## Task 0 — Bootstrap the repo (human + Claude)

- [ ] `gh repo create PeterJhongLinksys/PrivacyGUI-golden-ci-test --public --clone` (or create
      empty + push). Confirm `gh auth status` shows scopes `repo` + `workflow`.
- [ ] Add `.gitignore`:
      ```gitignore
      /app/
      *.log
      .DS_Store
      ```
- [ ] Commit the skeleton.

## Task 1 — `scripts/collect_baseline_from_app.sh`

Purpose: after generation, copy `app/test/golden_test/**/goldens/*.png` into the baseline dir,
mirroring the relative path. **Clear the previous baseline first** ("next generation deletes
the previous"). Fail loudly if zero PNGs (don't commit an empty baseline).

- [ ] Signature: `collect_baseline_from_app.sh <APP_DIR> <BASELINE_DIR>`.
- [ ] `set -euo pipefail`; validate `$APP_DIR/test/golden_test` exists.
- [ ] `rm -rf "$BASELINE_DIR/test"`; then for each `test/golden_test/**/goldens/*.png` under
      APP_DIR, `mkdir -p` the parallel dir under BASELINE_DIR and `cp`.
- [ ] Count copied; `exit 1` with a clear message if count == 0.

## Task 2 — `scripts/sync_baseline_into_app.sh`

Purpose: before verify, copy baseline PNGs back into the fresh PrivacyGUI clone so they act as
masters to diff against. Inverse of Task 1, same relative layout (so it's a plain copy, no path
math). Fail loudly if the baseline dir is empty (means generate was never run).

- [ ] Signature: `sync_baseline_into_app.sh <BASELINE_DIR> <APP_DIR>`.
- [ ] `set -euo pipefail`; validate baseline has ≥1 PNG, else `exit 1` with "run generate first".
- [ ] Copy `$BASELINE_DIR/test/...` → `$APP_DIR/test/...` preserving structure.

## Task 3 — `scripts/detect_golden_failures.sh`

Purpose: decide if the verify run found diffs, since the verify script always exits 0.

- [ ] Signature: `detect_golden_failures.sh <APP_DIR>`.
- [ ] Find `app/test/golden_test/localizations-test-reports-*.json` (or wherever
      `combine_results.dart`/`test_result_parser.dart` writes them — verify the actual path on
      first run; the parser writes next to the input `tests.json`, i.e. `test/golden_test/`).
- [ ] Count records with `result == "error"` across all those JSON files (use `jq`).
- [ ] Print the count; `exit 1` if > 0, else `exit 0`. (Workflow uses this to gate the Issue.)

## Task 4 — `scripts/publish_to_pages.sh` + `scripts/prune_old_verify_reports.sh`

`publish_to_pages.sh <SRC_DIR> <PAGES_WORKTREE> <SUBPATH>`:
- [ ] `set -euo pipefail`; `rm -rf "$PAGES_WORKTREE/$SUBPATH"`; `mkdir -p`; copy SRC_DIR
      contents (HTML + image folders) into it preserving structure.
- [ ] (Workflow commits the gh-pages worktree afterward.)

`prune_old_verify_reports.sh <PAGES_WORKTREE> <KEEP_DAYS>`:
- [ ] `set -euo pipefail`; under `$PAGES_WORKTREE/verify/`, for each `YYYY-MM-DD` dir, compute
      age vs. today and `rm -rf` if older than KEEP_DAYS. **Note:** GitHub Actions runners have
      GNU `date`; compute `today` from `$(date -u +%F)` inside the workflow (not hardcoded).
- [ ] Skip non-date entries safely.

## Task 5 — `.github/workflows/generate-golden.yml`

Trigger: `workflow_dispatch` inputs `branch` (default `main`), `locales` (default `en`),
`screens` (default `480,1280`).

Steps (single job, `ubuntu-latest`, `timeout-minutes: 45`):
- [ ] `actions/checkout@v4` (the orchestration repo).
- [ ] `subosito/flutter-action@v2` channel `stable`, cache true.
- [ ] `webfactory/ssh-agent@v0.9.0` with `${{ secrets.UI_KIT_DEPLOY_KEY }}`; then
      `git config --global url."git@github.com:".insteadOf "https://github.com/"`.
- [ ] Clone target: `git clone --branch "${{ inputs.branch }}" --depth 1 https://github.com/linksys/PrivacyGUI.git app`.
- [ ] In `app`: `cp assets/agents/env.template assets/agents/.env`; `flutter pub get`.
- [ ] `sh run_generate_loc_snapshots.sh -l "${{ inputs.locales }}" -s "${{ inputs.screens }}"`
      (run with working-directory `app`).
- [ ] `scripts/collect_baseline_from_app.sh app <BASELINE_DIR>` → commit baseline to the chosen
      baseline location (branch/dir per the open question). Use a bot identity
      (`git config user.name/.email`) and the built-in `GITHUB_TOKEN`.
- [ ] Publish `app/test/golden_test/golden_gallery_report.html` **and** the `goldens/` image
      dirs it references to gh-pages `golden/` via `publish_to_pages.sh` (fixed path, overwrite).
      Because the gallery HTML uses paths relative to `test/golden_test/`, publish that whole
      subtree (HTML + `page/**/goldens/*.png`) so the relative `src` resolves on Pages.

## Task 6 — `.github/workflows/daily-verify.yml`

Trigger: `schedule: '0 22 * * *'` **and** `workflow_dispatch` inputs `branch` (default `main`),
`locales`, `screens`.

Steps (single job, `ubuntu-latest`, `timeout-minutes: 45`):
- [ ] Checkout orchestration repo (+ baseline — checkout the baseline branch/path).
- [ ] Flutter + ssh-agent + git insteadOf (same as Task 5).
- [ ] Clone PrivacyGUI at `branch`; env file; `flutter pub get`.
- [ ] `scripts/sync_baseline_into_app.sh <BASELINE_DIR> app`.
- [ ] `sh run_golden_verify.sh -l "${{ inputs.locales || 'en' }}" -s "${{ inputs.screens || '480,1280' }}"`
      (no `--embed`), working-directory `app`.
- [ ] `today=$(date -u +%F)`; publish `app/test/golden_test/golden_verify_report.html` + its
      `failures/`/`goldens/` image dirs to gh-pages `verify/$today/` via `publish_to_pages.sh`.
- [ ] `scripts/prune_old_verify_reports.sh <PAGES_WORKTREE> 7`; commit + push gh-pages.
- [ ] `scripts/detect_golden_failures.sh app` — if it exits non-zero, open an Issue:
      ```bash
      gh issue create \
        --title "Golden verify failed — $today ($BRANCH)" \
        --body "@PeterJhongLinksys golden diffs detected on \`$BRANCH\`.
      Report: https://peterjhonglinksys.github.io/PrivacyGUI-golden-ci-test/verify/$today/golden_verify_report.html
      Failures: $FAIL_COUNT"
      ```
      Use `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}`. Guard so a passing run opens nothing.

## Task 7 — `README.md` (prerequisites the human must do once)

Document, in order:
- [ ] **Secrets**: add `UI_KIT_DEPLOY_KEY` = a deploy key with read access to
      `linksys/privacyGUI-UI-kit` (else `flutter pub get` fails). Repo Settings → Secrets.
- [ ] **Pages**: enable GitHub Pages, source = `gh-pages` branch, root. URL will be
      `https://peterjhonglinksys.github.io/PrivacyGUI-golden-ci-test/`.
- [ ] **Run order**: (1) trigger `generate-golden` once to seed the baseline + gallery report;
      (2) then `daily-verify` (manual once to smoke-test, then it runs nightly).
- [ ] **Where to look**: gallery report `…/golden/`; daily reports `…/verify/<date>/`.
- [ ] Note that reports are **public** (repo is public).

## Self-review checklist (run before handing off)

- [ ] Every requirement in §7 maps to a task above.
- [ ] No script references a path that PrivacyGUI doesn't actually produce — re-verify the
      report JSON output path on the first real `daily-verify` run and fix `detect_golden_failures.sh`
      if needed.
- [ ] gh-pages publishing preserves relative image paths (publish the `test/golden_test`
      subtree, not just the lone HTML file).
- [ ] First end-to-end: generate → verify(no-change, expect pass) → intentionally tweak a UI →
      verify(expect fail + Issue).
