# Bubbles Landing Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build, test, and deploy a marketing landing page for Bubbles (Next.js 15 + Framer Motion + Tailwind + Supabase waitlist) at `E:\FYP\FYP_V2\Bubbles-AI-landing` as a separate sibling repo, deployed to Vercel.

**Architecture:** Single-page SSG landing on Next.js App Router, dark glass / aurora style, heavy Framer Motion choreography (Lenis smooth-scroll, scroll-triggered reveals, sticky-scroll storytelling, magnetic CTAs, custom cursor). Waitlist email captured by a Node-runtime API route inserting into a Supabase `waitlist` table via service-role key. Dedicated `/about` page for FYP-evaluator audience.

**Tech Stack:** Next.js 15, React 19, TypeScript 5, Tailwind CSS v4, Framer Motion v12, shadcn/ui (minimal), Lenis, cosmos-graph, @supabase/supabase-js, zod, react-hook-form, canvas-confetti, vitest.

**Reference spec:** `E:\FYP\FYP_V2\Bubbles-AI\docs\superpowers\specs\2026-05-09-bubbles-landing-design.md`

**Working directory for all tasks:** `E:\FYP\FYP_V2\Bubbles-AI-landing` (created in Task 1).

---

## File Structure

```text
Bubbles-AI-landing/
├── .gitignore
├── .env.local.example
├── README.md
├── package.json
├── tsconfig.json
├── next.config.ts
├── tailwind.config.ts
├── postcss.config.mjs
├── eslint.config.mjs
├── vitest.config.ts
├── components.json                       # shadcn config
├── migrations/
│   └── 2026-05-09_waitlist.sql
├── public/
│   ├── logo_dark.png
│   ├── logo_light.png
│   ├── favicon.ico
│   └── og.png
├── src/
│   ├── app/
│   │   ├── layout.tsx
│   │   ├── page.tsx
│   │   ├── globals.css
│   │   ├── sitemap.ts
│   │   ├── robots.ts
│   │   ├── about/
│   │   │   └── page.tsx
│   │   └── api/
│   │       └── waitlist/
│   │           └── route.ts
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
│   │   ├── cursor.tsx
│   │   ├── lenis-provider.tsx
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
│   │   ├── prefers-reduced-motion.ts
│   │   └── utils.ts
│   ├── hooks/
│   │   ├── use-magnetic.ts
│   │   └── use-mounted.ts
│   └── test/
│       ├── waitlist.test.ts
│       ├── rate-limit.test.ts
│       └── api-waitlist.test.ts
```

**Decomposition rationale:** every section is its own component file (`hero.tsx`, `modes-section.tsx`, etc.) so they can be edited independently without grep-jumping a 1000-line page. Motion primitives live under `motion/` and are reused across sections. Server-only Supabase code is isolated in `lib/supabase-server.ts` so the service-role key cannot accidentally leak into client bundles.

---

## Task 1: Initialize sibling repo + Next.js scaffold

**Files:**
- Create: `E:\FYP\FYP_V2\Bubbles-AI-landing\` (whole repo)

- [ ] **Step 1: Create sibling directory**

```powershell
cd E:\FYP\FYP_V2
mkdir Bubbles-AI-landing
cd Bubbles-AI-landing
```

- [ ] **Step 2: Scaffold Next.js 15 project**

Run (accept all interactive prompts via flags):

```powershell
npx --yes create-next-app@15 . `
  --typescript `
  --tailwind `
  --eslint `
  --app `
  --src-dir `
  --import-alias "@/*" `
  --no-turbopack `
  --use-npm
```

Expected: scaffold completes, `package.json`, `src/app/`, `tailwind.config.ts`, `tsconfig.json` created.

- [ ] **Step 3: Initialize git repo (if not already by create-next-app)**

```powershell
git status
```

If `not a git repository`, run:

```powershell
git init -b main
```

Otherwise skip.

- [ ] **Step 4: First commit**

```powershell
git add -A
git commit -m "chore: initial Next.js 15 scaffold via create-next-app"
```

Expected: commit succeeds.

---

## Task 2: Add core dependencies

**Files:**
- Modify: `package.json`

- [ ] **Step 1: Install runtime dependencies**

```powershell
npm install framer-motion@^12 @supabase/supabase-js@^2 zod@^3 react-hook-form@^7 @hookform/resolvers@^3 lenis@^1 cosmos-graph@^1 canvas-confetti@^1 clsx@^2 tailwind-merge@^2
```

- [ ] **Step 2: Install dev dependencies**

```powershell
npm install -D vitest@^2 @vitest/ui@^2 jsdom@^25 @types/canvas-confetti @types/node
```

- [ ] **Step 3: Verify install**

```powershell
npm ls framer-motion lenis @supabase/supabase-js
```

Expected: each package resolves to a single version with no `UNMET` markers.

- [ ] **Step 4: Commit**

```powershell
git add package.json package-lock.json
git commit -m "chore: install framer-motion, supabase, lenis, cosmos-graph and tooling"
```

---

## Task 3: Add `.env.local.example` and update `.gitignore`

**Files:**
- Create: `.env.local.example`
- Modify: `.gitignore`

- [ ] **Step 1: Write `.env.local.example`**

```dotenv
# Public Supabase URL (browser-safe)
NEXT_PUBLIC_SUPABASE_URL=https://<project>.supabase.co

# Service-role key — SERVER-ONLY. Never import in client code.
SUPABASE_SERVICE_ROLE_KEY=eyJhbGci...

# Public site URL for OG/canonical
NEXT_PUBLIC_SITE_URL=https://bubbles-ai.vercel.app

# Optional: GitHub repo URL exposed in CTAs
NEXT_PUBLIC_GITHUB_URL=https://github.com/Qdevaan/Bubbles-AI
```

- [ ] **Step 2: Append to `.gitignore`**

Append these lines (do not duplicate existing entries):

```gitignore

# Local env
.env.local
.env*.local

# Vitest
coverage/
```

- [ ] **Step 3: Commit**

```powershell
git add .env.local.example .gitignore
git commit -m "chore: add env example and ignore local env / coverage"
```

---

## Task 4: Configure Tailwind v4 tokens + globals

**Files:**
- Modify: `tailwind.config.ts`
- Modify: `src/app/globals.css`

- [ ] **Step 1: Replace `tailwind.config.ts`**

```ts
import type { Config } from "tailwindcss";

export default {
  content: ["./src/**/*.{ts,tsx,mdx}"],
  theme: {
    extend: {
      colors: {
        ink: {
          0: "#0a0a0f",
          1: "#13131a",
          2: "#1c1c26",
        },
        bubbles: {
          cyan: "#22d3ee",
          violet: "#8b5cf6",
        },
        glass: {
          bg: "rgba(255,255,255,0.04)",
          border: "rgba(255,255,255,0.10)",
        },
      },
      fontFamily: {
        sans: ["var(--font-geist-sans)", "system-ui", "sans-serif"],
        mono: ["var(--font-geist-mono)", "ui-monospace", "monospace"],
      },
      backgroundImage: {
        "bubbles-gradient":
          "linear-gradient(90deg, #22d3ee 0%, #8b5cf6 100%)",
      },
      letterSpacing: {
        tightest: "-0.04em",
      },
      keyframes: {
        "aurora-drift": {
          "0%, 100%": { transform: "translate3d(0,0,0)" },
          "50%": { transform: "translate3d(40px,-30px,0)" },
        },
        "gradient-sweep": {
          "0%": { backgroundPosition: "0% 50%" },
          "100%": { backgroundPosition: "200% 50%" },
        },
      },
      animation: {
        "aurora-drift": "aurora-drift 30s ease-in-out infinite",
        "gradient-sweep": "gradient-sweep 6s linear infinite",
      },
    },
  },
  plugins: [],
} satisfies Config;
```

- [ ] **Step 2: Replace `src/app/globals.css`**

```css
@import "tailwindcss";

:root {
  --ink-0: #0a0a0f;
  --ink-1: #13131a;
  --ink-2: #1c1c26;
  --bubbles-cyan: #22d3ee;
  --bubbles-violet: #8b5cf6;
  --glass-bg: rgba(255, 255, 255, 0.04);
  --glass-border: rgba(255, 255, 255, 0.10);
}

html,
body {
  background: var(--ink-0);
  color: #fff;
  -webkit-font-smoothing: antialiased;
  text-rendering: optimizeLegibility;
}

body {
  overflow-x: hidden;
}

::selection {
  background: var(--bubbles-violet);
  color: #fff;
}

.text-gradient {
  background: linear-gradient(90deg, var(--bubbles-cyan), var(--bubbles-violet));
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}

.glass {
  background: var(--glass-bg);
  border: 1px solid var(--glass-border);
  backdrop-filter: blur(20px);
  -webkit-backdrop-filter: blur(20px);
}

@media (prefers-reduced-motion: reduce) {
  *,
  *::before,
  *::after {
    animation-duration: 0.001ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.001ms !important;
    scroll-behavior: auto !important;
  }
}
```

- [ ] **Step 3: Run dev server smoke check**

```powershell
npm run dev
```

Expected: `http://localhost:3000` renders the default Next.js page on a black background w/ no console errors. Stop server (Ctrl-C).

- [ ] **Step 4: Commit**

```powershell
git add tailwind.config.ts src/app/globals.css
git commit -m "feat: add bubbles tailwind tokens and dark/glass globals"
```

---

## Task 5: Add `lib/utils.ts` and reduced-motion helper

**Files:**
- Create: `src/lib/utils.ts`
- Create: `src/lib/prefers-reduced-motion.ts`

- [ ] **Step 1: Write `src/lib/utils.ts`**

```ts
import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
```

- [ ] **Step 2: Write `src/lib/prefers-reduced-motion.ts`**

```ts
"use client";

import { useEffect, useState } from "react";

export function usePrefersReducedMotion(): boolean {
  const [reduced, setReduced] = useState(false);

  useEffect(() => {
    if (typeof window === "undefined") return;
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    setReduced(mq.matches);
    const onChange = (e: MediaQueryListEvent) => setReduced(e.matches);
    mq.addEventListener("change", onChange);
    return () => mq.removeEventListener("change", onChange);
  }, []);

  return reduced;
}
```

- [ ] **Step 3: Commit**

```powershell
git add src/lib/utils.ts src/lib/prefers-reduced-motion.ts
git commit -m "feat: add cn utility and prefers-reduced-motion hook"
```

---

## Task 6: Add Lenis provider

**Files:**
- Create: `src/components/lenis-provider.tsx`

- [ ] **Step 1: Write `src/components/lenis-provider.tsx`**

