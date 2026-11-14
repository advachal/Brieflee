# Brieflee: Flutter app (phase 1)

Evidence-based legal counsel discovery for web, Android and iOS. This is the
"next implementation milestone" from the product blueprint: complete
navigation and UI, typed domain models, repository interfaces, REST API
contracts and clearly labelled demonstration data.

> **Two kinds of data.** **Ask** (`/ask`) and the **Records** pages run on
> **real** Delhi High Court records (see below). The original matter flow
> (New matter → Analysis → Results → Profile/Compare) still runs on clearly
> labelled **fictional** demo data ("Advocate A", `DEMO-DHC-…`). A teal
> banner marks real pages, a gold banner marks demo pages.

## Real data and the knowledge layer (phase 2 pilot)

**Source.** Delhi High Court decisions 2023–2025 from the eCourts judgments
portal, via the *Indian High Court Judgments* dataset on AWS Open Data
(`s3://indian-high-court-judgments`, CC BY 4.0). This is the same official
source the [Open India Law](https://github.com/Vaquill-AI/open-india-law)
corpus (Vaquill AI, CC BY 4.0) is built on; its Hugging Face and mirror
downloads were not reachable from the build environment, so the pipeline
reads the AWS copy directly. Judgments are reproducible under s.52(1)(q) of
the Copyright Act; attribution is shown on every real page.

**Pipeline** (all scripts in `tool/`):

1. `build_dhc_snapshot.py` — metadata parquet → `assets/data/dhc_snapshot*.json`:
   109,341 decisions with case number, parties, bench, CNR, PDF link, and
   counsel parsed from the header excerpt.
2. `knowledge/harvest_texts.py` — downloads the official PDFs for the pilot
   subjects (commercial, arbitration, IP: ~13,300) and extracts their text.
3. `knowledge/build_knowledge.py` — builds the knowledge layer:
   * **outcome** per decision read from the operative sentence by
     conservative rules (`knowledge/outcomes.py`), stored *with that sentence*
     as evidence. Only "petitioner side succeeded" / "respondent side
     succeeded" count; settled, withdrawn, infructuous, interim, partly
     allowed, arbitrator-appointed and unclear orders never count;
   * full counsel list from the judgment header, statutes and sections cited,
     key terms (TF-IDF, person names excluded);
   * `build/knowledge/knowledge.db` — SQLite with text chunks + FTS5 (BM25);
   * `assets/data/dhc_knowledge.json` — the compact layer bundled in the app.

**Ask, in real time** (`lib/core/public_records/ask_engine.dart`, on device):
interpret the question (subject → official case types, sections, judge,
counsel, year, case number, side) → retrieve similar decisions (BM25-style
over key terms, statutes and parties) → credit counsel on the winning side of
outcome-eligible similar decisions, smooth the rate toward 50% (prior 10),
require ≥3 decided outcomes to rank, weight by similarity and side fit →
a factual answer built from those numbers. Every number opens the decisions
behind it; every decision links to its official PDF.

**Knowledge service** (`server/`, optional): FastAPI `POST /v1/ask` does the
same over the *full judgment text* (FTS5) and, if `ANTHROPIC_API_KEY` is set,
adds a short grounded summary from Claude that may cite only the retrieved
decisions. Run it with
`KNOWLEDGE_DB=build/knowledge/knowledge.db uvicorn app:app --app-dir server`
and start the app with `--dart-define=BRIEFLEE_KNOWLEDGE_URL=http://localhost:8000`.

**Known limits.** Counsel names are matched by spelling (namesakes merge);
header parsing can miss names; outcomes are only known for the ~13k pilot
judgments read in full; win/loss is from the petitioner/respondent point of
view and ignores partial relief. Treat results as evidence to review, not a
recommendation.

## Run it

```bash
flutter pub get
flutter run -d chrome          # web
flutter run                    # attached Android / iOS device or simulator
flutter test                   # scoring, dedup, JSON, layouts, routes, real-records engine and Ask screens
flutter build web --release --no-web-resources-cdn
```

Built with Flutter 3.50 / Dart 3.14. Material widgets come from the
`material_ui` package (Flutter moved Material out of the SDK in 3.47).

## Stack

- **State:** Riverpod 3 (`Provider`, `FutureProvider.family`, `Notifier`)
- **Routing:** GoRouter 18, one `ShellRoute` with responsive navigation
- **Uploads:** `file_picker` (only name and size are read in this build)
- **Type:** Times New Roman, falling back to the bundled, metric-compatible
  Tinos (Apache 2.0) where the system font is unavailable (Android, web)

## Design

Navy, teal, off-white and restrained gold, in an editorial style: large
serif headings, generous whitespace, hairline rules, pill buttons, a quiet
top navigation bar on tablet/desktop and a bottom bar on phones.

- **Desktop results:** three panels (filters, ranked advocates, evidence).
- **Phone results:** filters in a bottom sheet, expandable result cards.
- Every number (relevant cases, favorable, before bench…) opens the exact
  cases behind it.

## Screens (blueprint section 8)

| Screen | Route |
| --- | --- |
| Landing / Home | `/` |
| Login / Account | `/login` |
| New Matter (describe, upload, case number) | `/matters/new` |
| AI Case Analysis + bench intelligence | `/matters/:id/analysis` |
| Court Explorer | `/courts`, `/courts/:id` |
| Judge Explorer (directory, roster, cause list, notices, history) | `/judges?court=dhc` |
| Search Results (3-panel) | `/recommendations/:id` |
| Advocate Profile | `/advocates/:id?rec=` |
| Advocate Comparison | `/compare?rec=&ids=a1,a2` |
| Judgment Details | `/judgments/:id` |
| Saved Matters | `/saved` |
| Alerts | `/alerts` |
| Settings (privacy, notifications, deletion) | `/settings` |
| Admin Dashboard (sign in first) | `/admin` |

Try: Home → "See a sample result", or New matter → Case no. →
`CS(COMM) 512/2026` (a demo listing whose bench changed).

## Structure

```
lib/
├── main.dart
├── app/                 app.dart, router.dart, app_shell.dart, theme/
├── core/
│   ├── api/             api_contract.dart (endpoints), brieflee_api.dart (typed client, DTOs)
│   ├── auth/            demo auth controller (Firebase Auth / OIDC later)
│   ├── config/          data mode and source feature flags (all live sources off)
│   ├── errors/          typed failures
│   ├── intelligence/    scoring_engine.dart, judgment_deduplicator.dart
│   ├── mock/            demo_dataset.dart (deterministic, fictional)
│   ├── models/          typed domain models with toJson/fromJson
│   └── widgets/         shared UI (badges, cards, async views)
├── features/<feature>/
│   ├── domain/          repository interfaces, feature rules
│   ├── data/            mock repositories (swap for API-backed ones)
│   ├── application/     Riverpod providers / notifiers
│   └── presentation/    screens and widgets
└── shared/              constants, utilities
```

Features: home, authentication, case_intake, document_upload,
case_analysis, court_explorer, judge_roster, advocate_search,
advocate_profile, advocate_comparison, judgment_viewer, saved_matters,
notifications, settings, admin.

## What is real logic vs. mock

Real, tested logic that will carry into production:

- **Scoring engine** (`core/intelligence/scoring_engine.dart`):
  `S = 0.30C + 0.20F + 0.15J + 0.20O + 0.10R + 0.05V`, components normalised,
  versioned weights (adjustable in Admin → Methodology). Outcome evidence is
  smoothed toward 50% so 8/10 does not automatically beat 70/100. The judge
  weight is redistributed when no bench is known. Advocates below the
  evidence threshold are listed as "insufficient verified evidence", not ranked.
- **Outcome eligibility:** settled, withdrawn, procedural and indeterminate
  matters, and unverified appearances, are excluded from favorable rates and
  listed separately.
- **Deduplication:** one case per court + case number + date, every source kept,
  official record wins on conflict.
- **Search hits vs. appearances vs. eligible judgments** are separate metrics.

Mock in this build: repositories (in-memory, simulated latency and job
polling), case analysis (a keyword matcher labelled "not AI"), roster and
cause-list data, authentication, notifications delivery.

## Next steps

1. FastAPI backend implementing `docs/api_contracts.md`; add `Api*Repository`
   classes beside the mock ones and switch providers on `AppConfig.dataMode`.
2. Vakilaj and Indian Kanoon adapters once access, terms and reuse
   permissions are confirmed; official Delhi High Court roster and cause-list
   monitoring.
3. LLM case analysis with structured outputs, redaction and evidence checks.
4. Firebase Auth / OIDC, FCM + email alerts, encrypted document storage.

## Deploying

**Website (GitHub Pages).** `.github/workflows/deploy-web.yml` runs the tests,
builds the web app and publishes it on every push to `main`. In the repository,
open Settings → Pages and set Source to "GitHub Actions" once. The site is then
at `https://<account>.github.io/<repo>/`. Everything the website needs, including
the Delhi High Court snapshot and knowledge layer in `assets/data/`, ships with
it, and uploaded judgments are read in the visitor's browser.

**Knowledge service (optional).** For full-text retrieval and AI summaries, deploy
`server/` (Docker; `render.yaml` is a Render blueprint). `knowledge.db` is too large
for git, so attach it (gzipped) to a GitHub Release and set `KNOWLEDGE_DB_URL` to the
asset's download URL; set `ANTHROPIC_API_KEY` for summaries. Then add a repository
variable `BRIEFLEE_KNOWLEDGE_URL` with the service URL so the website uses it.

**Rebuilding the data.** `tool/build_dhc_snapshot.py` builds the case snapshot from
the AWS Open Data parquet files; `tool/knowledge/harvest_texts.py` then
`tool/knowledge/build_knowledge.py` rebuild the knowledge layer and `knowledge.db`.
