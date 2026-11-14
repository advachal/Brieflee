# Brieflee: REST API contracts (v1)

Source of truth in code: `lib/core/api/api_contract.dart` (endpoints) and
`lib/core/api/brieflee_api.dart` (typed client and request DTOs). Response
bodies are the `toJson()` shapes of the models in `lib/core/models/`. All keys
are `snake_case`; enums serialise by name; dates are ISO 8601.

Long-running operations (`analyze`, `recommendations`) return a **Job** at once.
The app polls `GET /v1/jobs/{id}` (or receives a push) until `status` is
`succeeded` or `failed`; `result_id` then points at the result.

```json
// Job
{ "id": "job-123", "status": "running", "progress": 0.4,
  "step": "Searching Vakilaj adapter", "result_id": null, "error": null }
```

| Method | Endpoint | Request | Response |
| --- | --- | --- | --- |
| POST | `/v1/matters` | `CreateMatterRequest` `{title, intake_mode, description, case_number?, court_id?}` | `Matter` |
| POST | `/v1/matters/{id}/documents` | multipart: `file`, `kind` | `MatterDocument` `{id, file_name, size_bytes, kind, uploaded_at, scan_status}` |
| POST | `/v1/matters/{id}/analyze` | none | `Job` → result is the `Matter` with `analysis` |
| GET | `/v1/courts` | none | `Court[]` |
| GET | `/v1/courts/{id}/roster` | none | `RosterVersion` (current); `?history=true` adds earlier versions |
| GET | `/v1/cases/{id}/listings` | `?court_id=` | `CaseListing[]` (latest first) |
| POST | `/v1/recommendations` | `{matter_id, analysis, filters, methodology_version}` | `Job` → result id is a recommendation id |
| GET | `/v1/recommendations/{id}` | optional filter query params | `Recommendation` |
| GET | `/v1/advocates/{id}` | none | `Advocate` |
| GET | `/v1/advocates/{id}/cases` | paging, filters | `Judgment[]` |
| GET | `/v1/judgments/{id}` | none | `Judgment` (with `sources`, `passages`, `appearances`) |
| POST | `/v1/alerts` | `CreateAlertRequest` `{label, kinds[], matter_id?, court_id?}` | `AlertSubscription` |
| DELETE | `/v1/matters/{id}` | none | `204`; deletes documents, analysis, shortlist and history |
| GET | `/v1/jobs/{id}` | none | `Job` |

## Key shapes

```json
// CaseAnalysis (editable by the user; user_edited lists changed fields)
{ "court_id": "dhc", "case_category": "Trademark infringement",
  "legal_issues": ["..."], "statutes": ["Trade Marks Act, 1999 s.29"],
  "relief_sought": "...", "stage": "interimInjunction", "parties": "...",
  "case_number": "CS(COMM) 512/2026", "confidence": {"category": 0.86},
  "analyzer_label": "...", "user_edited": ["stage"] }

// SearchFilters
{ "court_id": "dhc", "categories": ["Trademark infringement"],
  "stage": null, "side": "any", "judge_ids": [], "years_back": 10,
  "min_verified_comparable": 4 }

// Judgment (one case, deduplicated; one entry per source in "sources")
{ "id": "J001", "title": "...", "citation": "...", "case_number": "...",
  "court_id": "dhc", "bench_judge_ids": ["j1"], "date": "...",
  "category": "...", "statutes": [], "stage": "interimInjunction",
  "disposition": "interimGranted", "disposition_confidence": 0.91,
  "review_status": "autoAccepted",
  "appearances": [{ "advocate_id": "a1", "side": "plaintiff", "role": "arguing",
                    "verification": "verified", "confidence": 0.93,
                    "supporting_passage_id": "J001-p1" }],
  "sources": [{ "type": "vakilaj", "url": "...", "external_id": "...",
                "retrieved_at": "...", "document_version": "v1",
                "verification": "unverified" }],
  "passages": [{ "id": "J001-p3", "paragraph": "Para 41", "text": "...",
                 "supports": "Outcome classification: ..." }],
  "summary": "...", "conflict_note": null }

// RecommendationItem (inside Recommendation.ranked / .insufficient)
{ "advocate": {...}, "score": 86.2,
  "components": { "comparable": 1.0, "forum": 1.0, "judge": 1.0,
                  "outcome": 0.66, "recency": 0.48, "role_verification": 0.87,
                  "judge_applied": true },
  "metrics": { "search_hits": 59, "mention_only": 6,
               "verified_appearance_ids": [], "comparable_ids": [],
               "forum_ids": [], "judge_ids": [], "eligible_ids": [],
               "favorable_ids": [], "unfavorable_ids": [], "mixed_ids": [],
               "excluded_ids": [] },
  "reliability": "high", "headline": "...", "reasons": [], "limitations": [],
  "insufficient": false }
```

Every count in `metrics` is a list of judgment ids, so the client can always
open the exact cases behind a number.

## Rules the backend must keep

- Query Vakilaj first, Indian Kanoon second, then verify against official
  records. A source without confirmed permission is disabled, never scraped.
- A judgment found in several repositories is one case with several `sources`.
- Official records win on conflict; the conflict is kept in `conflict_note`.
- Only eligible dispositions (final allowed/dismissed, partly allowed,
  interim granted/refused) enter outcome rates; the rest are listed as excluded.
- Every recommendation stores its `methodology_version`.
- Never return invented advocates, judgments, citations or statistics.