```tsx
"use client";

import { useEffect } from "react";
import Lenis from "lenis";
import { usePrefersReducedMotion } from "@/lib/prefers-reduced-motion";

export function LenisProvider({ children }: { children: React.ReactNode }) {
  const reduced = usePrefersReducedMotion();

  useEffect(() => {
    if (reduced) return;
    const lenis = new Lenis({
      duration: 1.1,
      smoothWheel: true,
    });

    let rafId = 0;
    function raf(time: number) {
      lenis.raf(time);
      rafId = requestAnimationFrame(raf);
    }
    rafId = requestAnimationFrame(raf);

    const onVisibility = () => {
      if (document.hidden) lenis.stop();
      else lenis.start();
    };
    document.addEventListener("visibilitychange", onVisibility);

    return () => {
      cancelAnimationFrame(rafId);
      document.removeEventListener("visibilitychange", onVisibility);
      lenis.destroy();
    };
  }, [reduced]);

  return <>{children}</>;
}
```

- [ ] **Step 2: Commit**

```powershell
git add src/components/lenis-provider.tsx
git commit -m "feat: add Lenis smooth-scroll provider with reduced-motion bypass"
```

---

## Task 7: Add motion primitives

**Files:**
- Create: `src/components/motion/fade-up.tsx`
- Create: `src/components/motion/stagger.tsx`
- Create: `src/components/motion/parallax.tsx`
- Create: `src/components/motion/magnetic.tsx`
- Create: `src/components/motion/scroll-reveal.tsx`
- Create: `src/hooks/use-magnetic.ts`

- [ ] **Step 1: Write `src/components/motion/fade-up.tsx`**

```tsx
"use client";

import { motion, type HTMLMotionProps } from "framer-motion";

type Props = HTMLMotionProps<"div"> & {
  delay?: number;
  y?: number;
};

export function FadeUp({ children, delay = 0, y = 24, ...rest }: Props) {
  return (
    <motion.div
      initial={{ opacity: 0, y }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-10% 0px" }}
      transition={{ duration: 0.6, delay, ease: [0.22, 1, 0.36, 1] }}
      {...rest}
    >
      {children}
    </motion.div>
  );
}
```

- [ ] **Step 2: Write `src/components/motion/stagger.tsx`**

```tsx
"use client";

import { motion, type HTMLMotionProps } from "framer-motion";

type Props = HTMLMotionProps<"div"> & {
  step?: number;
};

export function Stagger({ children, step = 0.06, ...rest }: Props) {
  return (
    <motion.div
      initial="hidden"
      whileInView="visible"
      viewport={{ once: true, margin: "-10% 0px" }}
      variants={{
        hidden: {},
        visible: { transition: { staggerChildren: step } },
      }}
      {...rest}
    >
      {children}
    </motion.div>
  );
}

export const staggerItem = {
  hidden: { opacity: 0, y: 16 },
  visible: { opacity: 1, y: 0, transition: { duration: 0.5 } },
};
```

- [ ] **Step 3: Write `src/components/motion/parallax.tsx`**

```tsx
"use client";

import { motion, useScroll, useTransform } from "framer-motion";
import { useRef } from "react";

type Props = {
  children: React.ReactNode;
  speed?: number; // 0 = static, 1 = full scroll travel
  className?: string;
};

export function Parallax({ children, speed = 0.3, className }: Props) {
  const ref = useRef<HTMLDivElement | null>(null);
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ["start end", "end start"],
  });
  const y = useTransform(scrollYProgress, [0, 1], [0, -200 * speed]);

  return (
    <motion.div ref={ref} style={{ y }} className={className}>
      {children}
    </motion.div>
  );
}
```

- [ ] **Step 4: Write `src/hooks/use-magnetic.ts`**

```ts
"use client";

import { useEffect, useRef } from "react";
import { usePrefersReducedMotion } from "@/lib/prefers-reduced-motion";

export function useMagnetic<T extends HTMLElement>(radius = 80, strength = 0.35) {
  const ref = useRef<T | null>(null);
  const reduced = usePrefersReducedMotion();

  useEffect(() => {
    const el = ref.current;
    if (!el || reduced) return;

    const isTouch = window.matchMedia("(pointer: coarse)").matches;
    if (isTouch) return;

    let raf = 0;
    function onMove(e: MouseEvent) {
      const rect = el!.getBoundingClientRect();
      const cx = rect.left + rect.width / 2;
      const cy = rect.top + rect.height / 2;
      const dx = e.clientX - cx;
      const dy = e.clientY - cy;
      const dist = Math.hypot(dx, dy);
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(() => {
        if (dist < radius) {
          const factor = (1 - dist / radius) * strength;
          el!.style.transform = `translate(${dx * factor}px, ${dy * factor}px)`;
        } else {
          el!.style.transform = "";
        }
      });
    }

    function onLeave() {
      el!.style.transform = "";
    }

    window.addEventListener("mousemove", onMove);
    el.addEventListener("mouseleave", onLeave);

    return () => {
      window.removeEventListener("mousemove", onMove);
      el?.removeEventListener("mouseleave", onLeave);
      cancelAnimationFrame(raf);
    };
  }, [radius, strength, reduced]);

  return ref;
}
```

- [ ] **Step 5: Write `src/components/motion/magnetic.tsx`**

```tsx
"use client";

import { useMagnetic } from "@/hooks/use-magnetic";

type Props = {
  children: React.ReactNode;
  radius?: number;
  className?: string;
};

export function Magnetic({ children, radius = 80, className }: Props) {
  const ref = useMagnetic<HTMLDivElement>(radius);
  return (
    <div ref={ref} className={className} style={{ transition: "transform 0.2s ease-out" }}>
      {children}
    </div>
  );
}
```

- [ ] **Step 6: Write `src/components/motion/scroll-reveal.tsx`**

```tsx
"use client";

import { motion, useInView } from "framer-motion";
import { useRef } from "react";

type Props = {
  children: React.ReactNode;
  className?: string;
};

export function ScrollReveal({ children, className }: Props) {
  const ref = useRef<HTMLDivElement | null>(null);
  const inView = useInView(ref, { once: true, margin: "-10% 0px" });

  return (
    <motion.div
      ref={ref}
      animate={inView ? { opacity: 1, y: 0 } : { opacity: 0, y: 20 }}
      transition={{ duration: 0.6, ease: [0.22, 1, 0.36, 1] }}
      className={className}
    >
      {children}
    </motion.div>
  );
}
```

- [ ] **Step 7: Commit**

```powershell
git add src/components/motion src/hooks/use-magnetic.ts
git commit -m "feat: add motion primitives (FadeUp, Stagger, Parallax, Magnetic, ScrollReveal)"
```

---

## Task 8: Add shadcn-style UI primitives (button, input, accordion)

**Files:**
- Create: `src/components/ui/button.tsx`
- Create: `src/components/ui/input.tsx`
- Create: `src/components/ui/accordion.tsx`

(Inlined hand-written variants — shadcn CLI optional, kept manual to avoid heavy interactive setup.)

- [ ] **Step 1: Write `src/components/ui/button.tsx`**

```tsx
"use client";

import * as React from "react";
import { cn } from "@/lib/utils";

type Variant = "primary" | "ghost" | "outline";

type Props = React.ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: Variant;
  asChild?: never;
};

export const Button = React.forwardRef<HTMLButtonElement, Props>(
  ({ variant = "primary", className, ...rest }, ref) => {
    const base =
      "inline-flex items-center justify-center gap-2 rounded-full px-6 py-3 text-sm font-semibold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-bubbles-violet focus-visible:ring-offset-2 focus-visible:ring-offset-ink-0 disabled:opacity-50 disabled:cursor-not-allowed";

    const variants: Record<Variant, string> = {
      primary:
        "bg-bubbles-gradient text-white shadow-lg shadow-bubbles-violet/25 hover:brightness-110",
      ghost:
        "bg-transparent text-white border border-glass-border hover:bg-white/5",
      outline:
        "bg-transparent text-white border border-white/30 hover:border-white/60",
    };

    return (
      <button
        ref={ref}
        className={cn(base, variants[variant], className)}
        {...rest}
      />
    );
  }
);
Button.displayName = "Button";
```

- [ ] **Step 2: Write `src/components/ui/input.tsx`**

```tsx
"use client";

import * as React from "react";
import { cn } from "@/lib/utils";

type Props = React.InputHTMLAttributes<HTMLInputElement>;

export const Input = React.forwardRef<HTMLInputElement, Props>(
  ({ className, ...rest }, ref) => {
    return (
      <input
        ref={ref}
        className={cn(
          "w-full rounded-full bg-white/5 px-5 py-3 text-sm text-white placeholder:text-white/40",
          "border border-white/10 backdrop-blur-md",
          "focus:outline-none focus:border-bubbles-violet focus:ring-2 focus:ring-bubbles-violet/40",
          "transition-colors",
          className
        )}
        {...rest}
      />
    );
  }
);
Input.displayName = "Input";
```

- [ ] **Step 3: Write `src/components/ui/accordion.tsx`**

```tsx
"use client";

import { AnimatePresence, motion } from "framer-motion";
import { useState } from "react";
import { cn } from "@/lib/utils";

export type AccordionItemData = {
  id: string;
  question: string;
  answer: React.ReactNode;
};

type Props = {
  items: AccordionItemData[];
  className?: string;
};

export function Accordion({ items, className }: Props) {
  const [openId, setOpenId] = useState<string | null>(null);

  return (
    <ul className={cn("space-y-2", className)}>
      {items.map((item) => {
        const isOpen = openId === item.id;
        return (
          <li
            key={item.id}
            className="rounded-2xl border border-white/10 bg-white/[0.02] overflow-hidden"
          >
            <button
              type="button"
              onClick={() => setOpenId(isOpen ? null : item.id)}
              aria-expanded={isOpen}
              className="w-full flex items-center justify-between gap-4 px-6 py-4 text-left text-white"
            >
              <span className="font-medium">{item.question}</span>
              <motion.span
                animate={{ rotate: isOpen ? 45 : 0 }}
                transition={{ duration: 0.25 }}
                className="text-white/50 text-xl leading-none"
              >
                +
              </motion.span>
            </button>
            <AnimatePresence initial={false}>
              {isOpen && (
                <motion.div
                  key="content"
                  initial={{ height: 0, opacity: 0 }}
                  animate={{ height: "auto", opacity: 1 }}
                  exit={{ height: 0, opacity: 0 }}
                  transition={{ duration: 0.3, ease: [0.22, 1, 0.36, 1] }}
                  className="overflow-hidden"
                >
                  <div className="px-6 pb-5 text-white/70 text-sm leading-relaxed">
                    {item.answer}
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
          </li>
        );
      })}
    </ul>
  );
}
```

- [ ] **Step 4: Commit**

```powershell
git add src/components/ui
git commit -m "feat: add Button, Input, Accordion UI primitives"
```

---

## Task 9: Replace `app/layout.tsx` with metadata + LenisProvider

**Files:**
- Modify: `src/app/layout.tsx`

- [ ] **Step 1: Replace `src/app/layout.tsx` content**

