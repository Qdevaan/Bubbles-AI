# Bubbles Landing Page — Design Spec

**Date:** 2026-05-09
**Author:** Brainstorming session w/ Claude
**Scope:** Marketing landing page for Bubbles (FYP-II AI conversation assistant). Next.js 15 + Tailwind + Framer Motion + shadcn/ui, deployed to Vercel.
**Out of scope:** Flutter web port, i18n, blog, pricing page, app store badges, analytics, cookie banner. (Separate specs.)

---

## 1. Goals & Audience

Hybrid landing page serving two audiences:

- **Consumer (primary):** drive waitlist signups for upcoming beta. Communicate what Bubbles does and why it's worth waiting for.
- **FYP evaluator / academic (secondary):** demonstrate technical depth, link to GitHub repo, surface architecture and stack credibility via dedicated section + `/about` page.

**Success criteria:**

- Page loads under 2.5s LCP on Vercel preview, mobile slow-3G under 4s.
- Lighthouse: 90+ desktop, 80+ mobile.
- Waitlist form submits successfully → row in Supabase `waitlist` table.
- Animations honor `prefers-reduced-motion`.
- Mobile responsive 320 → 1440px.
- WCAG AA contrast on all body/heading text.

---

## 2. Architecture & Stack

**Stack:**

- Next.js 15 (App Router) + React 19 + TypeScript 5
- Tailwind CSS v4 + shadcn/ui (button, input, accordion only)
- Framer Motion v12 (entrance, scroll-triggered, parallax, magnetic CTA)
- Lenis (smooth-scroll, reduced-motion aware)
- `cosmos-graph` or `d3-force` (memory-graph visualization)
- `@supabase/supabase-js` (server-side service-role client only)
- `zod` + `react-hook-form` (form + API validation)
- `@vercel/og` (OG image, optional)
- `canvas-confetti` (waitlist success)

**Repo location:** new `landing/` folder at repo root (monorepo style w/ existing Flutter app + `server_v2/`).

**Project tree:**

```text
landing/
├── package.json
├── next.config.ts
├── tailwind.config.ts
├── postcss.config.mjs
├── tsconfig.json
├── .env.local.example
├── public/
│   ├── logo_dark.png
│   ├── logo_light.png
│   ├── favicon.ico
│   └── og.png
├── src/
│   ├── app/
│   │   ├── layout.tsx
│   │   ├── page.tsx
│   │   ├── about/page.tsx
│   │   ├── api/waitlist/route.ts
│   │   ├── globals.css
│   │   ├── opengraph-image.tsx
│   │   ├── sitemap.ts
│   │   └── robots.ts
│   ├── components/
│   │   ├── nav.tsx
│   │   ├── hero.tsx
│   │   ├── phone-mockup.tsx
│   │   ├── modes-section.tsx
│   │   ├── try-prompt.tsx
│   │   ├── features-grid.tsx
│   │   ├── memory-graph.tsx
│   │   ├── how-it-works.tsx
│   │   ├── tech-section.tsx
│   │   ├── faq.tsx
│   │   ├── cta-waitlist.tsx
│   │   ├── footer.tsx
│   │   ├── ui/
│   │   │   ├── button.tsx
│   │   │   ├── input.tsx
│   │   │   └── accordion.tsx
│   │   └── motion/
│   │       ├── fade-up.tsx
│   │       ├── stagger.tsx
│   │       ├── parallax.tsx
│   │       ├── magnetic.tsx
│   │       └── scroll-reveal.tsx
│   ├── lib/
│   │   ├── supabase-server.ts
│   │   ├── waitlist.ts
│   │   ├── rate-limit.ts
│   │   └── utils.ts
│   └── hooks/
│       ├── use-lenis.ts
│       └── use-magnetic.ts
└── README.md
```

**Build flags:** SSG everything; `/api/waitlist` runs Node runtime; image optimization on; ESLint + TS errors fail build.

---

## 3. Visual Design

**Style:** dark glass / aurora. Premium AI aesthetic.

**Palette (locked from app logo `assets/logos/logo_dark.png`):**

