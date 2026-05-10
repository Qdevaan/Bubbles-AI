# Bubbles — Server & App Optimization Plan

Date: 2026-05-10
Owner: Muhammad Ahmad
Status: planning + first delivery (this branch)

This document records the optimization items that came in as a single batched
todo list and what was actioned in the `feat/todo-batch-improvements` branch.

## What shipped on this branch

| # | Item | Where |
| --- | --- | --- |
| 2 | Robust client-side entity extraction (fuzzy match + neighbour promotion + relevance score) | `lib/screens/graph_explorer_screen.dart` `_extractGraphEntities` |
| 3 | Performa wizard redesign (ambient bg, modern header, progress bar, branded actions) | `lib/screens/performa/performa_wizard_screen.dart` |
| 4 / 7 | First perf pass: `RepaintBoundary` around the global ambient orb animation so 60Hz repaints don't invalidate the rest of the tree | `lib/widgets/animated_background.dart` |
| 5 / 6 | No more startup permission carpet-bomb. New `PermissionsUtil.ensure(...)` API to request only what a feature needs, when it's needed. Splash + login no longer call the bulk requester | `lib/utils/permissions_util.dart`, `splash_screen.dart`, `login_screen.dart` |
| 8 | Settings screen no longer pixel-overflows on small devices (Column+Spacer → SingleChildScrollView) | `lib/screens/settings_screen.dart` |
| 9 | Live streaming chat in consultant: typing dots while waiting for first token + blinking cursor while streaming, on top of the existing SSE backend | `lib/widgets/consultant/consultant_widgets.dart` |
| 10 | Roleplay voice feedback: VoiceAssistantService emits medium-impact haptic when AI starts speaking and a selection-click when it stops, gated to roleplay sessions | `lib/services/voice_assistant_service.dart`, `lib/screens/new_session_screen.dart` |
| 11 | Graph QA now sends `mode=entity_focused` + a `prompt_hint` instructing the LLM to ground answers in the extracted entities | `lib/services/api_service.dart` `askGraphQuery` |
| 12 | Performa view/edit screen in Settings (links into existing wizard `editMode`) | `lib/screens/settings_performa_screen.dart`, settings tile, route |
| 13 | Uniform `AppDialog` widget with tone variants, header icon, action row + `confirm` / `notice` helpers — drop-in replacement for ad-hoc `showDialog` calls | `lib/widgets/app_dialog.dart` |
| 14 | Graph search bar restyled: glass pill with gradient AI orb, animated focus glow, gradient submit button, clear button | `lib/screens/graph_explorer_screen.dart` `_GraphQueryBar` |

## Item 1 — Server optimization (lives in the sibling repo)

The Flutter client only consumes the server; the server source is in the
sibling FastAPI repo. The plan below is what to apply there before the next
release.

### Hot endpoints to profile first

These are the endpoints with the worst latency observed from the mobile
client (median p50 from `ApiService` debug logs over the last week of dev):

1. `POST /v1/ask_consultant_stream` — SSE consultant chat. p50 ~2.4s before
   first token. Target: ≤ 800ms.
2. `POST /v1/ask` (`context=knowledge_graph`) — graph QA. p50 ~3.1s.
3. `GET /v1/graph_export/{user_id}` — knowledge graph export. p50 ~1.8s on
   medium graphs (~400 nodes), ~6s on heavy (>2k nodes).
4. `POST /v1/start_live_session` / `POST /v1/end_live_session` — roleplay /
   wingman. Mostly DB-bound; tail latency from sequential writes.
5. `GET /v1/insights/*` — aggregated dashboards; doing per-row Python work.

### Recommended changes (priority order)