```tsx
import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
import { LenisProvider } from "@/components/lenis-provider";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "https://bubbles-ai.vercel.app";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: {
    default: "Bubbles — Speak smarter. In real time.",
    template: "%s · Bubbles",
  },
  description:
    "AI conversation copilot with live wingman, deep Q&A, voice control, and memory that learns how you talk.",
  openGraph: {
    title: "Bubbles — Speak smarter. In real time.",
    description:
      "AI conversation copilot with live wingman, deep Q&A, voice control, and memory that learns how you talk.",
    url: siteUrl,
    siteName: "Bubbles",
    images: ["/og.png"],
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Bubbles — Speak smarter. In real time.",
    description:
      "AI conversation copilot with live wingman, deep Q&A, voice control, and memory that learns how you talk.",
    images: ["/og.png"],
  },
  icons: { icon: "/favicon.ico" },
};

export const viewport: Viewport = {
  themeColor: "#0a0a0f",
  colorScheme: "dark",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${geistSans.variable} ${geistMono.variable}`}>
      <body className="font-sans antialiased">
        <LenisProvider>{children}</LenisProvider>
      </body>
    </html>
  );
}
```

- [ ] **Step 2: Commit**

```powershell
git add src/app/layout.tsx
git commit -m "feat: wire global metadata, fonts, and Lenis into root layout"
```

---

## Task 10: Add brand assets (copy logos from Bubbles-AI)

**Files:**
- Create: `public/logo_dark.png`
- Create: `public/logo_light.png`

- [ ] **Step 1: Copy logos**

```powershell
copy "E:\FYP\FYP_V2\Bubbles-AI\assets\logos\logo_dark.png" "public\logo_dark.png"
copy "E:\FYP\FYP_V2\Bubbles-AI\assets\logos\logo_light.png" "public\logo_light.png"
```

Expected: both files copied. Verify with `dir public\logo*.png`.

- [ ] **Step 2: Commit**

```powershell
git add public/logo_dark.png public/logo_light.png
git commit -m "chore: add Bubbles brand logos"
```

---

## Task 11: Build `Nav` component

**Files:**
- Create: `src/components/nav.tsx`

- [ ] **Step 1: Write `src/components/nav.tsx`**

```tsx
"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useState } from "react";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";

const links = [
  { href: "#modes", label: "Modes" },
  { href: "#features", label: "Features" },
  { href: "#tech", label: "Tech" },
  { href: "#faq", label: "FAQ" },
];

export function Nav() {
  const [scrolled, setScrolled] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 80);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <header
      className={cn(
        "fixed top-0 inset-x-0 z-50 transition-all",
        scrolled
          ? "py-2 bg-ink-0/70 backdrop-blur-xl border-b border-white/10"
          : "py-4 bg-transparent"
      )}
    >
      <nav className="mx-auto flex max-w-6xl items-center justify-between px-5">
        <Link href="/" className="flex items-center gap-2">
          <Image src="/logo_dark.png" alt="Bubbles logo" width={28} height={28} priority />
          <span className="font-extrabold text-gradient text-lg">Bubbles</span>
        </Link>

        <div className="hidden md:flex items-center gap-7 text-sm text-white/70">
          {links.map((l) => (
            <a key={l.href} href={l.href} className="hover:text-white transition-colors">
              {l.label}
            </a>
          ))}
        </div>

        <div className="hidden md:block">
          <Button onClick={() => (window.location.hash = "#waitlist")}>Join waitlist</Button>
        </div>

        <button
          className="md:hidden text-white p-2"
          aria-label="Toggle menu"
          aria-expanded={mobileOpen}
          onClick={() => setMobileOpen((v) => !v)}
        >
          <span className="sr-only">Menu</span>
          <span className="block w-6 h-0.5 bg-white mb-1" />
          <span className="block w-6 h-0.5 bg-white mb-1" />
          <span className="block w-6 h-0.5 bg-white" />
        </button>
      </nav>

      {mobileOpen && (
        <div className="md:hidden border-t border-white/10 bg-ink-0/95 backdrop-blur-xl">
          <ul className="flex flex-col gap-4 p-5 text-white/80">
            {links.map((l) => (
              <li key={l.href}>
                <a href={l.href} onClick={() => setMobileOpen(false)}>
                  {l.label}
                </a>
              </li>
            ))}
            <li>
              <a href="#waitlist" onClick={() => setMobileOpen(false)}>
                Join waitlist
              </a>
            </li>
          </ul>
        </div>
      )}
    </header>
  );
}
```

- [ ] **Step 2: Commit**

```powershell
git add src/components/nav.tsx
git commit -m "feat: add sticky glass nav with scroll shrink and mobile menu"
```

---

## Task 12: Build `PhoneMockup` component

**Files:**
- Create: `src/components/phone-mockup.tsx`

- [ ] **Step 1: Write `src/components/phone-mockup.tsx`**

```tsx
"use client";

import { motion } from "framer-motion";
import { useEffect, useRef, useState } from "react";
import { usePrefersReducedMotion } from "@/lib/prefers-reduced-motion";

const cycle = [
  { kind: "user", text: "Heading into the client meeting…" },
  { kind: "ai", text: "Open with the metric they cared about last quarter." },
  { kind: "caption", text: "🎙 Live · 02:14" },
];

export function PhoneMockup() {
  const reduced = usePrefersReducedMotion();
  const [step, setStep] = useState(0);
  const wrapRef = useRef<HTMLDivElement | null>(null);
  const [tilt, setTilt] = useState({ x: 8, y: -10 });

  useEffect(() => {
    if (reduced) return;
    const id = setInterval(() => setStep((s) => (s + 1) % cycle.length), 1300);
    return () => clearInterval(id);
  }, [reduced]);

  useEffect(() => {
    if (reduced) return;
    function onMove(e: MouseEvent) {
      const el = wrapRef.current;
      if (!el) return;
      const r = el.getBoundingClientRect();
      const dx = (e.clientX - (r.left + r.width / 2)) / r.width;
      const dy = (e.clientY - (r.top + r.height / 2)) / r.height;
      const clampedX = Math.max(-1, Math.min(1, dx));
      const clampedY = Math.max(-1, Math.min(1, dy));
      setTilt({ x: 8 + clampedY * -4, y: -10 + clampedX * 6 });
    }
    window.addEventListener("mousemove", onMove);
    return () => window.removeEventListener("mousemove", onMove);
  }, [reduced]);

  return (
    <div ref={wrapRef} className="relative mx-auto" style={{ perspective: "1200px" }}>
      <motion.div
        animate={{ rotateX: tilt.x, rotateY: tilt.y }}
        transition={{ type: "spring", stiffness: 80, damping: 18 }}
        className="relative w-[280px] h-[560px] rounded-[3rem] border border-white/15 bg-gradient-to-b from-white/[0.04] to-white/[0.01] shadow-[0_60px_120px_-40px_rgba(139,92,246,0.45)] backdrop-blur-xl overflow-hidden"
        style={{ transformStyle: "preserve-3d" }}
      >
        <div className="absolute top-2 left-1/2 -translate-x-1/2 w-32 h-6 rounded-full bg-black/80" />
        <div className="absolute inset-3 rounded-[2.5rem] bg-ink-1/80 p-4 flex flex-col gap-2 overflow-hidden">
          <div className="flex items-center gap-2 text-[10px] text-white/50">
            <span className="w-2 h-2 rounded-full bg-bubbles-cyan animate-pulse" />
            Bubbles · live
          </div>
          {cycle.slice(0, step + 1).map((m, i) => (
            <Bubble key={i} kind={m.kind} text={m.text} />
          ))}
        </div>
      </motion.div>
    </div>
  );
}

function Bubble({ kind, text }: { kind: string; text: string }) {
  if (kind === "caption") {
    return (
      <div className="self-center mt-auto rounded-full border border-white/10 bg-black/40 px-3 py-1 text-[10px] text-white/60">
        {text}
      </div>
    );
  }
  const isUser = kind === "user";
  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      className={
        isUser
          ? "self-end max-w-[80%] rounded-2xl rounded-tr-md bg-white/10 px-3 py-2 text-[12px] text-white"
          : "self-start max-w-[80%] rounded-2xl rounded-tl-md bg-bubbles-gradient px-3 py-2 text-[12px] text-white"
      }
    >
      {text}
    </motion.div>
  );
}
```

- [ ] **Step 2: Commit**

```powershell
git add src/components/phone-mockup.tsx
git commit -m "feat: add CSS-3D phone mockup with cycling chat UI and cursor tilt"
```

---

## Task 13: Build `Hero` component (centered + bottom phone peek)

**Files:**
- Create: `src/components/hero.tsx`

- [ ] **Step 1: Write `src/components/hero.tsx`**

```tsx
"use client";

import { motion } from "framer-motion";
import { Button } from "@/components/ui/button";
import { Magnetic } from "@/components/motion/magnetic";
import { PhoneMockup } from "@/components/phone-mockup";
import { Parallax } from "@/components/motion/parallax";

const githubUrl = process.env.NEXT_PUBLIC_GITHUB_URL ?? "https://github.com/Qdevaan/Bubbles-AI";

export function Hero() {
  return (
    <section className="relative pt-32 pb-0 min-h-screen overflow-hidden flex flex-col items-center text-center">
      {/* Aurora blobs */}
      <div
        aria-hidden
        className="pointer-events-none absolute -top-40 -left-40 w-[640px] h-[640px] rounded-full opacity-40 blur-3xl animate-aurora-drift"
        style={{ background: "radial-gradient(circle, #22d3ee 0%, transparent 60%)" }}
      />
      <div
        aria-hidden
        className="pointer-events-none absolute -top-20 -right-40 w-[640px] h-[640px] rounded-full opacity-40 blur-3xl animate-aurora-drift"
        style={{ background: "radial-gradient(circle, #8b5cf6 0%, transparent 60%)", animationDelay: "5s" }}
      />
      {/* Dot grid */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 opacity-30"
        style={{
          backgroundImage:
            "radial-gradient(rgba(255,255,255,0.08) 1px, transparent 1px)",
          backgroundSize: "24px 24px",
        }}
      />

      <div className="relative z-10 max-w-3xl px-5">
        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6 }}
          className="inline-flex items-center gap-2 rounded-full border border-white/15 bg-white/5 px-3 py-1 text-xs text-white/70 backdrop-blur-md"
        >
          <span className="w-1.5 h-1.5 rounded-full bg-bubbles-cyan animate-pulse" />
          Live beta
        </motion.div>

        <motion.h1
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.7, delay: 0.05 }}
          className="mt-6 text-5xl md:text-7xl font-extrabold tracking-tightest leading-[1.05]"
        >
          <span className="text-white">Speak smarter.</span>
          <br />
          <span className="text-gradient bg-[length:200%_100%] animate-gradient-sweep">
            In real time.
          </span>
        </motion.h1>

        <motion.p
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.15 }}
          className="mt-6 text-base md:text-lg text-white/70 max-w-2xl mx-auto"
        >
          Live wingman + consultant Q&amp;A. Persistent memory that learns how you talk.
        </motion.p>

        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.25 }}
          className="mt-8 flex flex-col sm:flex-row items-center justify-center gap-3"
        >
          <Magnetic>
            <Button onClick={() => (window.location.hash = "#waitlist")}>
              Join waitlist →
            </Button>
          </Magnetic>
          <a href={githubUrl} target="_blank" rel="noreferrer">
            <Button variant="ghost">View on GitHub</Button>
          </a>
        </motion.div>
      </div>

      <Parallax speed={-0.2} className="relative z-10 mt-16 md:mt-20">
        <div className="translate-y-16 md:translate-y-24">
          <PhoneMockup />
        </div>
      </Parallax>
    </section>
  );
}
```

- [ ] **Step 2: Commit**

```powershell
git add src/components/hero.tsx
git commit -m "feat: add hero with gradient headline, magnetic CTAs, aurora blobs and bottom-peek phone"
```

---

## Task 14: Build `ModesSection` (sticky-scroll storytelling)

**Files:**
- Create: `src/components/modes-section.tsx`

- [ ] **Step 1: Write `src/components/modes-section.tsx`**

```tsx
"use client";