| Token | Hex | Use |
|---|---|---|
| `--ink-0` | `#0a0a0f` | Page bg |
| `--ink-1` | `#13131a` | Section bg variant |
| `--ink-2` | `#1c1c26` | Card/surface base |
| `--bubbles-cyan` | `#22d3ee` | Gradient start, accent |
| `--bubbles-violet` | `#8b5cf6` | Gradient end, accent |
| `--glass-bg` | `rgba(255,255,255,0.04)` | Glass cards |
| `--glass-border` | `rgba(255,255,255,0.10)` | Glass borders |
| `--text-primary` | `#ffffff` | Headings |
| `--text-secondary` | `rgba(255,255,255,0.65)` | Body |
| `--text-muted` | `rgba(255,255,255,0.45)` | Captions |

**Primary gradient:** `linear-gradient(90deg, #22d3ee 0%, #8b5cf6 100%)`. Used on logo, headline accents, primary CTA, focused inputs.

**Aurora blobs:** two radial gradients, one cyan-tinted, one violet-tinted, animated translation 30s loop, blurred 100px+.

**Typography:**

- Headings: Geist Sans (variable), 800 weight, tight letter-spacing (`-0.04em` on hero).
- Body: Geist Sans, 400/500.
- Mono (tech section, citations): Geist Mono.
- Loaded via `next/font/google`.

**Spacing:** Tailwind defaults. Section vertical rhythm: `py-24 md:py-32`. Container max-width: `max-w-6xl` for content, `max-w-7xl` for full sections.

**Border radius:** `rounded-2xl` for cards, `rounded-full` for pills/CTAs, `rounded-3xl` for hero phone.

---

## 4. Page Sections

Single landing page (`app/page.tsx`). Top → bottom:

### 4.1 Sticky Nav

- Logo (gradient `Bubbles` text + small icon).
- Links: `Modes · Features · Tech · FAQ · GitHub`.
- CTA: `Join waitlist` (gradient pill, scrolls to bottom CTA).
- Glass blur intensifies + height shrinks past 80px scroll.
- Mobile: hamburger → slide-down panel.

### 4.2 Hero (full viewport)

Centered layout (hero option A). Symmetric, headline-first, phone peeks from bottom on scroll.

- Eyebrow pill: `⚡ Live beta` (centered, top of viewport).
- Headline: **Speak smarter.** *(gradient sweep on mount)* **In real time.** — centered, large.
- Sub: *Live wingman + consultant Q&A. Persistent memory that learns how you talk.* — centered, max-width constrained.
- CTAs: `Join waitlist →` (gradient, magnetic) + `View on GitHub` (ghost glass) — centered, side by side.
- **CSS-3D phone mockup**: positioned at bottom of viewport, peeks up ~30% on initial render, slides further into view on scroll w/ parallax. Tilted (`perspective(1200px) rotateX(8deg)`), tilts subtly toward cursor (clamped). Animated chat UI inside loops 4s (typing dots → AI suggestion bubble → fake live caption).
- Mobile (<md): phone scales down, stacks below CTAs (no peek behavior).
- Background: aurora blobs (cyan + violet, RAF translation loop) + subtle dot grid overlay.

### 4.3 Modes Section

Heading: *"Three modes. One assistant."*

Three sticky-scroll panels (scroll-pinned storytelling):

1. **Wingman** — *"In your ear, mid-conversation. Without sounding like a robot."* Mockup: live caption + ghosted AI suggestion fading in.
2. **Consultant** — *"Deep Q&A with memory you can audit."* Mockup: streaming response + citation chips.
3. **Voice** — *"Just say 'Hey Bubbles' — we handle the awkward parts."* Mockup: waveform pulse + intent badge.

Implementation: outer `100vh × 3` container, inner content `position: sticky; top: 0`, panel index driven by `useScroll` progress.

### 4.4 Try a Prompt (interactive)

- Glass input: `Ask Bubbles anything…` + 3 suggestion chips.
- On submit: client-side mocked typewriter response (8ms/char) + citation chip slide-in + "memory updated" toast.
- Pure client-side; no backend hit. Canned responses keyed to chips.
- Demonstrates streaming feel.

### 4.5 Features Grid

Bento layout, 6 cards (2 large, 4 small):

1. **Memory graph** (large) — entities/relations across sessions.
2. **Session analytics** (small) — sentiment, turn-level metrics.
3. **Voice enrollment** (small) — speaker embedding for personalization.
4. **Multi-platform** (large) — Android, iOS, Web, Desktop.
5. **Live captions** (small) — real-time transcription.
6. **Privacy-first** (small) — your data, your control.

