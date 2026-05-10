# History Search And Tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve session history discoverability by adding search and clear dual-tab navigation.

**Architecture:** Keep data-fetching behavior in existing history list widgets and enhance only the host screen UI state. Add a local search query state in `SessionsScreen`, then pass it into both `LiveSessionsList` and `ConsultantHistoryList` so filtering remains consistent.

**Tech Stack:** Flutter, Provider, existing `SessionsService` / `SessionsRepository`, glass-morphism design system.

---

### Task 1: Add Search UI To History Screen

**Files:**
- Modify: `lib/screens/sessions_screen.dart`

- [x] **Step 1: Add local search state and controller**
- [x] **Step 2: Render search input below header**
- [x] **Step 3: Wire change events to update query**
- [x] **Step 4: Pass normalized query to both list widgets**

### Task 2: Replace Filter Chips With Dual History Tabs

**Files:**
- Modify: `lib/screens/sessions_screen.dart`

- [x] **Step 1: Replace chip-filter layout with `DefaultTabController`**
- [x] **Step 2: Add `TabBar` with "Live Session History" and "Conversation History"**
- [x] **Step 3: Bind `TabBarView` to existing `LiveSessionsList` and `ConsultantHistoryList`**

### Task 3: Reflect Progress In Roadmap

**Files:**
- Modify: `todos.md`

- [x] **Step 1: Mark implemented history todos as completed**
- [x] **Step 2: Keep remaining roadmap items unchanged for future phases**

### Next Priority Candidates

- [ ] Roleplay mode consistency and prompt constraints (`server_v2/app/routes/consultant.py` + prompt builders).
- [ ] Conversation mode UX (Formal/Semi-Formal/Informal) and default persistence alignment.
- [ ] Session summaries/key points/share actions in history detail views.
- [ ] Entity graph deep-linking from history selections.