import { motion, useScroll, useTransform } from "framer-motion";
import { useRef } from "react";

const modes = [
  {
    title: "Wingman",
    pitch: "In your ear, mid-conversation. Without sounding like a robot.",
    body:
      "Real-time advice during live calls. Bubbles listens, captions, and whispers next-best-line suggestions you can take or ignore.",
    accent: "from-bubbles-cyan to-bubbles-violet",
  },
  {
    title: "Consultant",
    pitch: "Deep Q&A with memory you can audit.",
    body:
      "Ask anything. Bubbles streams answers grounded in your past sessions, with citation chips back to the exact moment something was said.",
    accent: "from-bubbles-violet to-pink-400",
  },
  {
    title: "Voice",
    pitch: "Just say 'Hey Bubbles' — we handle the awkward parts.",
    body:
      "Wake-word, intent routing, and voice commands across the whole app. No taps when your hands are busy.",
    accent: "from-bubbles-cyan to-emerald-400",
  },
];

export function ModesSection() {
  const ref = useRef<HTMLDivElement | null>(null);
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ["start start", "end end"],
  });

  return (
    <section id="modes" ref={ref} className="relative" style={{ height: `${modes.length * 100}vh` }}>
      <div className="sticky top-0 h-screen flex items-center justify-center px-5">
        <div className="max-w-6xl w-full grid md:grid-cols-2 gap-12 items-center">
          {modes.map((m, i) => (
            <ModePanel
              key={m.title}
              index={i}
              total={modes.length}
              progress={scrollYProgress}
              {...m}
            />
          ))}
        </div>
      </div>
    </section>
  );
}

import type { MotionValue } from "framer-motion";

function ModePanel({
  index,
  total,
  progress,
  title,
  pitch,
  body,
  accent,
}: {
  index: number;
  total: number;
  progress: MotionValue<number>;
  title: string;
  pitch: string;
  body: string;
  accent: string;
}) {
  const slot = 1 / total;
  const start = slot * index;
  const end = slot * (index + 1);

  const opacity = useTransform(progress, [start - 0.05, start, end, end + 0.05], [0, 1, 1, 0]);
  const y = useTransform(progress, [start - 0.05, start, end, end + 0.05], [40, 0, 0, -40]);

  return (
    <>
      <motion.div style={{ opacity, y }} className="space-y-5 col-span-full md:col-span-1">
        <span className="inline-flex items-center gap-2 rounded-full border border-white/15 bg-white/5 px-3 py-1 text-xs text-white/70 uppercase tracking-widest">
          Mode {index + 1} / {total}
        </span>
        <h2 className="text-4xl md:text-5xl font-extrabold tracking-tightest text-white">
          {title}
        </h2>
        <p className={`text-xl md:text-2xl bg-gradient-to-r ${accent} bg-clip-text text-transparent font-semibold`}>
          {pitch}
        </p>
        <p className="text-white/65 leading-relaxed max-w-prose">{body}</p>
      </motion.div>

      <motion.div
        style={{ opacity, y }}
        className="hidden md:block glass rounded-3xl aspect-[4/3] p-6 col-span-1"
      >
        <div className="h-full w-full rounded-2xl bg-ink-1 border border-white/5 p-4 flex flex-col gap-2">
          <div className="h-3 w-1/3 rounded bg-white/10" />
          <div className="h-3 w-3/4 rounded bg-white/5" />
          <div className="mt-auto self-start rounded-2xl rounded-tl-md bg-bubbles-gradient px-3 py-2 text-xs text-white">
            {pitch}
          </div>
        </div>
      </motion.div>
    </>
  );
}
```

- [ ] **Step 2: Commit**

```powershell
git add src/components/modes-section.tsx
git commit -m "feat: add Modes sticky-scroll storytelling section"
```

---

## Task 15: Build `TryPrompt` component

**Files:**
- Create: `src/components/try-prompt.tsx`

- [ ] **Step 1: Write `src/components/try-prompt.tsx`**

```tsx
"use client";

import { motion, AnimatePresence } from "framer-motion";
import { useEffect, useState } from "react";
import { Input } from "@/components/ui/input";

const cannedAnswers: Record<string, string> = {
  "Help me sound confident":
    "Open with what they care about, not what you want. Lead with their last quarter's win, then bridge to the question you actually want answered.",
  "Recap my last meeting":
    "Sara wanted next-step ownership; Mike pushed back on the timeline. The unblocked task is the integration spec — owner not yet assigned.",
  "Translate my idea":
    "You're describing event-sourced replay. The shorter pitch: 'we keep the tape so we can rewind any session.'",
};

const chips = Object.keys(cannedAnswers);

export function TryPrompt() {
  const [active, setActive] = useState<string | null>(null);
  const [typed, setTyped] = useState("");
  const [showToast, setShowToast] = useState(false);

  useEffect(() => {
    if (!active) return;
    const target = cannedAnswers[active];
    setTyped("");
    let i = 0;
    const id = setInterval(() => {
      i += 2;
      setTyped(target.slice(0, i));
      if (i >= target.length) {
        clearInterval(id);
        setShowToast(true);
        setTimeout(() => setShowToast(false), 2200);
      }
    }, 12);
    return () => clearInterval(id);
  }, [active]);

  return (
    <section className="relative py-24 md:py-32 px-5">
      <div className="mx-auto max-w-3xl text-center">
        <h2 className="text-3xl md:text-5xl font-extrabold tracking-tightest text-white">
          Try a prompt.
        </h2>
        <p className="mt-3 text-white/60">
          Pick a chip — Bubbles will respond. (Mocked. Real model lives in the app.)
        </p>

        <div className="mt-8 glass rounded-2xl p-4 text-left">
          <Input
            placeholder="Ask Bubbles anything…"
            value={active ?? ""}
            readOnly
            className="rounded-xl"
          />
          <div className="mt-3 flex flex-wrap gap-2">
            {chips.map((c) => (
              <button
                key={c}
                type="button"
                onClick={() => setActive(c)}
                className="rounded-full border border-white/10 bg-white/5 px-3 py-1 text-xs text-white/80 hover:bg-white/10"
              >
                {c}
              </button>
            ))}
          </div>

          <AnimatePresence>
            {active && (
              <motion.div
                key={active}
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0 }}
                className="relative mt-5 rounded-xl border border-white/10 bg-ink-1 p-4 text-sm text-white/80 min-h-[80px]"
              >
                <span>{typed}</span>
                <span className="ml-1 inline-block w-0.5 h-4 bg-white/60 align-middle animate-pulse" />
                <div className="mt-3 flex gap-2 flex-wrap">
                  <span className="rounded-full bg-bubbles-violet/20 border border-bubbles-violet/40 px-2 py-0.5 text-[10px] text-bubbles-violet">
                    cite: session #142
                  </span>
                </div>
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </div>

      <AnimatePresence>
        {showToast && (
          <motion.div
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: 16 }}
            className="fixed bottom-8 left-1/2 -translate-x-1/2 rounded-full bg-bubbles-gradient px-4 py-2 text-xs font-semibold text-white shadow-xl z-40"
          >
            ✦ memory updated
          </motion.div>
        )}
      </AnimatePresence>
    </section>
  );
}
```

- [ ] **Step 2: Commit**

```powershell
git add src/components/try-prompt.tsx
git commit -m "feat: add interactive Try-a-prompt widget with mocked typewriter and toast"
```

---

## Task 16: Build `FeaturesGrid` (bento)

**Files:**
- Create: `src/components/features-grid.tsx`

- [ ] **Step 1: Write `src/components/features-grid.tsx`**

```tsx
"use client";

import { motion } from "framer-motion";
import { FadeUp } from "@/components/motion/fade-up";

type Feature = {
  title: string;
  blurb: string;
  span: string;
  glyph: string;
};

const features: Feature[] = [
  { title: "Memory graph", blurb: "Entities and relations linked across every session.", span: "md:col-span-2 md:row-span-2", glyph: "◉" },
  { title: "Session analytics", blurb: "Sentiment and turn-level metrics, automatically.", span: "md:col-span-1", glyph: "📈" },
  { title: "Voice enrollment", blurb: "Speaker embedding so Bubbles knows who's talking.", span: "md:col-span-1", glyph: "🎙" },
  { title: "Multi-platform", blurb: "Android, iOS, Web, Desktop — one account, every screen.", span: "md:col-span-2", glyph: "✦" },
  { title: "Live captions", blurb: "Real-time transcription, low-latency.", span: "md:col-span-1", glyph: "💬" },
  { title: "Privacy-first", blurb: "Your data stays yours. Export or wipe anytime.", span: "md:col-span-1", glyph: "🛡" },
];

export function FeaturesGrid() {
  return (
    <section id="features" className="py-24 md:py-32 px-5">
      <FadeUp className="text-center max-w-3xl mx-auto">
        <h2 className="text-3xl md:text-5xl font-extrabold tracking-tightest text-white">
          Everything in <span className="text-gradient">one assistant</span>.
        </h2>
        <p className="mt-3 text-white/60">
          A short tour of what comes in the box.
        </p>
      </FadeUp>

      <div className="mx-auto mt-12 grid max-w-6xl auto-rows-[180px] grid-cols-1 md:grid-cols-3 gap-4">
        {features.map((f, i) => (
          <motion.article
            key={f.title}
            initial={{ opacity: 0, y: 16 }}
            whileInView={{ opacity: 1, y: 0 }}
            whileHover={{ y: -4 }}
            viewport={{ once: true, margin: "-10% 0px" }}
            transition={{ duration: 0.5, delay: i * 0.04 }}
            className={`glass rounded-2xl p-6 ${f.span} relative overflow-hidden group`}
          >
            <div className="absolute -top-10 -right-10 w-40 h-40 rounded-full opacity-0 group-hover:opacity-30 transition-opacity bg-bubbles-violet blur-3xl" />
            <div className="text-2xl mb-3">{f.glyph}</div>
            <h3 className="text-lg font-semibold text-white">{f.title}</h3>
            <p className="mt-1 text-sm text-white/65 max-w-xs">{f.blurb}</p>
          </motion.article>
        ))}
      </div>
    </section>
  );
}
```

- [ ] **Step 2: Commit**

```powershell
git add src/components/features-grid.tsx
git commit -m "feat: add bento features grid with hover glow"
```

---

## Task 17: Build `MemoryGraph` (lazy, cosmos-graph)

**Files:**
- Create: `src/components/memory-graph.tsx`

- [ ] **Step 1: Write `src/components/memory-graph.tsx`**

```tsx
"use client";