Each card: icon, 2-line copy, hover lift + accent glow.

### 4.6 Memory Graph Visualization

- Tagline: *"Bubbles remembers what you said. And who you said it to."*
- Force-directed graph (cosmos-graph), ~30 fake nodes (people / topics / events) + edges.
- Auto-rotates slowly. Hover node → glow halo + tooltip.
- Lazy-loaded via `next/dynamic({ ssr: false })`, suspended w/ skeleton.
- `aria-hidden="true"` (decorative).

### 4.7 How It Works

4-step animated flow: `Speak → Transcribe → Reason → Suggest`.

- SVG path connecting steps; `stroke-dashoffset` animates 100% → 0% as section enters viewport.
- Step icons translate along path.
- Each step has 1-line caption.

### 4.8 Tech / About

Two-column section (md+), stacked on mobile.

- Left: stack chips — `Flutter` `FastAPI` `Supabase` `LiveKit` `Groq` `sentence-transformers` `networkx` `Provider` `Docker`. Stagger fade-up.
- Right: simplified architecture sketch (SVG, lines draw on viewport): client → API → LLM/embeddings/graph → storage.
- Below: short blurb + CTAs `View on GitHub` + `Read tech deep-dive →` (links to `/about`).

### 4.9 FAQ

6 questions, framer-motion accordion (`AnimatePresence` height auto):

1. When can I use Bubbles?
2. Is it free?
3. Which platforms are supported?
4. How do you handle privacy?
5. How does voice work?
6. Can I see the source code?

### 4.10 CTA / Waitlist

- Full-width band, gradient bg slowly shifts hue.
- Big headline: *"Be early. Speak smarter."*
- Email input + `Join waitlist` button.
- Success: confetti burst + checkmark + *"You're in. Check your inbox."* (no email actually sent yet — message is aspirational; see Open Questions).
- Secondary: `GitHub →`.

### 4.11 Footer

- Logo + tagline.
- Links: Privacy · Terms · GitHub · Email.
- Copyright + `Made for FYP-II 2026`.

### 4.12 `/about` page

Longer-form technical write-up:

- Project context (FYP-II, problem statement, motivation).
- Architecture diagram (full).
- Stack rationale.
- Demo screenshots (when available).
- FYP report PDF link (`Documentation/FYP-I Report-v3.2.pdf`).
- GitHub link.
- Acknowledgments.

---

## 5. Animation Strategy

**Lenis smooth-scroll** wraps body. Disabled if `prefers-reduced-motion: reduce`.

**Motion primitives** in `components/motion/`:

| Primitive | Behavior |
|---|---|
| `<FadeUp>` | opacity 0→1, y +24→0, viewport-enter once |
| `<Stagger>` | sequential children w/ 0.06s delay step |
| `<Parallax speed={0.3}>` | translateY based on scroll progress |
| `<Magnetic>` | CTA cursor-attraction within ~80px (desktop, no-touch) |
| `<ScrollReveal>` | generic IntersectionObserver wrapper |

**Per-section motion:**

| Section | Motion |
|---|---|
| Nav | Glass blur + height shrink past 80px |
| Hero | Aurora blobs (RAF loop, 30s), headline gradient sweep, CTAs magnetic, 3D phone peek-up parallax on scroll + tilts toward cursor + inner UI 4s loop |
| Modes | Sticky-scroll storytelling, panel index driven by `useScroll` |
| Try a prompt | Typewriter (8ms/char), chip slide-in, toast slide-up |
| Features grid | Stagger fade-up, hover lift + glow |
| Memory graph | Auto-rotation, edges fade-in 2s on first viewport, hover halo |
| How it works | SVG `stroke-dashoffset` 100→0 on viewport |
| Tech | Stack chips stagger, sketch lines draw |
| FAQ | Accordion height auto via `AnimatePresence` |
| CTA waitlist | Bg gradient hue-shift, success confetti |

**Cursor effect** (desktop only, ~30 lines, no library):

- Custom cursor: dot + ring, ring lerps to dot. Ring grows on hoverable elements.
- Hidden if `prefers-reduced-motion: reduce` or touch device.

**Performance guards:**

