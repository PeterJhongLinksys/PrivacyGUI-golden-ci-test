# PrivacyGUI Golden CI

Orchestration repo that drives golden (screenshot) testing of
[linksys/PrivacyGUI](https://github.com/linksys/PrivacyGUI) on a daily schedule.

## Prerequisites (one-time setup)

### 1. Add `UI_KIT_DEPLOY_KEY` secret

PrivacyGUI depends on the private repo `linksys/privacyGUI-UI-kit`. Without SSH access,
`flutter pub get` will fail.

1. Generate a deploy key: `ssh-keygen -t ed25519 -C "golden-ci" -f golden_ci_key`
2. Add the **public** key as a deploy key (read-only) on `linksys/privacyGUI-UI-kit`
3. Add the **private** key as a repository secret named `UI_KIT_DEPLOY_KEY` on this repo
   (Settings → Secrets and variables → Actions)

### 2. Enable GitHub Pages

1. Go to Settings → Pages
2. Source: **Deploy from a branch**
3. Branch: `gh-pages`, folder: `/ (root)`
4. URL will be: `https://peterjhonglinksys.github.io/PrivacyGUI-golden-ci-test/`

### 3. First run order

1. **Trigger `Generate Golden`** with mode = `baseline` (seeds the `baseline` branch + dev gallery)
2. **Trigger `Generate Golden`** with mode = `showcase`, branch = `usp` (publishes USP gallery)
3. **Trigger `Daily Golden Verify`** manually once to smoke-test
4. After that, the daily verify runs automatically at Taiwan 06:00

## Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| **Generate Golden** (mode=`showcase`) | Manual | Generate gallery report from `usp` branch → publish to `golden/usp/` |
| **Generate Golden** (mode=`baseline`) | Manual | Generate gallery + commit baseline from dev branch → publish to `golden/dev/` |
| **Daily Golden Verify** | Daily cron (06:00 Taiwan) + manual | Diff current dev branch render against baseline, publish verify report, open Issue on failure |

## Reports

<!-- REPORTS:START -->
### Showcase (USP)

- [Gallery Report](https://PeterJhongLinksys.github.io/PrivacyGUI-golden-ci-test/golden/usp/golden_gallery_report.html) — updated: 2026-06-03

### Dev Baseline

- [Gallery Report](https://PeterJhongLinksys.github.io/PrivacyGUI-golden-ci-test/golden/dev/golden_gallery_report.html) — updated: 2026-06-08

### Daily Verify

| Date | Report |
|------|--------|
| 2026-06-08 | [Verify Report](https://PeterJhongLinksys.github.io/PrivacyGUI-golden-ci-test/verify/dev/2026-06-08/golden_verify_report.html) |
| 2026-06-04 | [Verify Report](https://PeterJhongLinksys.github.io/PrivacyGUI-golden-ci-test/verify/dev/2026-06-04/golden_verify_report.html) |
| 2026-06-03 | [Verify Report](https://PeterJhongLinksys.github.io/PrivacyGUI-golden-ci-test/verify/dev/2026-06-03/golden_verify_report.html) |

<!-- REPORTS:END -->

## Branch structure

| Branch | Purpose |
|--------|---------|
| `main` | Workflows, scripts, documentation |
| `baseline` | Golden baseline PNGs (written by generate workflow) |
| `gh-pages` | Published reports for GitHub Pages |

## Retention

- **Gallery report**: overwritten each time `Generate Golden Baseline` runs
- **Verify reports**: kept for 7 days, automatically pruned

## Failure notification

When the daily verify detects diffs, it opens a GitHub Issue in this repo mentioning
`@PeterJhongLinksys` with a link to the verify report.

## Note

Reports are **public** (this repo is public). They contain UI screenshots only.