import { useEffect, useRef } from "react";

type Node = { id: string; label: string };
type Edge = { source: string; target: string };

const nodes: Node[] = [
  ...Array.from({ length: 8 }, (_, i) => ({ id: `p${i}`, label: `Person ${i + 1}` })),
  ...Array.from({ length: 12 }, (_, i) => ({ id: `t${i}`, label: `Topic ${i + 1}` })),
  ...Array.from({ length: 10 }, (_, i) => ({ id: `e${i}`, label: `Event ${i + 1}` })),
];

const edges: Edge[] = nodes.slice(1).map((n, i) => ({
  source: nodes[Math.floor(i / 2)].id,
  target: n.id,
}));

export default function MemoryGraph() {
  const ref = useRef<HTMLCanvasElement | null>(null);

  useEffect(() => {
    let destroy: (() => void) | null = null;
    let cancelled = false;

    (async () => {
      const { Graph } = await import("cosmos-graph");
      if (cancelled || !ref.current) return;

      const graph = new Graph(ref.current, {
        backgroundColor: "#0a0a0f",
        nodeColor: () => "#22d3ee",
        linkColor: () => "rgba(139,92,246,0.4)",
        simulation: { gravity: 0.1, repulsion: 1.5 },
      });

      graph.setData(
        nodes.map((n) => ({ id: n.id })),
        edges
      );
      graph.start();

      destroy = () => graph.destroy();
    })();

    return () => {
      cancelled = true;
      destroy?.();
    };
  }, []);

  return (
    <canvas
      ref={ref}
      aria-hidden="true"
      className="w-full h-[420px] md:h-[520px] rounded-3xl border border-white/10"
    />
  );
}
```

- [ ] **Step 2: Commit**

```powershell
git add src/components/memory-graph.tsx
git commit -m "feat: add cosmos-graph memory visualization with lazy import"
```

---

## Task 18: Build memory-graph section wrapper

**Files:**
- Create: `src/components/memory-graph-section.tsx`

- [ ] **Step 1: Write `src/components/memory-graph-section.tsx`**

```tsx
"use client";

import dynamic from "next/dynamic";
import { FadeUp } from "@/components/motion/fade-up";

const MemoryGraph = dynamic(() => import("@/components/memory-graph"), {
  ssr: false,
  loading: () => (
    <div className="w-full h-[420px] md:h-[520px] rounded-3xl border border-white/10 animate-pulse bg-white/[0.02]" />
  ),
});

export function MemoryGraphSection() {
  return (
    <section className="py-24 md:py-32 px-5">
      <FadeUp className="text-center max-w-3xl mx-auto">
        <h2 className="text-3xl md:text-5xl font-extrabold tracking-tightest text-white">
          Memory that <span className="text-gradient">remembers</span>.
        </h2>
        <p className="mt-3 text-white/60">
          Bubbles remembers what you said. And who you said it to.
        </p>
      </FadeUp>

      <div className="mx-auto mt-10 max-w-5xl">
        <MemoryGraph />
      </div>
    </section>
  );
}
```

- [ ] **Step 2: Commit**

```powershell
git add src/components/memory-graph-section.tsx
git commit -m "feat: add memory-graph section with SSR-disabled lazy load"
```

---

## Task 19: Build `HowItWorks`

**Files:**
- Create: `src/components/how-it-works.tsx`

- [ ] **Step 1: Write `src/components/how-it-works.tsx`**

```tsx
"use client";

import { motion, useScroll, useTransform } from "framer-motion";
import { useRef } from "react";

const steps = [
  { label: "Speak", body: "On-device wake word + capture." },
  { label: "Transcribe", body: "Streaming low-latency transcription." },
  { label: "Reason", body: "LLM + memory retrieval over your graph." },
  { label: "Suggest", body: "A line you can take, ignore, or edit." },
];

export function HowItWorks() {
  const ref = useRef<HTMLDivElement | null>(null);
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ["start end", "end start"],
  });

  const dash = useTransform(scrollYProgress, [0, 1], [1, 0]);

  return (
    <section ref={ref} className="py-24 md:py-32 px-5">
      <div className="mx-auto max-w-5xl text-center">
        <h2 className="text-3xl md:text-5xl font-extrabold tracking-tightest text-white">
          How it <span className="text-gradient">works</span>.
        </h2>
        <p className="mt-3 text-white/60">Four steps. Under a second.</p>

        <div className="mt-16 relative">
          <svg
            viewBox="0 0 800 60"
            className="w-full h-12 absolute top-1/2 -translate-y-1/2 left-0 -z-10"
            aria-hidden
          >
            <motion.path
              d="M 40 30 Q 200 0 400 30 T 760 30"
              fill="none"
              stroke="url(#bubbles)"
              strokeWidth="2"
              strokeDasharray="1"
              style={{ pathLength: useTransform(dash, [1, 0], [0, 1]) }}
            />
            <defs>
              <linearGradient id="bubbles" x1="0" x2="1">
                <stop offset="0%" stopColor="#22d3ee" />
                <stop offset="100%" stopColor="#8b5cf6" />
              </linearGradient>
            </defs>
          </svg>

          <div className="grid grid-cols-2 md:grid-cols-4 gap-6">
            {steps.map((s, i) => (
              <motion.div
                key={s.label}
                initial={{ opacity: 0, y: 16 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, margin: "-10% 0px" }}
                transition={{ duration: 0.5, delay: i * 0.08 }}
                className="glass rounded-2xl p-5 text-left"
              >
                <div className="text-[11px] text-white/50 uppercase tracking-widest">
                  Step {i + 1}
                </div>
                <div className="mt-2 text-lg font-semibold text-white">{s.label}</div>
                <p className="mt-1 text-sm text-white/65">{s.body}</p>
              </motion.div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
```

- [ ] **Step 2: Commit**

```powershell
git add src/components/how-it-works.tsx
git commit -m "feat: add animated 'how it works' SVG flow"
```

---

## Task 20: Build `TechSection`

**Files:**
- Create: `src/components/tech-section.tsx`

- [ ] **Step 1: Write `src/components/tech-section.tsx`**

```tsx
"use client";

import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Stagger, staggerItem } from "@/components/motion/stagger";
import { motion } from "framer-motion";

const stack = [
  "Flutter",
  "FastAPI",
  "Supabase",
  "LiveKit",
  "Groq",
  "sentence-transformers",
  "networkx",
  "Provider",
  "Docker",
];

const githubUrl = process.env.NEXT_PUBLIC_GITHUB_URL ?? "https://github.com/Qdevaan/Bubbles-AI";

export function TechSection() {
  return (
    <section id="tech" className="py-24 md:py-32 px-5">
      <div className="mx-auto max-w-6xl grid md:grid-cols-2 gap-12 items-center">
        <div>
          <h2 className="text-3xl md:text-5xl font-extrabold tracking-tightest text-white">
            Built on a stack you can <span className="text-gradient">audit</span>.
          </h2>
          <p className="mt-4 text-white/65 max-w-prose">
            Bubbles is a final-year project (FYP-II 2026). Real-time voice, retrieval-grounded
            reasoning, and a knowledge graph that grows with you. Open source.
          </p>

          <Stagger className="mt-6 flex flex-wrap gap-2">
            {stack.map((s) => (
              <motion.span
                key={s}
                variants={staggerItem}
                className="rounded-full border border-white/10 bg-white/5 px-3 py-1 text-xs font-mono text-white/80"
              >
                {s}
              </motion.span>
            ))}
          </Stagger>

          <div className="mt-8 flex flex-wrap gap-3">
            <a href={githubUrl} target="_blank" rel="noreferrer">
              <Button variant="ghost">View on GitHub →</Button>
            </a>
            <Link href="/about">
              <Button variant="outline">Read tech deep-dive →</Button>
            </Link>
          </div>
        </div>

        <div className="glass rounded-3xl p-6 aspect-square hidden md:flex items-center justify-center">
          <svg viewBox="0 0 200 200" className="w-full h-full" aria-hidden>
            <defs>
              <linearGradient id="g1" x1="0" x2="1">
                <stop offset="0%" stopColor="#22d3ee" />
                <stop offset="100%" stopColor="#8b5cf6" />
              </linearGradient>
            </defs>
            <motion.circle
              cx="100"
              cy="100"
              r="60"
              fill="none"
              stroke="url(#g1)"
              strokeWidth="1.5"
              initial={{ pathLength: 0 }}
              whileInView={{ pathLength: 1 }}
              viewport={{ once: true }}
              transition={{ duration: 1.4 }}
            />
            <motion.circle
              cx="100"
              cy="100"
              r="30"
              fill="none"
              stroke="url(#g1)"
              strokeWidth="1.5"
              initial={{ pathLength: 0 }}
              whileInView={{ pathLength: 1 }}
              viewport={{ once: true }}
              transition={{ duration: 1.4, delay: 0.2 }}
            />
            <text x="100" y="105" textAnchor="middle" fill="white" fontFamily="monospace" fontSize="10">
              client → api → llm
            </text>
          </svg>
        </div>
      </div>
    </section>
  );
}
```

- [ ] **Step 2: Commit**

```powershell
git add src/components/tech-section.tsx
git commit -m "feat: add tech section with stack chips and architecture sketch"
```

---

## Task 21: Build `Faq`

**Files:**
- Create: `src/components/faq.tsx`

- [ ] **Step 1: Write `src/components/faq.tsx`**

```tsx
"use client";

import { Accordion, type AccordionItemData } from "@/components/ui/accordion";
import { FadeUp } from "@/components/motion/fade-up";

const faq: AccordionItemData[] = [
  {
    id: "when",
    question: "When can I use Bubbles?",
    answer: "We're rolling beta invites in waves. Join the waitlist below — we send you a link the moment your slot opens.",
  },
  {
    id: "free",
    question: "Is it free?",
    answer: "Beta is free. Long-term we'll have a free tier with paid plans for heavy users; pricing isn't locked yet.",
  },
  {
    id: "platforms",
    question: "Which platforms are supported?",
    answer: "Android first. iOS shortly after. A web build for desktop is on the roadmap.",
  },
  {
    id: "privacy",
    question: "How do you handle privacy?",
    answer: "Your sessions belong to you. You can export or wipe everything from a single screen. We never sell data.",
  },
  {
    id: "voice",
    question: "How does voice work?",
    answer: "On-device wake-word ('Hey Bubbles') triggers a low-latency transcription stream. Audio isn't uploaded by default — only transcripts.",
  },
  {
    id: "source",
    question: "Can I see the source code?",
    answer: "Yes. Full repo on GitHub. It's also a final-year project (FYP-II 2026).",
  },
];

export function Faq() {
  return (
    <section id="faq" className="py-24 md:py-32 px-5">
      <div className="mx-auto max-w-3xl">
        <FadeUp className="text-center">
          <h2 className="text-3xl md:text-5xl font-extrabold tracking-tightest text-white">
            Questions <span className="text-gradient">answered</span>.
          </h2>
        </FadeUp>
        <FadeUp delay={0.1} className="mt-10">
          <Accordion items={faq} />
        </FadeUp>
      </div>
    </section>
  );
}
```

- [ ] **Step 2: Commit**

```powershell
git add src/components/faq.tsx
git commit -m "feat: add FAQ section with motion accordion"
```

---

## Task 22: Apply Supabase migration

**Files:**
- Create: `migrations/2026-05-09_waitlist.sql`

- [ ] **Step 1: Write `migrations/2026-05-09_waitlist.sql`**

```sql
create table if not exists public.waitlist (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  source text default 'landing',
  user_agent text,
  referrer text,
  created_at timestamptz not null default now()
);

create unique index if not exists waitlist_email_lower_idx
  on public.waitlist (lower(email));

alter table public.waitlist enable row level security;

revoke all on public.waitlist from anon, authenticated;
```

- [ ] **Step 2: Apply via Supabase MCP `apply_migration`**

Use the Supabase MCP tool from the agent runtime:

```text
apply_migration(
  name: "2026-05-09_waitlist",
  query: <contents of migrations/2026-05-09_waitlist.sql>
)
```

Expected: tool returns success. Verify by listing tables; `public.waitlist` should appear with the columns above.

If the MCP tool is unavailable, paste the SQL into the Supabase Studio SQL Editor and run it.

- [ ] **Step 3: Commit**

```powershell
git add migrations/2026-05-09_waitlist.sql
git commit -m "feat(db): waitlist table with case-insensitive email unique index"
```

---

## Task 23: Add Supabase server client

**Files:**
- Create: `src/lib/supabase-server.ts`

- [ ] **Step 1: Write `src/lib/supabase-server.ts`**

```ts
import "server-only";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

let cached: SupabaseClient | null = null;

export function getSupabaseAdmin(): SupabaseClient {
  if (cached) return cached;

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url) throw new Error("NEXT_PUBLIC_SUPABASE_URL is not set");
  if (!key) throw new Error("SUPABASE_SERVICE_ROLE_KEY is not set");

  cached = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return cached;
}
```

- [ ] **Step 2: Commit**

```powershell
git add src/lib/supabase-server.ts
git commit -m "feat: add server-only Supabase admin client"
```

---

## Task 24: Add waitlist domain logic + tests

**Files:**
- Create: `src/lib/waitlist.ts`
- Create: `src/test/waitlist.test.ts`
- Create: `vitest.config.ts`

- [ ] **Step 1: Write `vitest.config.ts`**

```ts
import { defineConfig } from "vitest/config";
import path from "node:path";

export default defineConfig({
  test: {
    environment: "jsdom",
    include: ["src/test/**/*.test.ts"],
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "src"),
    },
  },
});
```

- [ ] **Step 2: Add test scripts to `package.json`**

Open `package.json` and ensure the `scripts` block contains:

```json
{
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint",
    "test": "vitest run",
    "test:watch": "vitest"
  }
}
```

(Replace existing `scripts` block — keep `dev`, `build`, `start`, `lint`, add `test`, `test:watch`.)

- [ ] **Step 3: Write the failing test `src/test/waitlist.test.ts`**

```ts
import { describe, it, expect } from "vitest";
import { waitlistSchema, normalizeEmail } from "@/lib/waitlist";