- `will-change` only during active animation, removed after.
- `IntersectionObserver` `rootMargin: -10%` to defer off-screen work.
- Memory graph + cosmos-graph lazy-loaded `ssr: false`.
- Lenis pauses on `visibilitychange` hidden.

---

## 6. Data Flow — Waitlist

### 6.1 Supabase Schema

```sql
create table public.waitlist (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  source text default 'landing',
  user_agent text,
  referrer text,
  created_at timestamptz not null default now()
);

create unique index waitlist_email_lower_idx on public.waitlist (lower(email));

alter table public.waitlist enable row level security;
revoke all on public.waitlist from anon, authenticated;
-- Service-role bypasses RLS, used server-side only.
```

Migration file: `server_v2/migrations/2026-05-09_waitlist.sql` (or wherever existing migrations live — TBD by writer of plan).

### 6.2 API: `POST /api/waitlist`

- Runtime: Node (needs `SUPABASE_SERVICE_ROLE_KEY`).
- Body: `{ email: string }`.
- Validation: `z.string().email().max(254).toLowerCase()`.
- Honeypot field `company` — non-empty → `200 { ok: true }` (silent drop).
- Rate-limit: in-memory LRU per IP, `5 req / 10 min` (`lib/rate-limit.ts`).
- Insert via service-role client.
- On unique violation → `200 { ok: true, already: true }`.
- On success → `200 { ok: true }`.
- On invalid email → `400 { error: "invalid_email" }`.
- On other errors → `500 { error: "server" }`.
- Captures `user_agent` (header), `referrer` (header) for source attribution.

### 6.3 Client Form (`cta-waitlist.tsx`)

- `react-hook-form` + zod resolver.
- Hidden honeypot `<input name="company" tabIndex={-1} aria-hidden="true">`.
- States: idle → submitting → success → error.
- After success: `localStorage.setItem('bubbles_waitlist', '1')` to skip form on revisit (replace w/ thank-you state).

### 6.4 Env Vars

Set in Vercel project settings:

- `NEXT_PUBLIC_SUPABASE_URL` — public.
- `SUPABASE_SERVICE_ROLE_KEY` — server-only, encrypted.
- `NEXT_PUBLIC_SITE_URL` — for OG/canonical.

`.env.local.example` committed; `.env.local` gitignored.

### 6.5 Privacy

- Email only. No tracking pixels, no analytics, no cookies.
- Cookie banner unnecessary at launch.

---

## 7. Deployment

**Vercel:**

- Project root: `landing/` (set in Project Settings → Root Directory).
- Framework: Next.js (auto).
- Node version: 20.x.
- Build: `next build`.
- Install: `npm install` (or `pnpm install` if `pnpm-lock.yaml` present).
- Domain: default `bubbles-ai.vercel.app` (or whatever Vercel assigns). Custom domain deferred.
- Branch: `main` → production. PRs → preview deploys.

**CI:** Vercel preview is the gate — `next lint` + `tsc --noEmit` run during build, fail build on errors. No separate GH Action initially.

**Pre-deploy manual checklist:**

- [ ] Lighthouse desktop ≥ 90, mobile ≥ 80.
- [ ] Mobile responsive at 320 / 375 / 414 / 768 / 1024 / 1440.
- [ ] Reduced-motion mode: animations disabled, page still readable.
- [ ] Slow-3G test (Chrome DevTools).
- [ ] Form submits → row in Supabase `waitlist`.
- [ ] OG image renders on Twitter/Facebook debugger.
- [ ] Keyboard nav full tab order.
- [ ] No console errors / warnings in production build.

---

## 8. SEO & Metadata

- `title`: *Bubbles — Speak smarter. In real time.*
- `description`: *AI conversation copilot with live wingman, deep Q&A, voice control, and memory that learns how you talk.*
- OG image: static `/og.png` (1200×630) initially; dynamic `opengraph-image.tsx` if needed.
- Twitter card: `summary_large_image`.
- `robots.ts`: allow all, sitemap reference.
- `sitemap.ts`: `/`, `/about`.
- Favicon derived from `logo_dark.png`.
- Canonical URL via `NEXT_PUBLIC_SITE_URL`.

---

## 9. Accessibility