1. **First-token latency for consultant streaming**
   - Stream the model's tokens through the SSE pipe as soon as the first
     chunk arrives. Avoid `await` on the full prompt build; do retrieval and
     persona composition in parallel with the user's request reaching the
     model (Asyncio `gather`).
   - Cap retrieval payload to top-N entity facts; the client now sends
     `graph_entities` (item #11) so the server can skip its own retrieval
     when the client has already narrowed it down.

2. **Move entity extraction off the request path**
   - Run extraction in a background worker on session/transcript ingest, not
     on every `/v1/ask`. Persist `entities`, `mentions`, and edges so
     `/v1/ask` only does a graph read.
   - Where extraction must run online, swap the LLM call for a faster
     extractor (regex + spaCy NER + small classifier) and only invoke the
     LLM on ambiguous cases.

3. **Graph export caching**
   - ETag the export by `(user_id, max(updated_at))` over `entities` +
     `entity_relations`. The client repository already supports SWR; honour
     the ETag to allow `304 Not Modified`.
   - Pre-compute the layout positions server-side once per write so the
     Flutter WebView doesn't pay layout cost every cold open.

4. **DB indexes**
   - `entities (user_id, entity_type)` — used by roleplay setup query and
     graph filters.
   - `entity_relations (user_id, source_id)` and `(user_id, target_id)` —
     graph traversal both ways.
   - `messages (session_id, created_at desc)` — chat history fetch.
   - `mistakes (user_id, created_at desc)` — analytics tab.
   - Verify all the above are present and used (`EXPLAIN ANALYZE` from
     prod-shaped data).

5. **Connection pooling and async I/O**
   - Reuse a single `httpx.AsyncClient` for outbound LLM/Deepgram calls;
     don't open a new one per request.
   - Use `asyncpg` (or SQLAlchemy async) end-to-end. Any sync DB call on the
     hot path defeats the FastAPI worker model.

6. **Compression and payload diet**
   - Enable gzip/br on FastAPI (`GZipMiddleware`).
   - Trim graph export to only fields used by the client (`id`, `label`,
     `type`, `mention_count`, edges with `relation`). Drop debug/trace
     fields in prod.

7. **Observability**
   - Add `X-Server-Timing: db;dur=…, llm;dur=…, retrieve;dur=…` so the app
     can log per-stage latency without server-side digging.
   - Sentry breadcrumb every >1s endpoint. Sample 10% of requests for full
     traces.

8. **Rate-limit + queue the heavy stuff**
   - Quest issuance, daily insights aggregation, and graph rebuilds belong
     on a Celery/RQ queue, not in request handlers.

## Item 4 / 7 — App optimization beyond this PR

The first-pass `RepaintBoundary` win is in. Follow-up work tracked here:

- Audit eager `ListView(children: …)` instances in:
  `data_management_screen.dart`, `entity_screen.dart`,
  `game_center_screen.dart`, `graph_explorer_screen.dart`,
  `home_screen.dart`, `quests_screen.dart`,
  `session_analytics_screen.dart`. Convert any with > 20 children to
  `ListView.builder`.
- `cached_network_image` is in `pubspec.yaml`; verify all profile and
  entity avatar usages go through it (no raw `NetworkImage`).
- Wrap the live-session `WebView` and `force_directed_graphview` in
  `RepaintBoundary`.
- Add `const` constructors aggressively (run `flutter analyze --no-fatal-infos`
  with `prefer_const_constructors` enforced; CI gate).
- Defer non-critical providers (gamification, insights) until after first
  meaningful paint to shave splash → home time.
- Consider `flutter_displaymode` or a lightweight equivalent so 90/120Hz
  panels actually run at native rate — animations look choppy on Pixel and
  OnePlus devices today.

## Item 3 — Performa redesign (continued)

Wizard chrome (header, progress, actions) is now branded. Step pages are
still using stock Flutter inputs. Next pass should:

- Replace `Step1Identity` / `Step2Language` / `Step3Goals` form fields with
  `AppCard` + the same input style as `widgets/app_input.dart`.
- Use chip pickers for `expertiseTags`, `communicationStyle`, `primaryGoals`,
  `typicalScenarios` — currently free-form text.
- Add a final "review" step that mirrors `SettingsPerformaScreen` so the
  user sees what they're committing.

Tracked as a follow-up; doesn't block this branch.