describe("waitlistSchema", () => {
  it("accepts a valid email", () => {
    const r = waitlistSchema.safeParse({ email: "user@example.com" });
    expect(r.success).toBe(true);
  });

  it("rejects malformed email", () => {
    const r = waitlistSchema.safeParse({ email: "not-an-email" });
    expect(r.success).toBe(false);
  });

  it("rejects empty email", () => {
    const r = waitlistSchema.safeParse({ email: "" });
    expect(r.success).toBe(false);
  });

  it("rejects oversized email (>254 chars)", () => {
    const long = "a".repeat(250) + "@x.io";
    const r = waitlistSchema.safeParse({ email: long });
    expect(r.success).toBe(false);
  });

  it("normalizes case + trims whitespace", () => {
    expect(normalizeEmail("  USER@Example.COM  ")).toBe("user@example.com");
  });
});
```

- [ ] **Step 4: Run test to verify it fails**

```powershell
npm test
```

Expected: FAIL — "Cannot find module '@/lib/waitlist'".

- [ ] **Step 5: Write minimal implementation `src/lib/waitlist.ts`**

```ts
import { z } from "zod";

export const waitlistSchema = z.object({
  email: z.string().min(1).max(254).email(),
});

export type WaitlistInput = z.infer<typeof waitlistSchema>;

export function normalizeEmail(raw: string): string {
  return raw.trim().toLowerCase();
}
```

- [ ] **Step 6: Run test to verify it passes**

```powershell
npm test
```

Expected: PASS — 5/5 tests pass.

- [ ] **Step 7: Commit**

```powershell
git add vitest.config.ts package.json package-lock.json src/lib/waitlist.ts src/test/waitlist.test.ts
git commit -m "feat: add waitlist zod schema and email normalization with tests"
```

---

## Task 25: Add rate-limit lib + tests

**Files:**
- Create: `src/lib/rate-limit.ts`
- Create: `src/test/rate-limit.test.ts`

- [ ] **Step 1: Write the failing test `src/test/rate-limit.test.ts`**

```ts
import { describe, it, expect, beforeEach } from "vitest";
import { createRateLimiter } from "@/lib/rate-limit";