- Semantic HTML (`<header>`, `<main>`, `<nav>`, `<section>`, `<footer>`).
- Skip-link to main content.
- All interactive elements keyboard-accessible w/ visible focus rings (`focus-visible`).
- Form: labels, `aria-describedby` for errors.
- Color contrast: WCAG AA min on body/heading (white on `#0a0a0f` = 19.5:1).
- Animations honor `prefers-reduced-motion: reduce`.
- Memory graph: `aria-hidden="true"` (decorative).
- Custom cursor disabled on touch + reduced-motion.

---

## 10. Testing

Lightweight scope (marketing page):

- **Unit (vitest):** `lib/waitlist.ts` zod schema (~5 tests: valid, invalid format, too long, mixed case normalization, empty).
- **Route (vitest + direct fetch):** `/api/waitlist` happy path, invalid email, rate-limit trip, duplicate insert, honeypot trap.
- **E2E:** skipped initially. Add Playwright smoke test only if landing grows.
- **Manual:** pre-deploy checklist (section 7).

---

## 11. Components — Public Interfaces

Each component file exports a single default React component. Boundaries are kept tight so each can be modified without touching the others.

| Component | Props | Responsibility |
|---|---|---|
| `<Nav>` | none | Sticky nav, scroll behavior |
| `<Hero>` | none | Hero copy + CTAs + phone mockup |
| `<PhoneMockup>` | `loop?: boolean` | CSS-3D phone shell w/ animated chat UI |
| `<ModesSection>` | none | Sticky-scroll 3 modes |
| `<TryPrompt>` | none | Mocked interactive prompt widget |
| `<FeaturesGrid>` | none | Bento grid of 6 features |
| `<MemoryGraph>` | none | Force-directed graph, lazy-loaded |
| `<HowItWorks>` | none | 4-step animated SVG flow |
| `<TechSection>` | none | Stack chips + architecture sketch |
| `<Faq>` | none | Accordion |
| `<CtaWaitlist>` | none | Email form + success state |
| `<Footer>` | none | Static |
| `<FadeUp>` | `delay?, y?` + children | Entrance animation wrapper |
| `<Stagger>` | `step?` + children | Sequential children animator |
| `<Parallax>` | `speed?` + children | Scroll-driven translate |
| `<Magnetic>` | `radius?` + children | Cursor-attraction wrapper |

All sections are independent: no cross-component state shared except theme (CSS vars) and Lenis instance (context provider in root layout).

---

## 12. Open Questions / Deferred

- **Waitlist confirmation email:** form success says *"Check your inbox"* but no email is sent at launch. Either (a) update copy to *"You're in. We'll email when beta opens."* (recommended), or (b) wire Resend / Supabase Edge Function later. Recommend option (a) at launch.
- **GitHub repo URL:** not yet confirmed in spec. Implementation plan should fill in actual URL or leave as `NEXT_PUBLIC_GITHUB_URL` env.
- **`/about` content depth:** stub on first ship; expand iteratively.
- **Logo `Bubbles` text mark:** wordmark not yet in `assets/logos/`; need to either generate gradient text in CSS (chosen here) or commission/render an SVG wordmark later.
- **Migration location:** spec assumes `server_v2/migrations/`; planner to confirm against existing migration convention before placing.
- **Custom domain:** deferred. Document setup steps in implementation plan for future.

---

## 13. Decisions Locked

- Stack: Next.js 15 + Tailwind v4 + Framer Motion v12 + shadcn/ui (minimal).
- Visual style: dark glass / aurora.
- Hero layout: centered gradient headline w/ CSS-3D phone peeking from bottom of viewport, parallax on scroll.
- Sections: hero → modes → try-prompt → features → memory graph → how it works → tech → FAQ → waitlist CTA → footer + `/about`.
- CTAs: waitlist (primary) + GitHub (secondary).
- Animation: heavy — Framer Motion + scroll-trigger + parallax + cursor + Lenis.
- Hero mockup: CSS-3D phone w/ animated chat UI (no Three.js).
- Demo replacement: interactive try-prompt + memory graph viz (no video).
- Tone: confident + playful.
- Palette: cyan `#22d3ee` → violet `#8b5cf6` on near-black `#0a0a0f` (matched from app logo).
- Waitlist: Supabase table on existing project, server-side service-role insert, in-memory rate-limit.
- Domain: Vercel default subdomain initially.
- Repo location: `landing/` at repo root.