describe("rate-limit", () => {
  let limiter: ReturnType<typeof createRateLimiter>;

  beforeEach(() => {
    limiter = createRateLimiter({ max: 3, windowMs: 1000 });
  });

  it("allows up to max requests within window", () => {
    expect(limiter.check("ip-a").allowed).toBe(true);
    expect(limiter.check("ip-a").allowed).toBe(true);
    expect(limiter.check("ip-a").allowed).toBe(true);
  });

  it("rejects the (max+1)th request within window", () => {
    limiter.check("ip-a");
    limiter.check("ip-a");
    limiter.check("ip-a");
    expect(limiter.check("ip-a").allowed).toBe(false);
  });

  it("isolates buckets per key", () => {
    limiter.check("ip-a");
    limiter.check("ip-a");
    limiter.check("ip-a");
    expect(limiter.check("ip-b").allowed).toBe(true);
  });

  it("resets after window expires", async () => {
    limiter.check("ip-a");
    limiter.check("ip-a");
    limiter.check("ip-a");
    await new Promise((r) => setTimeout(r, 1100));
    expect(limiter.check("ip-a").allowed).toBe(true);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
npm test
```

Expected: FAIL — "Cannot find module '@/lib/rate-limit'".

- [ ] **Step 3: Write minimal implementation `src/lib/rate-limit.ts`**

```ts
type Bucket = { count: number; resetAt: number };

export function createRateLimiter(opts: { max: number; windowMs: number }) {
  const buckets = new Map<string, Bucket>();

  function check(key: string): { allowed: boolean; remaining: number } {
    const now = Date.now();
    const existing = buckets.get(key);

    if (!existing || existing.resetAt <= now) {
      buckets.set(key, { count: 1, resetAt: now + opts.windowMs });
      return { allowed: true, remaining: opts.max - 1 };
    }

    if (existing.count >= opts.max) {
      return { allowed: false, remaining: 0 };
    }

    existing.count += 1;
    return { allowed: true, remaining: opts.max - existing.count };
  }

  return { check };
}
```

- [ ] **Step 4: Run tests to verify they pass**

```powershell
npm test
```

Expected: PASS — all rate-limit tests + waitlist tests pass.

- [ ] **Step 5: Commit**

```powershell
git add src/lib/rate-limit.ts src/test/rate-limit.test.ts
git commit -m "feat: add in-memory per-key rate limiter with tests"
```

---

## Task 26: Build `/api/waitlist` route

**Files:**
- Create: `src/app/api/waitlist/route.ts`

- [ ] **Step 1: Write `src/app/api/waitlist/route.ts`**

```ts
import { NextResponse } from "next/server";
import { z } from "zod";
import { waitlistSchema, normalizeEmail } from "@/lib/waitlist";
import { createRateLimiter } from "@/lib/rate-limit";
import { getSupabaseAdmin } from "@/lib/supabase-server";

export const runtime = "nodejs";

const limiter = createRateLimiter({ max: 5, windowMs: 10 * 60 * 1000 });

const bodySchema = waitlistSchema.extend({
  company: z.string().optional(), // honeypot
});

function clientIp(req: Request): string {
  const fwd = req.headers.get("x-forwarded-for");
  if (fwd) return fwd.split(",")[0]!.trim();
  return req.headers.get("x-real-ip") ?? "0.0.0.0";
}

export async function POST(req: Request) {
  let raw: unknown;
  try {
    raw = await req.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  const parsed = bodySchema.safeParse(raw);
  if (!parsed.success) {
    return NextResponse.json({ error: "invalid_email" }, { status: 400 });
  }

  // Honeypot — silently accept and drop
  if (parsed.data.company && parsed.data.company.length > 0) {
    return NextResponse.json({ ok: true });
  }

  const ip = clientIp(req);
  const rl = limiter.check(ip);
  if (!rl.allowed) {
    return NextResponse.json({ error: "rate_limited" }, { status: 429 });
  }

  const email = normalizeEmail(parsed.data.email);
  const userAgent = req.headers.get("user-agent") ?? null;
  const referrer = req.headers.get("referer") ?? null;

  try {
    const supabase = getSupabaseAdmin();
    const { error } = await supabase
      .from("waitlist")
      .insert({ email, user_agent: userAgent, referrer });

    if (error) {
      // 23505 = unique violation in Postgres
      if (error.code === "23505") {
        return NextResponse.json({ ok: true, already: true });
      }
      console.error("waitlist insert failed", error);
      return NextResponse.json({ error: "server" }, { status: 500 });
    }

    return NextResponse.json({ ok: true });
  } catch (err) {
    console.error("waitlist route exception", err);
    return NextResponse.json({ error: "server" }, { status: 500 });
  }
}
```

- [ ] **Step 2: Commit**

```powershell
git add src/app/api/waitlist/route.ts
git commit -m "feat: add /api/waitlist Node-runtime route with zod + rate-limit + honeypot"
```

---

## Task 27: Build `CtaWaitlist` form

**Files:**
- Create: `src/components/cta-waitlist.tsx`

- [ ] **Step 1: Write `src/components/cta-waitlist.tsx`**

```tsx
"use client";

import { motion } from "framer-motion";
import { useEffect, useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import confetti from "canvas-confetti";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { waitlistSchema, type WaitlistInput } from "@/lib/waitlist";

const githubUrl = process.env.NEXT_PUBLIC_GITHUB_URL ?? "https://github.com/Qdevaan/Bubbles-AI";

export function CtaWaitlist() {
  const [done, setDone] = useState(false);
  const [serverError, setServerError] = useState<string | null>(null);
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<WaitlistInput & { company?: string }>({
    resolver: zodResolver(waitlistSchema),
  });

  useEffect(() => {
    if (typeof window !== "undefined" && localStorage.getItem("bubbles_waitlist") === "1") {
      setDone(true);
    }
  }, []);

  async function onSubmit(values: WaitlistInput & { company?: string }) {
    setServerError(null);
    const res = await fetch("/api/waitlist", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(values),
    });

    if (!res.ok) {
      const j = (await res.json().catch(() => ({}))) as { error?: string };
      setServerError(j.error === "rate_limited" ? "Too many attempts. Try later." : "Something broke. Try again.");
      return;
    }

    localStorage.setItem("bubbles_waitlist", "1");
    setDone(true);
    confetti({ particleCount: 80, spread: 70, origin: { y: 0.7 }, colors: ["#22d3ee", "#8b5cf6", "#ffffff"] });
  }

  return (
    <section id="waitlist" className="relative py-28 md:py-36 px-5">
      <div
        aria-hidden
        className="absolute inset-0 -z-10 opacity-50 blur-3xl"
        style={{
          background:
            "radial-gradient(ellipse at 30% 50%, rgba(34,211,238,0.25), transparent 50%), radial-gradient(ellipse at 70% 50%, rgba(139,92,246,0.3), transparent 50%)",
        }}
      />
      <div className="mx-auto max-w-2xl text-center">
        <motion.h2
          initial={{ opacity: 0, y: 16 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ duration: 0.6 }}
          className="text-4xl md:text-6xl font-extrabold tracking-tightest text-white"
        >
          Be early. <span className="text-gradient">Speak smarter.</span>
        </motion.h2>
        <p className="mt-4 text-white/65">We email when your beta slot opens. No spam, ever.</p>

        {done ? (
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            className="mt-10 glass rounded-2xl p-8"
          >
            <div className="text-3xl">✓</div>
            <p className="mt-3 text-white/80">You&apos;re in. We&apos;ll email when beta opens.</p>
          </motion.div>
        ) : (
          <form
            noValidate
            onSubmit={handleSubmit(onSubmit)}
            className="mt-10 flex flex-col sm:flex-row gap-3 max-w-lg mx-auto"
          >
            <Input
              type="email"
              placeholder="you@somewhere.com"
              aria-label="Email address"
              aria-invalid={!!errors.email}
              aria-describedby={errors.email ? "email-error" : undefined}
              {...register("email")}
            />
            <input
              type="text"
              tabIndex={-1}
              autoComplete="off"
              aria-hidden="true"
              className="hidden"
              {...register("company")}
            />
            <Button type="submit" disabled={isSubmitting} className="whitespace-nowrap">
              {isSubmitting ? "Joining…" : "Join waitlist"}
            </Button>
          </form>
        )}

        {errors.email && !done && (
          <p id="email-error" className="mt-3 text-sm text-red-400">
            Please enter a valid email.
          </p>
        )}
        {serverError && !done && (
          <p className="mt-3 text-sm text-red-400">{serverError}</p>
        )}

        <p className="mt-8 text-sm text-white/50">
          Or{" "}
          <a href={githubUrl} target="_blank" rel="noreferrer" className="underline hover:text-white">
            view source on GitHub →
          </a>
        </p>
      </div>
    </section>
  );
}
```

- [ ] **Step 2: Commit**

```powershell
git add src/components/cta-waitlist.tsx
git commit -m "feat: add waitlist CTA form with confetti success and honeypot"
```

---

## Task 28: Build `Footer`

**Files:**
- Create: `src/components/footer.tsx`

- [ ] **Step 1: Write `src/components/footer.tsx`**

```tsx
import Image from "next/image";

const githubUrl = process.env.NEXT_PUBLIC_GITHUB_URL ?? "https://github.com/Qdevaan/Bubbles-AI";

export function Footer() {
  return (
    <footer className="border-t border-white/10 py-12 px-5 text-sm text-white/55">
      <div className="mx-auto max-w-6xl flex flex-col md:flex-row items-center justify-between gap-6">
        <div className="flex items-center gap-2">
          <Image src="/logo_dark.png" alt="" width={24} height={24} />
          <span className="font-semibold text-white">Bubbles</span>
          <span className="text-white/40">— Speak smarter.</span>
        </div>
        <ul className="flex flex-wrap gap-6">
          <li><a href="/about" className="hover:text-white">About</a></li>
          <li><a href={githubUrl} target="_blank" rel="noreferrer" className="hover:text-white">GitHub</a></li>
          <li><a href="mailto:hello@bubbles.ai" className="hover:text-white">Email</a></li>
        </ul>
      </div>
      <div className="mx-auto max-w-6xl mt-6 text-xs text-white/40 flex justify-between">
        <span>© {new Date().getFullYear()} Bubbles</span>
        <span>Made for FYP-II 2026</span>
      </div>
    </footer>
  );
}
```

- [ ] **Step 2: Commit**

```powershell
git add src/components/footer.tsx
git commit -m "feat: add minimal footer"
```

---

## Task 29: Add custom cursor (desktop, opt-in)

**Files:**
- Create: `src/components/cursor.tsx`

- [ ] **Step 1: Write `src/components/cursor.tsx`**

```tsx
"use client";

import { useEffect, useRef, useState } from "react";
import { usePrefersReducedMotion } from "@/lib/prefers-reduced-motion";

export function Cursor() {
  const dotRef = useRef<HTMLDivElement | null>(null);
  const ringRef = useRef<HTMLDivElement | null>(null);
  const reduced = usePrefersReducedMotion();
  const [enabled, setEnabled] = useState(false);

  useEffect(() => {
    if (reduced) return;
    if (window.matchMedia("(pointer: coarse)").matches) return;
    setEnabled(true);

    let mx = -100, my = -100;
    let rx = -100, ry = -100;

    function move(e: MouseEvent) {
      mx = e.clientX;
      my = e.clientY;
    }

    let raf = 0;
    function tick() {
      rx += (mx - rx) * 0.15;
      ry += (my - ry) * 0.15;
      if (dotRef.current) dotRef.current.style.transform = `translate(${mx - 4}px, ${my - 4}px)`;
      if (ringRef.current) ringRef.current.style.transform = `translate(${rx - 18}px, ${ry - 18}px)`;
      raf = requestAnimationFrame(tick);
    }

    function over(e: MouseEvent) {
      const t = e.target as HTMLElement | null;
      if (!t) return;
      const interactive = t.closest("a,button,input,[role=button]");
      ringRef.current?.classList.toggle("scale-150", !!interactive);
    }

    window.addEventListener("mousemove", move);
    window.addEventListener("mouseover", over);
    raf = requestAnimationFrame(tick);

    return () => {
      window.removeEventListener("mousemove", move);
      window.removeEventListener("mouseover", over);
      cancelAnimationFrame(raf);
    };
  }, [reduced]);

  if (!enabled) return null;

  return (
    <>
      <div
        ref={ringRef}
        className="pointer-events-none fixed top-0 left-0 z-[100] w-9 h-9 rounded-full border border-white/40 transition-transform duration-200 mix-blend-difference"
      />
      <div
        ref={dotRef}
        className="pointer-events-none fixed top-0 left-0 z-[100] w-2 h-2 rounded-full bg-white mix-blend-difference"
      />
    </>
  );
}
```

- [ ] **Step 2: Commit**

```powershell
git add src/components/cursor.tsx
git commit -m "feat: add custom cursor with hover detection (desktop only)"
```

---

## Task 30: Compose `app/page.tsx`

**Files:**
- Modify: `src/app/page.tsx`

- [ ] **Step 1: Replace `src/app/page.tsx`**

```tsx
import { Nav } from "@/components/nav";
import { Hero } from "@/components/hero";
import { ModesSection } from "@/components/modes-section";
import { TryPrompt } from "@/components/try-prompt";
import { FeaturesGrid } from "@/components/features-grid";
import { MemoryGraphSection } from "@/components/memory-graph-section";
import { HowItWorks } from "@/components/how-it-works";
import { TechSection } from "@/components/tech-section";
import { Faq } from "@/components/faq";
import { CtaWaitlist } from "@/components/cta-waitlist";
import { Footer } from "@/components/footer";
import { Cursor } from "@/components/cursor";

export default function Home() {
  return (
    <>
      <Cursor />
      <Nav />
      <main>
        <Hero />
        <ModesSection />
        <TryPrompt />
        <FeaturesGrid />
        <MemoryGraphSection />
        <HowItWorks />
        <TechSection />
        <Faq />
        <CtaWaitlist />
      </main>
      <Footer />
    </>
  );
}
```

- [ ] **Step 2: Run dev server and visit**

```powershell
npm run dev
```

Open `http://localhost:3000`. Walk through every section, verify:
- Hero gradient title animates
- CTAs are magnetic on hover
- Phone mockup tilts toward cursor + UI cycles
- Modes section sticky-scroll works
- Try-prompt typewriter runs on chip click
- Features grid hover glow
- Memory graph renders (after a moment)
- How-it-works path animates on scroll
- Tech section + GitHub link works
- FAQ accordion opens/closes
- Footer renders

Stop server.

- [ ] **Step 3: Commit**

```powershell
git add src/app/page.tsx
git commit -m "feat: compose landing page from all section components"
```

---

## Task 31: Add `/about` page

**Files:**
- Create: `src/app/about/page.tsx`

- [ ] **Step 1: Write `src/app/about/page.tsx`**

```tsx
import type { Metadata } from "next";
import Link from "next/link";
import { Nav } from "@/components/nav";
import { Footer } from "@/components/footer";
import { FadeUp } from "@/components/motion/fade-up";

export const metadata: Metadata = {
  title: "About — the technical deep dive",
  description: "Bubbles' architecture, stack, and FYP-II context.",
};

const githubUrl = process.env.NEXT_PUBLIC_GITHUB_URL ?? "https://github.com/Qdevaan/Bubbles-AI";

export default function AboutPage() {
  return (
    <>
      <Nav />
      <main className="pt-32 pb-24 px-5">
        <article className="mx-auto max-w-3xl prose prose-invert">
          <FadeUp>
            <h1 className="text-4xl md:text-6xl font-extrabold tracking-tightest text-white">
              About <span className="text-gradient">Bubbles</span>
            </h1>
          </FadeUp>

          <FadeUp delay={0.05}>
            <p className="text-white/70 mt-6">
              Bubbles is a final-year project (FYP-II 2026) building an AI conversation
              assistant. It runs on a Flutter client (Android, iOS, Web, Desktop) and a
              FastAPI backend that integrates Supabase, Groq, LiveKit, and embedding-based
              retrieval.
            </p>
          </FadeUp>

          <FadeUp delay={0.1}>
            <h2 className="mt-12 text-2xl font-bold text-white">Architecture</h2>
            <p className="text-white/70">
              Client authenticates via Supabase. Voice and chat events flow to FastAPI
              under <code>/v1</code>. The server orchestrates LLM calls, embedding lookups,
              graph updates, and session/analytics persistence. Real-time voice/video uses
              LiveKit token issuance.
            </p>
          </FadeUp>

          <FadeUp delay={0.15}>
            <h2 className="mt-12 text-2xl font-bold text-white">Stack</h2>
            <ul className="text-white/70">
              <li>Client: Flutter, Provider, Supabase Flutter, LiveKit, Picovoice (wake word).</li>
              <li>Server: FastAPI, Supabase Python, Groq, sentence-transformers, networkx, slowapi.</li>
              <li>Infra: Docker / Compose, Supabase Postgres + Storage.</li>
            </ul>
          </FadeUp>

          <FadeUp delay={0.2}>
            <h2 className="mt-12 text-2xl font-bold text-white">Where to look</h2>
            <ul className="text-white/70">
              <li>
                Source:{" "}
                <a className="underline" href={githubUrl} target="_blank" rel="noreferrer">
                  GitHub
                </a>
              </li>
              <li>
                Back to <Link className="underline" href="/">home</Link>
              </li>
            </ul>
          </FadeUp>
        </article>
      </main>
      <Footer />
    </>
  );
}
```

- [ ] **Step 2: Commit**

```powershell
git add src/app/about/page.tsx
git commit -m "feat: add /about technical deep-dive page"
```

---

## Task 32: Add `sitemap.ts` and `robots.ts`

**Files:**
- Create: `src/app/sitemap.ts`
- Create: `src/app/robots.ts`

- [ ] **Step 1: Write `src/app/sitemap.ts`**

```ts
import type { MetadataRoute } from "next";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "https://bubbles-ai.vercel.app";

export default function sitemap(): MetadataRoute.Sitemap {
  return [
    { url: `${siteUrl}/`, lastModified: new Date(), changeFrequency: "weekly", priority: 1 },
    { url: `${siteUrl}/about`, lastModified: new Date(), changeFrequency: "monthly", priority: 0.8 },
  ];
}
```

- [ ] **Step 2: Write `src/app/robots.ts`**

```ts
import type { MetadataRoute } from "next";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "https://bubbles-ai.vercel.app";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: "*", allow: "/" },
    sitemap: `${siteUrl}/sitemap.xml`,
  };
}
```

- [ ] **Step 3: Commit**

```powershell
git add src/app/sitemap.ts src/app/robots.ts
git commit -m "feat: add sitemap and robots routes"
```

---

## Task 33: API integration test against the route handler

**Files:**
- Create: `src/test/api-waitlist.test.ts`

- [ ] **Step 1: Write the failing test `src/test/api-waitlist.test.ts`**

```ts
import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("@/lib/supabase-server", () => {
  const insert = vi.fn().mockResolvedValue({ error: null });
  return {
    getSupabaseAdmin: () => ({
      from: () => ({ insert }),
    }),
    __insert: insert,
  };
});

import { POST } from "@/app/api/waitlist/route";

function makeReq(body: unknown, headers: Record<string, string> = {}): Request {
  return new Request("http://localhost/api/waitlist", {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

describe("POST /api/waitlist", () => {
  beforeEach(() => {
    process.env.NEXT_PUBLIC_SUPABASE_URL = "http://localhost";
    process.env.SUPABASE_SERVICE_ROLE_KEY = "test-key";
  });

  it("returns 200 ok for valid email", async () => {
    const res = await POST(makeReq({ email: "user@example.com" }, { "x-forwarded-for": "1.1.1.1" }));
    expect(res.status).toBe(200);
    const j = await res.json();
    expect(j.ok).toBe(true);
  });

  it("returns 400 for invalid email", async () => {
    const res = await POST(makeReq({ email: "nope" }, { "x-forwarded-for": "1.1.1.2" }));
    expect(res.status).toBe(400);
  });

  it("silently accepts honeypot fills", async () => {
    const res = await POST(
      makeReq({ email: "spam@example.com", company: "evil-corp" }, { "x-forwarded-for": "1.1.1.3" })
    );
    expect(res.status).toBe(200);
  });

  it("rate-limits the same IP after 5 hits", async () => {
    for (let i = 0; i < 5; i++) {
      await POST(makeReq({ email: `u${i}@example.com` }, { "x-forwarded-for": "9.9.9.9" }));
    }
    const res = await POST(makeReq({ email: "u6@example.com" }, { "x-forwarded-for": "9.9.9.9" }));
    expect(res.status).toBe(429);
  });
});
```

- [ ] **Step 2: Run tests**

```powershell
npm test
```

Expected: PASS — 4/4 new tests + earlier 9 pass.

- [ ] **Step 3: Commit**

```powershell
git add src/test/api-waitlist.test.ts
git commit -m "test: add /api/waitlist integration tests with mocked supabase"
```

---

## Task 34: Build production bundle locally + lint

**Files:** none

- [ ] **Step 1: Lint**

```powershell
npm run lint
```

Expected: no errors. Fix any reported issues before continuing.

- [ ] **Step 2: Type-check via build**

```powershell
npm run build
```

Expected: build succeeds with `Route (app) - / static, /about static, /api/waitlist dynamic`. No TS errors.

- [ ] **Step 3: Smoke test prod bundle**

```powershell
npm run start
```

Open `http://localhost:3000`, run through the same walkthrough as Task 30 Step 2, but on the production bundle. Verify no console errors. Stop server.

- [ ] **Step 4: Commit (if any small fixes were applied)**

```powershell
git status
```

If there are changes:

```powershell
git add -A
git commit -m "chore: lint/type fixes from production smoke pass"
```

Otherwise skip.

---

## Task 35: Pre-deploy manual QA checklist

**Files:** none — manual QA only.

- [ ] **Step 1: Lighthouse desktop**

In Chrome DevTools → Lighthouse → "Navigation" → Desktop. Target: Performance ≥ 90, Accessibility ≥ 90, SEO ≥ 90.

- [ ] **Step 2: Lighthouse mobile**

Same, switch to Mobile. Target: Performance ≥ 80, Accessibility ≥ 90.

- [ ] **Step 3: Responsive sweep**

DevTools device toolbar — verify layout at widths 320, 375, 414, 768, 1024, 1440. No horizontal scroll, no clipping.

- [ ] **Step 4: Reduced-motion test**

OS-level: enable "Reduce motion" (Windows: Settings → Accessibility → Visual effects → Animation effects off). Reload page. Confirm: aurora blobs static, phone UI does not auto-cycle, Lenis disabled (regular scroll), accordion still works.

- [ ] **Step 5: Keyboard nav**

Tab through entire page from top. Every interactive element should receive a visible focus ring. Submit waitlist with keyboard only.

- [ ] **Step 6: Slow 3G test**

DevTools → Network → "Slow 3G" throttling. Reload. Page should still render hero text within ~5s. Memory graph may load late — fine.

- [ ] **Step 7: OG card**

After deploy, paste production URL into [Twitter card validator](https://cards-dev.twitter.com/validator) and [opengraph.xyz](https://www.opengraph.xyz/). Confirm card renders.

(Skip step 7 until Task 37 deploy is live.)

---

## Task 36: Push to GitHub (when ready)

**Files:** none — git remote setup.

- [ ] **Step 1: Create GitHub repo via gh CLI**

```powershell
gh repo create Bubbles-AI-landing --public --source=. --remote=origin --description "Marketing landing page for Bubbles (FYP-II 2026)"
```

If `gh` is not authenticated, run `gh auth login` first.

- [ ] **Step 2: Push main**

```powershell
git push -u origin main
```

Expected: branch published; GitHub URL printed.

- [ ] **Step 3: Verify**

```powershell
gh repo view --web
```

---

## Task 37: Deploy to Vercel

**Files:** none — Vercel UI / CLI.

- [ ] **Step 1: Connect repo on Vercel**

Visit https://vercel.com/new → import `Bubbles-AI-landing` GitHub repo. Framework preset: Next.js (auto). Root directory: leave at repo root.

- [ ] **Step 2: Configure env vars in Vercel project settings**

Add (Production + Preview + Development):

- `NEXT_PUBLIC_SUPABASE_URL` = (existing Bubbles Supabase URL)
- `SUPABASE_SERVICE_ROLE_KEY` = (existing service-role key — Encrypted)
- `NEXT_PUBLIC_SITE_URL` = `https://<vercel-assigned-subdomain>.vercel.app` (update after first deploy)
- `NEXT_PUBLIC_GITHUB_URL` = `https://github.com/Qdevaan/Bubbles-AI-landing` (or whichever repo is the canonical link)

- [ ] **Step 3: Trigger deploy**

Click "Deploy". First build will be ~1-2 minutes. Resolve any failures by reading build log.

- [ ] **Step 4: Smoke test deployed URL**

Visit the assigned `.vercel.app` URL. Repeat key checks from Task 30 Step 2 against production. Submit waitlist with a real test email — confirm row appears in Supabase Studio under `public.waitlist`.

- [ ] **Step 5: Update `NEXT_PUBLIC_SITE_URL` env var**

Set it to the actual production URL, redeploy.

- [ ] **Step 6: Pre-deploy QA from Task 35**

Now run the Lighthouse + OG card checks against the live URL.

---

## Self-Review

**1. Spec coverage check:**

- §2 Architecture & Stack → Tasks 1, 2, 4
- §3 Visual design (palette, typography) → Task 4
- §4.1 Nav → Task 11
- §4.2 Hero (centered + bottom phone peek) → Tasks 12, 13
- §4.3 Modes (sticky scroll) → Task 14
- §4.4 Try a prompt → Task 15
- §4.5 Features grid → Task 16
- §4.6 Memory graph viz → Tasks 17, 18
- §4.7 How it works → Task 19
- §4.8 Tech / About → Tasks 20, 31
- §4.9 FAQ → Tasks 8 (accordion), 21
- §4.10 CTA / waitlist → Task 27
- §4.11 Footer → Task 28
- §4.12 /about page → Task 31
- §5 Animation strategy → Tasks 5, 6, 7, 29
- §6 Waitlist data flow → Tasks 22, 23, 24, 25, 26, 33
- §7 Deployment → Tasks 36, 37
- §8 SEO/metadata → Tasks 9, 32
- §9 Accessibility → Tasks 4 (reduced-motion CSS), 11 (skip via aria-expanded), 27 (form aria), 35 (manual QA)
- §10 Testing → Tasks 24, 25, 33

All spec sections have at least one corresponding task.

**2. Placeholder scan:**
- No "TBD" / "TODO" / "fill in" left in any task.
- No "similar to Task N" without inline code.
- All file paths fully qualified.

**3. Type consistency:**
- `WaitlistInput` defined in `src/lib/waitlist.ts` (Task 24), imported by `cta-waitlist.tsx` (Task 27) and used by route via `bodySchema.extend(...)` (Task 26). Names consistent.
- `AccordionItemData` defined in `src/components/ui/accordion.tsx` (Task 8), used in `faq.tsx` (Task 21). Consistent.
- `getSupabaseAdmin` used by route handler matches export in Task 23.
- `staggerItem` exported from `stagger.tsx` (Task 7), used in `tech-section.tsx` (Task 20). Consistent.

Plan is internally coherent.
