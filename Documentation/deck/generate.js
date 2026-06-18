/* Bubbles FYP deck generator — Editorial Calm, projector-proof, editable PPTX.
   49 slides. On-slide text is sparse; detail lives in speaker notes. */
const pptxgen = require("pptxgenjs");
const p = new pptxgen();
p.defineLayout({ name: "W", width: 13.333, height: 7.5 });
p.layout = "W";
p.author = "Muhammad Ahmad & Attique Rehman";
p.company = "COMSATS University Islamabad — Lahore";
p.subject = "Bubbles — Smarter AI Assistant (FYP)";
p.title = "Bubbles FYP";

// ---- palette ----
const BG = "FAF8F4", INK = "1A1A1A", BODY = "3A3A3A", MUTE = "9A9285";
const TEAL = "0E7C86", TEALD = "0A5159", AMBER = "E08A2B", PANEL = "F0EBE1";
const CARD = "FFFFFF", TEALSOFT = "E4EFEF", LINE = "E3DCCF", RED = "C0492F", GREEN = "2F8F5B";
const HF = "Segoe UI", BF = "Segoe UI"; // header / body (Win11 native, editable)
const W = 13.333, H = 7.5, M = 0.62;
const LOGO = "assets/logo_dark.png";

const FOOT = "Bubbles  ·  FYP 2022–2026  ·  COMSATS Lahore";
let N = 0;

function base(dark = false) {
  const s = p.addSlide();
  s.background = { color: dark ? TEALD : BG };
  return s;
}
function bubble(s, x, y, d, col = TEAL, tr = 88) {
  s.addShape(p.ShapeType.ellipse, { x, y, w: d, h: d, fill: { color: col, transparency: tr }, line: { type: "none" } });
}
function footer(s, dark = false) {
  N++;
  s.addText(FOOT, { x: M, y: H - 0.42, w: 8, h: 0.3, fontFace: BF, fontSize: 9, color: dark ? "BFD8DB" : MUTE, align: "left", valign: "middle" });
  s.addText(String(N).padStart(2, "0"), { x: W - 1.3, y: H - 0.42, w: 0.7, h: 0.3, fontFace: BF, fontSize: 9, color: dark ? "BFD8DB" : MUTE, align: "right", valign: "middle" });
}
function kicker(s, txt, x = M, y = 0.62, col = TEAL) {
  s.addText(txt.toUpperCase(), { x, y, w: W - 2 * M, h: 0.34, fontFace: BF, fontSize: 12.5, bold: true, color: col, charSpacing: 2, align: "left" });
}
function title(s, txt, x = M, y = 0.96, w = W - 2 * M, size = 33, col = INK) {
  s.addText(txt, { x, y, w, h: 1.0, fontFace: HF, fontSize: size, bold: true, color: col, align: "left", lineSpacingMultiple: 0.98 });
}
function notes(s, t) { s.addNotes(t); }

// rounded card helper
function card(s, x, y, w, h, fill = CARD, lineCol = LINE) {
  s.addShape(p.ShapeType.roundRect, { x, y, w, h, rectRadius: 0.12, fill: { color: fill }, line: { color: lineCol, width: 1 }, shadow: { type: "outer", color: "BBB2A2", blur: 7, offset: 2, angle: 90, opacity: 0.22 } });
}
// straight line between two points (handles up-right via flipV)
function seg(s, x1, y1, x2, y2, col, w) {
  const x = Math.min(x1, x2), y = Math.min(y1, y2), ww = Math.abs(x2 - x1), hh = Math.abs(y2 - y1);
  const flip = ((x2 - x1) > 0) !== ((y2 - y1) > 0);
  s.addShape(p.ShapeType.line, { x, y, w: ww, h: hh, line: { color: col, width: w }, flipV: flip });
}

/* ============================ SLIDE BUILDERS ============================ */

// 1 — Title
(() => {
  const s = base();
  bubble(s, 10.6, -1.2, 4.2, TEAL, 86);
  bubble(s, 11.9, 1.7, 1.5, AMBER, 84);
  bubble(s, -0.9, 5.6, 3.0, TEAL, 90);
  s.addImage({ path: LOGO, x: M, y: 0.9, w: 1.5, h: 1.5 });
  s.addText("Bubbles", { x: M, y: 2.55, w: 10, h: 1.5, fontFace: HF, fontSize: 78, bold: true, color: INK });
  s.addText("Your AI conversation co-pilot — live coaching while you talk,\nand a smart assistant that remembers.", { x: M, y: 4.05, w: 9.6, h: 1.0, fontFace: BF, fontSize: 21, color: BODY, lineSpacingMultiple: 1.05 });
  s.addShape(p.ShapeType.rect, { x: M, y: 5.35, w: 1.5, h: 0.05, fill: { color: TEAL }, line: { type: "none" } });
  s.addText([
    { text: "Muhammad Ahmad", options: { bold: true } }, { text: "  FA22-BCS-025      " },
    { text: "Attique Rehman", options: { bold: true } }, { text: "  FA22-BCS-164" },
  ], { x: M, y: 5.55, w: 11, h: 0.4, fontFace: BF, fontSize: 14, color: INK });
  s.addText("Final Year Project · Mid Evaluation · BS Computer Science · COMSATS University Islamabad, Lahore Campus", { x: M, y: 6.05, w: 11.5, h: 0.4, fontFace: BF, fontSize: 12.5, color: MUTE });
  notes(s, "Greet the panel. Name the project in one breath: Bubbles is an AI that listens while you talk, whispers what to say next, and remembers everything so you can ask about it later. Two-person FYP. We'll show the problem, the solution, how it's built, and a live demo.");
})();

// 2 — Team & brief (two-column)
(() => {
  const s = base();
  kicker(s, "The team & the brief");
  title(s, "Two people. One split-stack build.");
  const cols = [
    { n: "Muhammad Ahmad", r: "FA22-BCS-025", role: "App · Architecture · Frontend", items: ["Flutter client across 6 platforms", "System architecture & data model", "Auth, UI/UX, caching, releases"] },
    { n: "Attique Rehman", r: "FA22-BCS-164", role: "AI · Backend · Memory systems", items: ["FastAPI brain & LLM router", "Knowledge graph + vector memory", "Real-time pipeline & workers"] },
  ];
  cols.forEach((c, i) => {
    const x = M + i * 6.1;
    card(s, x, 2.3, 5.7, 3.3);
    s.addShape(p.ShapeType.rect, { x: x, y: 2.3, w: 0.14, h: 3.3, fill: { color: i ? AMBER : TEAL }, line: { type: "none" } });
    s.addText(c.n, { x: x + 0.45, y: 2.58, w: 5, h: 0.45, fontFace: HF, fontSize: 22, bold: true, color: INK });
    s.addText(c.r + "   ·   " + c.role, { x: x + 0.45, y: 3.06, w: 5, h: 0.35, fontFace: BF, fontSize: 13, color: TEAL, bold: true });
    s.addText(c.items.map(t => ({ text: t, options: { bullet: { code: "2022" }, indentLevel: 0 } })), { x: x + 0.45, y: 3.55, w: 4.95, h: 1.85, fontFace: BF, fontSize: 15, color: BODY, lineSpacingMultiple: 1.2, paraSpaceAfter: 7 });
  });
  footer(s);
  notes(s, "Who did what. A clean two-person ownership boundary: Ahmad owns the client and architecture, Attique owns the AI brain and memory. R&D project, areas: AI, NLP, mobile. SDG: Quality Education.");
})();

// 3 — What is Bubbles (icon rows)
(() => {
  const s = base();
  kicker(s, "In plain English");
  title(s, "A friend in your ear — and a memory that lasts.");
  const rows = [
    { e: "Listens", d: "Hears the conversation as it happens, in real time." },
    { e: "Suggests", d: "Quietly whispers what to say next, so you never freeze." },
    { e: "Remembers", d: "Keeps your people and topics, so you can ask about them later." },
  ];
  rows.forEach((r, i) => {
    const y = 2.35 + i * 1.45;
    s.addShape(p.ShapeType.ellipse, { x: M, y, w: 1.0, h: 1.0, fill: { color: TEALSOFT }, line: { color: TEAL, width: 1.5 } });
    s.addText(String(i + 1), { x: M, y, w: 1.0, h: 1.0, fontFace: HF, fontSize: 30, bold: true, color: TEAL, align: "center", valign: "middle" });
    s.addText(r.e, { x: M + 1.3, y: y + 0.02, w: 4, h: 0.5, fontFace: HF, fontSize: 23, bold: true, color: INK });
    s.addText(r.d, { x: M + 1.3, y: y + 0.52, w: 10.5, h: 0.5, fontFace: BF, fontSize: 16, color: BODY });
  });
  bubble(s, 11.6, 5.4, 2.6, AMBER, 88);
  footer(s);
  notes(s, "Set the scene with a relatable moment — interview, viva, negotiation, tough call. You freeze, you fumble, and you only spot the mistake afterwards. Bubbles fixes the timing problem: it helps during, and remembers after.");
})();

// 4 — Big statement
(() => {
  const s = base();
  kicker(s, "The human problem");
  s.addText([
    { text: "Writing got autocorrect.\n", options: { color: BODY } },
    { text: "Speaking never did.", options: { color: TEAL } },
  ], { x: M, y: 2.4, w: 11.8, h: 2.4, fontFace: HF, fontSize: 52, bold: true, lineSpacingMultiple: 1.02 });
  s.addText("Speech happens in real time. We notice the wrong word or wrong tone only after the moment is gone.", { x: M, y: 5.0, w: 10.5, h: 0.8, fontFace: BF, fontSize: 18, color: BODY });
  bubble(s, 10.9, 0.2, 3.2, TEAL, 90);
  footer(s);
  notes(s, "Communication decides interviews, vivas, deals, relationships. Writing has Grammarly, spell-check, undo. Speech has nothing — the feedback always arrives too late. That asymmetry is the wound the whole project targets.");
})();

// 5 — Where the idea came from (3 sticky cards)
(() => {
  const s = base();
  kicker(s, "Where the idea came from");
  title(s, "We kept losing the moment.");
  const c = [
    { t: "The blank-out", d: "Froze mid-interview — knew the answer, couldn't get it out." },
    { t: "The forgotten promise", d: "Couldn't recall what a client actually agreed to last week." },
    { t: "The walk-home regret", d: "Realized the better phrasing only hours after it mattered." },
  ];
  c.forEach((it, i) => {
    const x = M + i * 4.07;
    card(s, x, 2.35, 3.75, 3.3, PANEL);
    s.addText("0" + (i + 1), { x: x + 0.35, y: 2.6, w: 2, h: 0.6, fontFace: HF, fontSize: 30, bold: true, color: TEAL });
    s.addText(it.t, { x: x + 0.35, y: 3.35, w: 3.1, h: 0.6, fontFace: HF, fontSize: 18, bold: true, color: INK });
    s.addText(it.d, { x: x + 0.35, y: 3.95, w: 3.15, h: 1.5, fontFace: BF, fontSize: 14.5, color: BODY, lineSpacingMultiple: 1.12 });
  });
  footer(s);
  notes(s, "Honest origin story. We weren't chasing a market — we hit this ourselves and confirmed it with classmates (introspection + peer interviews, our elicitation method). Three recurring failure moments became the seed.");
})();

// 6 — What exists (two buckets)
(() => {
  const s = base();
  kicker(s, "What already exists");
  title(s, "Two camps today — neither helps in the moment.");
  const b = [
    { t: "Meeting notetakers", names: "Otter · Fathom · Notta · Gong", d: "Transcribe & summarize — but only after the meeting ends." },
    { t: "General assistants", names: "Siri · Google Assistant · ChatGPT", d: "Answer commands — but forget you between sessions." },
  ];
  b.forEach((it, i) => {
    const x = M + i * 6.1;
    card(s, x, 2.3, 5.7, 3.5);
    s.addShape(p.ShapeType.rect, { x, y: 2.3, w: 5.7, h: 0.85, fill: { color: i ? "EFE3D2" : TEALSOFT }, line: { type: "none" } });
    s.addText(it.t, { x: x + 0.4, y: 2.4, w: 5, h: 0.65, fontFace: HF, fontSize: 20, bold: true, color: i ? AMBER : TEAL, valign: "middle" });
    s.addText(it.names, { x: x + 0.4, y: 3.4, w: 5, h: 0.5, fontFace: BF, fontSize: 16, bold: true, color: INK });
    s.addText(it.d, { x: x + 0.4, y: 4.0, w: 5, h: 1.4, fontFace: BF, fontSize: 15.5, color: BODY, lineSpacingMultiple: 1.15 });
  });
  footer(s);
  notes(s, "Two camps. Notetakers transcribe and summarize after the fact. Assistants answer commands but treat each chat as an island. Neither coaches you live, and neither remembers your people and topics across conversations.");
})();

// 7 — Three gaps
(() => {
  const s = base();
  kicker(s, "The research gap");
  title(s, "Three things nobody does together.");
  const g = [
    { t: "No real-time coaching", d: "Everything on the market is post-meeting analysis." },
    { t: "No long-term context", d: "Assistants forget who and what you talked about." },
    { t: "Not privacy-first", d: "Enterprise tools mine your data for the org, not you." },
  ];
  g.forEach((it, i) => {
    const y = 2.35 + i * 1.4;
    s.addShape(p.ShapeType.roundRect, { x: M, y, w: 0.95, h: 0.95, rectRadius: 0.1, fill: { color: "F7E2DC" }, line: { color: RED, width: 1.3 } });
    s.addText("✕", { x: M, y, w: 0.95, h: 0.95, fontFace: HF, fontSize: 30, bold: true, color: RED, align: "center", valign: "middle" });
    s.addText(it.t, { x: M + 1.25, y: y + 0.02, w: 11, h: 0.5, fontFace: HF, fontSize: 22, bold: true, color: INK });
    s.addText(it.d, { x: M + 1.25, y: y + 0.55, w: 11, h: 0.4, fontFace: BF, fontSize: 16, color: BODY });
  });
  footer(s);
  notes(s, "The formal research gap from our literature review. Otter/Gong analyze after the fact. Siri/ChatGPT forget across sessions. Enterprise tools are team-first and data-hungry. Nobody serves one user, improving one skill, privately, in the moment.");
})();

// 8 — Why after-the-meeting fails (timeline)
(() => {
  const s = base();
  kicker(s, "Why post-meeting isn't enough");
  title(s, "The value of advice decays in seconds.");
  s.addShape(p.ShapeType.line, { x: M + 0.2, y: 4.0, w: 10.9, h: 0, line: { color: LINE, width: 2.5 } });
  const pts = [{ x: 0.2, t: "Mistake made", c: RED, a: "left" }, { x: 5.6, t: "Conversation ends", c: MUTE, a: "center" }, { x: 11.1, t: "You read the summary", c: MUTE, a: "right" }];
  pts.forEach(pt => {
    s.addShape(p.ShapeType.ellipse, { x: M + pt.x - 0.18, y: 3.82, w: 0.36, h: 0.36, fill: { color: pt.c }, line: { type: "none" } });
    const lx = pt.a === "left" ? M + pt.x - 0.2 : (pt.a === "right" ? M + pt.x - 3.0 : M + pt.x - 1.6);
    s.addText(pt.t, { x: lx, y: 4.3, w: 3.2, h: 0.6, fontFace: BF, fontSize: 14, bold: true, color: INK, align: pt.a });
  });
  s.addText("Feedback only ever lands here →  too late to change the outcome.", { x: M, y: 5.4, w: 11.4, h: 0.5, fontFace: BF, fontSize: 17, italic: true, color: BODY });
  footer(s);
  notes(s, "Post-hoc notes are good for records, useless for the moment. Once the conversation is over, advice is worth almost nothing. Coaching has to happen during, not after.");
})();

// 9 — Problem statement (quote)
(() => {
  const s = base();
  kicker(s, "Problem statement");
  s.addShape(p.ShapeType.rect, { x: M, y: 2.3, w: 0.16, h: 3.0, fill: { color: TEAL }, line: { type: "none" } });
  s.addText("Success often depends on communication, yet errors are hard to catch while speaking. Existing AI only transcribes or summarizes after the fact — with no live, context-aware, privacy-respecting feedback.", { x: M + 0.5, y: 2.3, w: 11.0, h: 3.0, fontFace: HF, fontSize: 30, color: INK, italic: true, lineSpacingMultiple: 1.12, valign: "top" });
  bubble(s, 11.4, 5.2, 2.6, AMBER, 88);
  footer(s);
  notes(s, "Read this once, slowly. It is the single sentence the entire project answers.");
})();

// 10 — Why it matters
(() => {
  const s = base();
  kicker(s, "Why it matters");
  title(s, "Soft-skills coaching, made a daily habit.");
  s.addText("Like Duolingo — but for talking. Track progress, drill weak spots, reward improvement.", { x: M, y: 2.1, w: 11, h: 0.7, fontFace: BF, fontSize: 19, color: BODY });
  card(s, M, 3.1, 5.5, 2.5, TEALSOFT, TEAL);
  s.addText("SDG 4", { x: M + 0.4, y: 3.4, w: 4, h: 0.7, fontFace: HF, fontSize: 30, bold: true, color: TEAL });
  s.addText("Quality Education", { x: M + 0.4, y: 4.1, w: 4.6, h: 0.5, fontFace: HF, fontSize: 19, bold: true, color: INK });
  s.addText("Aligned to the UN Sustainable Development Goal we mapped this project to.", { x: M + 0.4, y: 4.6, w: 4.7, h: 0.9, fontFace: BF, fontSize: 13.5, color: BODY, lineSpacingMultiple: 1.1 });
  // rising curve on right
  const bx = 7.0, by = 5.5;
  s.addShape(p.ShapeType.line, { x: bx, y: 3.2, w: 0, h: by - 3.2, line: { color: LINE, width: 1.5 } });
  s.addShape(p.ShapeType.line, { x: bx, y: by, w: 5.0, h: 0, line: { color: LINE, width: 1.5 } });
  const cpts = [[0.1, 5.2], [1.3, 4.8], [2.5, 4.3], [3.7, 3.85], [4.9, 3.35]];
  for (let i = 1; i < cpts.length; i++) seg(s, bx + cpts[i - 1][0], cpts[i - 1][1], bx + cpts[i][0], cpts[i][1], TEAL, 3);
  cpts.forEach(pt => s.addShape(p.ShapeType.ellipse, { x: bx + pt[0] - 0.07, y: pt[1] - 0.07, w: 0.14, h: 0.14, fill: { color: TEAL }, line: { type: "none" } }));
  s.addText("Confidence over time", { x: bx, y: by + 0.12, w: 5, h: 0.4, fontFace: BF, fontSize: 13, italic: true, color: MUTE });
  footer(s);
  notes(s, "This maps to SDG Quality Education. We frame Bubbles as a habit-building skill app: measurable progress, targeted practice, and rewards for improvement — gamified communication growth for a single learner.");
})();

/* ---------------- SECTION 3: SOLUTION CONCEPT ---------------- */

// 11 — One-idea solution (flow)
(() => {
  const s = base();
  kicker(s, "The solution, in four verbs");
  title(s, "Listen → Whisper → Remember → Improve");
  const steps = ["Listen", "Whisper", "Remember", "Improve"];
  const sub = ["to the live conversation", "the next thing to say", "the people & topics", "from your real mistakes"];
  steps.forEach((t, i) => {
    const x = M + i * 3.05;
    card(s, x, 2.9, 2.7, 1.9, i % 2 ? PANEL : CARD);
    s.addShape(p.ShapeType.ellipse, { x: x + 1.0, y: 3.15, w: 0.7, h: 0.7, fill: { color: TEAL }, line: { type: "none" } });
    s.addText(String(i + 1), { x: x + 1.0, y: 3.15, w: 0.7, h: 0.7, fontFace: HF, fontSize: 20, bold: true, color: "FFFFFF", align: "center", valign: "middle" });
    s.addText(t, { x: x + 0.1, y: 3.95, w: 2.5, h: 0.45, fontFace: HF, fontSize: 18, bold: true, color: INK, align: "center" });
    s.addText(sub[i], { x: x + 0.15, y: 4.38, w: 2.4, h: 0.5, fontFace: BF, fontSize: 12, color: BODY, align: "center" });
    if (i < 3) s.addText("›", { x: x + 2.6, y: 2.9, w: 0.5, h: 1.9, fontFace: HF, fontSize: 30, bold: true, color: TEAL, align: "center", valign: "middle" });
  });
  footer(s);
  notes(s, "The whole product in four verbs. Everything technical that follows hangs off these four words.");
})();

// helper for phone-mock content slides
function modeSlide(kick, ttl, bullets, mockTitle, mockLines, notesTxt) {
  const s = base();
  kicker(s, kick);
  title(s, ttl);
  s.addText(bullets.map(t => ({ text: t, options: { bullet: { code: "2022" } } })), { x: M, y: 2.4, w: 7.2, h: 3.0, fontFace: BF, fontSize: 17.5, color: BODY, lineSpacingMultiple: 1.25, paraSpaceAfter: 12 });
  // phone mock
  const px = 9.2, pw = 3.2, py = 1.9, ph = 4.9;
  s.addShape(p.ShapeType.roundRect, { x: px, y: py, w: pw, h: ph, rectRadius: 0.25, fill: { color: "0E2A2E" }, line: { color: TEALD, width: 2 } });
  s.addShape(p.ShapeType.roundRect, { x: px + 0.15, y: py + 0.25, w: pw - 0.3, h: ph - 0.5, rectRadius: 0.15, fill: { color: BG }, line: { type: "none" } });
  s.addText(mockTitle, { x: px + 0.3, y: py + 0.45, w: pw - 0.6, h: 0.4, fontFace: HF, fontSize: 13, bold: true, color: TEAL });
  mockLines.forEach((ln, i) => {
    const my = py + 1.05 + i * 0.95;
    s.addShape(p.ShapeType.roundRect, { x: ln.me ? px + 0.9 : px + 0.3, y: my, w: ln.me ? pw - 1.2 : pw - 1.1, h: 0.8, rectRadius: 0.12, fill: { color: ln.me ? TEAL : (ln.tag ? "E8F4DC" : PANEL) }, line: { type: "none" } });
    s.addText(ln.t, { x: (ln.me ? px + 1.0 : px + 0.4), y: my + 0.05, w: pw - 1.35, h: 0.72, fontFace: BF, fontSize: 9.5, color: ln.me ? "FFFFFF" : INK, valign: "middle", lineSpacingMultiple: 0.95 });
  });
  footer(s);
  notes(s, notesTxt);
  return s;
}

// 12 — Wingman
modeSlide("Mode 1", "Live Wingman — coaches you while you talk.",
  ["Real-time advice generated from the live transcript", "Clarifying questions when the moment needs one", "Reacts to the other person — never echoes you back", "Pushed to screen over WebSocket, no flow break"],
  "Live Wingman",
  [{ t: "Other: What do you like in CS?" }, { t: "AI INSIGHT · advice", tag: 1 }, { t: "Ask a follow-up to learn their interest first.", tag: 1 }, { t: "I'm doing CS and…", me: 1 }],
  "Bubbles listens to the other person, decides if advice is worth giving, and pushes a short tip mid-conversation without breaking your flow. It only advises on what the OTHER person said — never parrots your own sentence back.");

// 13 — Consultant
modeSlide("Mode 2", "Consultant — ask anything about your past talks.",
  ["Deep, context-aware Q&A over your history", "“What did I promise Client X last week?”", "Streaming, blocking, or batched answers", "Backed by the heavy reasoning model"],
  "Consultant AI",
  [{ t: "What more did we talk about?", me: 1 }, { t: "You agreed to send the report by Friday and to loop in Asma." }, { t: "Remind me who Asma is", me: 1 }, { t: "Asma — the project manager on Project X." }],
  "After the fact, you interrogate your own history. Deep, context-aware Q&A — streaming or batched. This is where the big reasoning model in the router earns its keep.");

// 14 — Speak-improve loop
(() => {
  const s = base();
  kicker(s, "Mode 3");
  title(s, "Speak-Improve — the coaching loop.");
  const steps = ["Mistakes\ncaptured", "Turned into\ndrills", "Progress\ntracked", "Improvement\nrewarded"];
  const bw = 2.55, gap = 0.55;
  steps.forEach((t, i) => {
    const x = M + i * (bw + gap);
    s.addShape(p.ShapeType.roundRect, { x, y: 3.3, w: bw, h: 1.5, rectRadius: 0.12, fill: { color: i % 2 ? PANEL : TEALSOFT }, line: { color: TEAL, width: 1 } });
    s.addText(String(i + 1), { x: x + 0.15, y: 3.4, w: bw - 0.3, h: 0.45, fontFace: HF, fontSize: 18, bold: true, color: TEAL });
    s.addText(t, { x: x + 0.1, y: 3.85, w: bw - 0.2, h: 0.85, fontFace: HF, fontSize: 14.5, bold: true, color: INK, align: "center" });
    if (i < 3) s.addText("›", { x: x + bw, y: 3.3, w: gap, h: 1.5, fontFace: HF, fontSize: 26, bold: true, color: TEAL, align: "center", valign: "middle" });
  });
  s.addText("↺  and the loop repeats — every session feeds the next.", { x: M, y: 5.2, w: 12, h: 0.5, fontFace: BF, fontSize: 16, italic: true, color: TEALD });
  footer(s);
  notes(s, "Your real slip-ups become flashcards; you practice them; the dashboard shows you improving; gamification keeps you coming back. This closes the loop from feedback to measurable growth.");
})();

// 15 — Hybrid memory (comparison)
(() => {
  const s = base();
  kicker(s, "The differentiator");
  title(s, "Two memories, not one.");
  const cols = [
    { t: "Vector memory", d: "Finds semantically similar past moments — fuzzy recall.", e: "“sounds related”", c: TEAL },
    { t: "Knowledge graph", d: "Stores factual relationships between people & topics.", e: "User → knows → Asma", c: AMBER },
  ];
  cols.forEach((it, i) => {
    const x = M + i * 6.1;
    card(s, x, 2.3, 5.6, 3.3);
    s.addText(it.t, { x: x + 0.4, y: 2.55, w: 5, h: 0.5, fontFace: HF, fontSize: 21, bold: true, color: it.c });
    s.addText(it.d, { x: x + 0.4, y: 3.15, w: 5, h: 1.0, fontFace: BF, fontSize: 16, color: BODY, lineSpacingMultiple: 1.15 });
    s.addShape(p.ShapeType.roundRect, { x: x + 0.4, y: 4.4, w: 4.8, h: 0.8, rectRadius: 0.1, fill: { color: PANEL }, line: { type: "none" } });
    s.addText(it.e, { x: x + 0.4, y: 4.4, w: 4.8, h: 0.8, fontFace: BF, fontSize: 16, italic: true, bold: true, color: INK, align: "center", valign: "middle" });
  });
  s.addText("Fused before every answer", { x: M, y: 5.95, w: 11.4, h: 0.4, fontFace: BF, fontSize: 14, italic: true, color: MUTE, align: "center" });
  footer(s);
  notes(s, "Our core technical claim: a Hybrid Memory Architecture. Vector search finds semantically similar past moments; the knowledge graph stores factual relationships (User knows Asma; Asma manages Project X). We fuse both before answering.");
})();

// 16 — Why GraphRAG (comparison)
(() => {
  const s = base();
  kicker(s, "Why GraphRAG, not plain RAG");
  title(s, "Plain RAG sounds right. GraphRAG is right.");
  const cols = [
    { t: "Plain vector RAG", d: "Retrieves text that reads similar — can confuse two similar events and invent facts.", bad: 1 },
    { t: "Graph-augmented RAG", d: "Looks up hard relationships first (ego-graph around your entities) — anchors the answer.", bad: 0 },
  ];
  cols.forEach((it, i) => {
    const x = M + i * 6.1;
    card(s, x, 2.35, 5.6, 3.1, it.bad ? "F8ECE8" : "E9F3EC");
    s.addText((it.bad ? "✕  " : "✓  ") + it.t, { x: x + 0.4, y: 2.6, w: 5, h: 0.5, fontFace: HF, fontSize: 20, bold: true, color: it.bad ? RED : GREEN });
    s.addText(it.d, { x: x + 0.4, y: 3.25, w: 5, h: 1.9, fontFace: BF, fontSize: 16.5, color: BODY, lineSpacingMultiple: 1.2 });
  });
  footer(s);
  notes(s, "Plain vector RAG is fuzzy — it retrieves text that reads similar, which is how models hallucinate or confuse events. By forcing a graph lookup — a neighbor/ego-graph search around the entities in your question — we anchor answers to hard relationships vectors miss. This directly attacks hallucination.");
})();

// 17 — Thin client / heavy brain (weighted two-col)
(() => {
  const s = base();
  kicker(s, "A deliberate trade-off");
  title(s, "Thin client. Heavy brain.");
  card(s, M, 2.35, 4.2, 3.5, PANEL);
  s.addText("📱  The phone", { x: M + 0.4, y: 2.65, w: 3.5, h: 0.5, fontFace: HF, fontSize: 18, bold: true, color: INK });
  s.addText([{ text: "Microphone", options: { bullet: true } }, { text: "Screen", options: { bullet: true } }, { text: "Battery-light", options: { bullet: true } }], { x: M + 0.4, y: 3.35, w: 3.4, h: 2.3, fontFace: BF, fontSize: 16, color: BODY, lineSpacingMultiple: 1.35, paraSpaceAfter: 6 });
  s.addText("→", { x: 5.0, y: 3.7, w: 1.0, h: 0.8, fontFace: HF, fontSize: 36, bold: true, color: TEAL, align: "center" });
  card(s, 6.1, 2.35, 6.5, 3.5, TEALSOFT, TEAL);
  s.addText("☁  The cloud brain", { x: 6.5, y: 2.65, w: 5.5, h: 0.5, fontFace: HF, fontSize: 18, bold: true, color: TEAL });
  s.addText([{ text: "All AI: STT, LLM router, memory, graph", options: { bullet: true } }, { text: "Models stay swappable, not baked into the app", options: { bullet: true } }, { text: "Same experience on a cheap phone", options: { bullet: true } }], { x: 6.5, y: 3.35, w: 5.8, h: 2.3, fontFace: BF, fontSize: 16.5, color: BODY, lineSpacingMultiple: 1.35, paraSpaceAfter: 6 });
  footer(s);
  notes(s, "We deliberately keep the phone a thin client — saves battery, keeps models swappable, runs the same on a cheap phone. Trade-off: it needs internet (an explicit constraint). We accepted that because real-time SOTA models don't fit on-device yet.");
})();

/* ---------------- SECTION 4: ARCHITECTURE ---------------- */

// 18 — Section divider
function divider(num, txt, sub) {
  const s = base(true);
  bubble(s, 10.4, -1.4, 4.6, "FFFFFF", 92);
  bubble(s, -1.0, 5.0, 3.4, AMBER, 80);
  s.addText("PART " + num, { x: M, y: 2.7, w: 6, h: 0.5, fontFace: BF, fontSize: 16, bold: true, color: "9FD0D4", charSpacing: 3 });
  s.addText(txt, { x: M, y: 3.2, w: 11.5, h: 1.6, fontFace: HF, fontSize: 46, bold: true, color: "FFFFFF", lineSpacingMultiple: 1.0 });
  if (sub) s.addText(sub, { x: M, y: 4.8, w: 10.5, h: 0.6, fontFace: BF, fontSize: 18, bold: true, color: "EAF6F7" });
  footer(s, true);
  return s;
}
divider("04", "How it actually works.", "Three tiers, one clean data path.");

// 19 — 3-tier architecture
(() => {
  const s = base();
  kicker(s, "Architecture at a glance");
  title(s, "Three tiers, top to bottom.");
  const tiers = [
    { t: "Client — Flutter", d: "Screens · State · Repositories · Cache · Services", c: TEAL },
    { t: "Backend — Brain API (FastAPI)", d: "Auth · LLM Router · Endpoints · ARQ Workers", c: AMBER },
    { t: "Data & AI", d: "Postgres + pgvector · Redis · Gemini/Cerebras/Groq · LiveKit", c: TEALD },
  ];
  tiers.forEach((it, i) => {
    const y = 2.35 + i * 1.45;
    s.addShape(p.ShapeType.roundRect, { x: M, y, w: 11.4, h: 1.2, rectRadius: 0.12, fill: { color: i === 1 ? PANEL : (i === 2 ? "E9EEEC" : TEALSOFT) }, line: { color: it.c, width: 1.4 } });
    s.addShape(p.ShapeType.rect, { x: M, y, w: 0.16, h: 1.2, fill: { color: it.c }, line: { type: "none" } });
    s.addText(it.t, { x: M + 0.45, y: y + 0.18, w: 11, h: 0.5, fontFace: HF, fontSize: 19, bold: true, color: INK });
    s.addText(it.d, { x: M + 0.45, y: y + 0.66, w: 11, h: 0.4, fontFace: BF, fontSize: 15, color: BODY });
    if (i < 2) s.addText("▼", { x: 6.5, y: y + 1.18, w: 0.5, h: 0.3, fontFace: BF, fontSize: 13, color: MUTE, align: "center" });
  });
  footer(s);
  notes(s, "Walk the three tiers once, top to bottom. Everything in this section zooms into one box of this picture — tell the panel that up front so they don't get lost.");
})();

// 20 — One codebase, six platforms
(() => {
  const s = base();
  kicker(s, "The client");
  title(s, "One codebase → six platforms.");
  const plats = ["Android", "iOS", "Web", "Windows", "macOS", "Linux"];
  s.addShape(p.ShapeType.roundRect, { x: M, y: 2.7, w: 2.6, h: 1.4, rectRadius: 0.12, fill: { color: TEAL }, line: { type: "none" } });
  s.addText("Flutter\n· Dart ·", { x: M, y: 2.7, w: 2.6, h: 1.4, fontFace: HF, fontSize: 20, bold: true, color: "FFFFFF", align: "center", valign: "middle" });
  plats.forEach((pl, i) => {
    const x = 4.2 + (i % 3) * 3.0, y = 2.45 + Math.floor(i / 3) * 1.6;
    s.addShape(p.ShapeType.roundRect, { x, y, w: 2.7, h: 1.3, rectRadius: 0.1, fill: { color: CARD }, line: { color: LINE, width: 1 } });
    s.addText(pl, { x, y, w: 2.7, h: 1.3, fontFace: HF, fontSize: 18, bold: true, color: INK, align: "center", valign: "middle" });
  });
  s.addText("25+ screens · 11 repositories · 25 services · offline-first stale-while-revalidate cache over SQLite", { x: M, y: 6.0, w: 12, h: 0.5, fontFace: BF, fontSize: 14, italic: true, color: MUTE });
  footer(s);
  notes(s, "Layered client: Screens → State (Riverpod/Provider) → Repositories → custom cache → Services. 25+ screens, 11 repositories, 25 services. Offline-first via a stale-while-revalidate cache over local SQLite.");
})();

// 21 — Why Flutter (table)
(() => {
  const s = base();
  kicker(s, "Why Flutter");
  title(s, "Why not native or React Native?");
  const head = ["Approach", "Verdict", "Why"];
  const data = [
    ["Flutter", "✓ Chosen", "One Dart codebase, true desktop, 60fps custom UI"],
    ["Native (×2)", "✕", "Two-person team can't build & maintain 6 native apps"],
    ["React Native", "✕", "JS-bridge overhead, weak desktop story"],
  ];
  const trows = [head.map(h => ({ text: h, options: { fontFace: HF, fontSize: 15, bold: true, color: "FFFFFF", fill: { color: TEAL }, valign: "middle" } }))];
  data.forEach((r, ri) => {
    trows.push(r.map((c, ci) => ({ text: c, options: { fontFace: BF, fontSize: 15.5, bold: ci === 0, color: ci === 1 ? (c.includes("✓") ? GREEN : RED) : INK, fill: { color: ri % 2 ? CARD : PANEL }, valign: "middle", align: ci === 1 ? "center" : "left" } })));
  });
  s.addTable(trows, { x: M, y: 2.5, w: 12.1, colW: [3.0, 2.0, 7.1], rowH: [0.6, 0.85, 0.85, 0.85], border: { type: "solid", color: LINE, pt: 1 } });
  footer(s);
  notes(s, "Two-person team — we can't build and maintain six native apps. Flutter gives one Dart codebase, real desktop targets, and smooth custom UI. React Native's JS bridge and thin desktop story ruled it out.");
})();

// 22 — Backend endpoint chips
(() => {
  const s = base();
  kicker(s, "The backend brain");
  title(s, "Async, top to bottom — 40+ endpoints under /v1.");
  const chips = ["Sessions", "Wingman", "Consultant", "Voice", "Speaker ID", "Grammar", "Drills", "Scenarios", "Gamification", "Dashboard", "Entities", "Memory", "Persona"];
  chips.forEach((c, i) => {
    const x = M + (i % 4) * 3.0, y = 2.5 + Math.floor(i / 4) * 0.85;
    s.addShape(p.ShapeType.roundRect, { x, y, w: 2.8, h: 0.65, rectRadius: 0.32, fill: { color: i % 2 ? TEALSOFT : CARD }, line: { color: TEAL, width: 1 } });
    s.addText(c, { x, y, w: 2.8, h: 0.65, fontFace: BF, fontSize: 14.5, bold: true, color: TEALD, align: "center", valign: "middle" });
  });
  s.addText("Python 3.12 · FastAPI on Uvicorn/Gunicorn · Pydantic v2 validates every request & response", { x: M, y: 6.1, w: 12, h: 0.5, fontFace: BF, fontSize: 14, italic: true, color: MUTE });
  footer(s);
  notes(s, "Python 3.12 + FastAPI on Uvicorn/Gunicorn. Fully async, so one server juggles many live audio streams. 40-plus endpoints under /v1, grouped by feature. Pydantic v2 validates everything.");
})();

// 23 — Why async (comparison)
(() => {
  const s = base();
  kicker(s, "Why FastAPI async");
  title(s, "Real-time audio needs non-blocking I/O.");
  const cols = [{ t: "Sync (Flask/Django)", d: "One worker blocks per audio stream → doesn't scale.", bad: 1 }, { t: "Async (FastAPI)", d: "Await network/LLM calls without freezing the server. Typed schemas + auto OpenAPI for free.", bad: 0 }];
  cols.forEach((it, i) => {
    const x = M + i * 6.1;
    card(s, x, 2.4, 5.6, 3.0, it.bad ? "F8ECE8" : "E9F3EC");
    s.addText((it.bad ? "✕  " : "✓  ") + it.t, { x: x + 0.4, y: 2.65, w: 5, h: 0.5, fontFace: HF, fontSize: 19, bold: true, color: it.bad ? RED : GREEN });
    s.addText(it.d, { x: x + 0.4, y: 3.3, w: 5, h: 1.9, fontFace: BF, fontSize: 16.5, color: BODY, lineSpacingMultiple: 1.2 });
  });
  footer(s);
  notes(s, "Django/Flask are sync-first; blocking a worker per audio stream doesn't scale. FastAPI's async lets us await network and LLM calls without freezing the server, and gives typed schemas plus auto-generated OpenAPI docs for free.");
})();

// 24 — Router table
(() => {
  const s = base();
  kicker(s, "The LLM router");
  title(s, "Each task → the model that fits it.");
  const head = ["Task", "Model", "Provider chain"];
  const data = [
    ["Consultant Q&A", "gemini-2.5-flash", "Gemini → Cerebras → Groq"],
    ["Wingman (live advice)", "llama-3.1-8b", "Cerebras → Groq → Gemini"],
    ["Speech-to-text", "whisper-large-v3-turbo", "Groq"],
    ["Embeddings", "text-embedding-004", "Gemini (ONNX fallback)"],
  ];
  const trows = [head.map(h => ({ text: h, options: { fontFace: HF, fontSize: 15, bold: true, color: "FFFFFF", fill: { color: TEAL }, valign: "middle" } }))];
  data.forEach((r, ri) => {
    trows.push(r.map((c, ci) => ({ text: c, options: { fontFace: BF, fontSize: 15, bold: ci === 0, color: INK, fill: { color: ri % 2 ? CARD : PANEL }, valign: "middle" } })));
  });
  s.addTable(trows, { x: M, y: 2.5, w: 12.1, colW: [3.5, 3.6, 5.0], rowH: [0.6, 0.75, 0.75, 0.75, 0.75], border: { type: "solid", color: LINE, pt: 1 } });
  s.addText("Per-provider circuit breakers: a failing provider trips its breaker and we fail over instantly.", { x: M, y: 6.1, w: 12, h: 0.5, fontFace: BF, fontSize: 14, italic: true, color: TEALD });
  footer(s);
  notes(s, "Each task is routed to the model that fits it — fast 8B for live advice, a bigger model for deep Q&A. Per-provider circuit breakers: if a provider starts failing, we trip the breaker and fail over to the next instantly.");
})();

// 25 — Why multi-provider (comparison)
(() => {
  const s = base();
  kicker(s, "Why multi-provider");
  title(s, "No single point of failure.");
  const cols = [{ t: "One provider", d: "One outage kills the app. One price hike traps you. One model is wrong for some tasks.", bad: 1 }, { t: "Three providers, routed", d: "Right model per job, automatic failover, no vendor lock-in.", bad: 0 }];
  cols.forEach((it, i) => {
    const x = M + i * 6.1;
    card(s, x, 2.4, 5.6, 3.0, it.bad ? "F8ECE8" : "E9F3EC");
    s.addText((it.bad ? "✕  " : "✓  ") + it.t, { x: x + 0.4, y: 2.65, w: 5, h: 0.5, fontFace: HF, fontSize: 19, bold: true, color: it.bad ? RED : GREEN });
    s.addText(it.d, { x: x + 0.4, y: 3.3, w: 5, h: 1.9, fontFace: BF, fontSize: 16.5, color: BODY, lineSpacingMultiple: 1.2 });
  });
  footer(s);
  notes(s, "One provider means one outage kills the app, one price hike traps you, one model is wrong for some tasks. Splitting by task lets us use a fast 8B for live advice (latency) and a big model for deep Q&A (quality), with automatic failover for uptime.");
})();

// helper: horizontal flow
function flowSlide(kick, ttl, steps, notesTxt) {
  const s = base();
  kicker(s, kick);
  title(s, ttl);
  const n = steps.length, gap = 0.45, totalW = 12.1, bw = (totalW - gap * (n - 1)) / n;
  steps.forEach((st, i) => {
    const x = M + i * (bw + gap);
    card(s, x, 3.0, bw, 2.0, i % 2 ? PANEL : TEALSOFT);
    s.addText(String(i + 1), { x: x + 0.15, y: 3.15, w: bw - 0.3, h: 0.5, fontFace: HF, fontSize: 22, bold: true, color: TEAL });
    s.addText(st.t, { x: x + 0.15, y: 3.7, w: bw - 0.3, h: 0.5, fontFace: HF, fontSize: 15.5, bold: true, color: INK });
    s.addText(st.d, { x: x + 0.15, y: 4.18, w: bw - 0.3, h: 0.7, fontFace: BF, fontSize: 12, color: BODY, lineSpacingMultiple: 1.05 });
    if (i < n - 1) s.addText("›", { x: x + bw, y: 3.0, w: gap, h: 2.0, fontFace: HF, fontSize: 24, bold: true, color: TEAL, align: "center", valign: "middle" });
  });
  footer(s);
  notes(s, notesTxt);
}

// 26 — Voice pipeline
flowSlide("Voice pipeline", "Wake-word → speech → advice → voice.",
  [{ t: "Wake-word", d: "Porcupine, on-device" }, { t: "Transport", d: "LiveKit low-latency audio" }, { t: "STT", d: "Groq Whisper turbo" }, { t: "Speaker ID", d: "you vs. them" }, { t: "TTS", d: "Edge-TTS speaks back" }],
  "Porcupine wake-word runs on-device. LiveKit carries low-latency audio. Groq Whisper transcribes. Speaker enrollment/identification separates you from them. Edge-TTS speaks responses back.");

// 27 — KG construction
flowSlide("Knowledge graph", "Transcript → entities → relationships → graph.",
  [{ t: "Transcript", d: "live text" }, { t: "Extract", d: "fast LLM finds people/topics" }, { t: "Model", d: "NetworkX nodes + edges" }, { t: "Persist", d: "Postgres link tables" }, { t: "Explore", d: "interactive timeline" }],
  "As you talk, the fast LLM pulls out people, topics and events as nodes, and their relationships as edges, modeled with NetworkX and persisted in Postgres link tables. You can browse it as an interactive graph.");

// 28 — Workers (two lanes)
(() => {
  const s = base();
  kicker(s, "Background workers (ARQ)");
  title(s, "Heavy work happens off the critical path.");
  card(s, M, 2.45, 11.4, 1.25, "E9F3EC", GREEN);
  s.addText("HOT PATH  ·  stays fast", { x: M + 0.4, y: 2.6, w: 6, h: 0.4, fontFace: HF, fontSize: 14, bold: true, color: GREEN });
  s.addText("Live advice generation — the only thing on the main thread.", { x: M + 0.4, y: 3.05, w: 10, h: 0.5, fontFace: BF, fontSize: 16, color: BODY });
  card(s, M, 4.05, 11.4, 1.95, PANEL);
  s.addText("BACKGROUND  ·  12 idempotent jobs", { x: M + 0.4, y: 4.22, w: 8, h: 0.4, fontFace: HF, fontSize: 14, bold: true, color: AMBER });
  s.addText("Embeddings · grammar scan · sentiment · knowledge extraction · rolling summaries · session analytics · drill cards · scenarios · achievements · reminders", { x: M + 0.4, y: 4.68, w: 10.7, h: 1.2, fontFace: BF, fontSize: 15.5, color: BODY, lineSpacingMultiple: 1.2 });
  footer(s);
  notes(s, "Everything expensive runs in Redis-backed ARQ workers, idempotent so a retry never double-counts. Only live advice stays on the hot path. The result: rich features without slowing the real-time loop.");
})();

/* ---------------- SECTION 5: REAL-TIME CHALLENGE ---------------- */

// 29 — Latency wall
(() => {
  const s = base();
  kicker(s, "The real-time challenge");
  title(s, "Chained, it took 3–5 seconds.");
  ["STT", "Vector search", "LLM", "Response"].forEach((t, i) => {
    const x = M + i * 3.0;
    s.addShape(p.ShapeType.roundRect, { x, y: 3.2, w: 2.6, h: 1.0, rectRadius: 0.1, fill: { color: "F8ECE8" }, line: { color: RED, width: 1.2 } });
    s.addText(t, { x, y: 3.2, w: 2.6, h: 1.0, fontFace: HF, fontSize: 16, bold: true, color: INK, align: "center", valign: "middle" });
    if (i < 3) s.addText("→", { x: x + 2.55, y: 3.2, w: 0.5, h: 1.0, fontFace: HF, fontSize: 22, bold: true, color: RED, align: "center", valign: "middle" });
  });
  s.addText("Conversation needs ", { x: M, y: 4.9, w: 4.5, h: 0.6, fontFace: BF, fontSize: 20, color: BODY });
  s.addText("< 1 second.", { x: 4.4, y: 4.85, w: 3, h: 0.7, fontFace: HF, fontSize: 26, bold: true, color: RED });
  s.addText("3–5 s of dead air is useless mid-talk.", { x: 6.6, y: 4.9, w: 6, h: 0.6, fontFace: BF, fontSize: 16, italic: true, color: MUTE });
  footer(s);
  notes(s, "Our first naive Wingman chained everything serially: speech-to-text, then vector search, then the LLM, then response. 3 to 5 seconds of dead air — useless in a live conversation.");
})();

// 30 — Beat it (before/after big stat)
(() => {
  const s = base();
  kicker(s, "How we beat it");
  title(s, "Parallel pipeline + Groq LPU.");
  card(s, M, 2.5, 5.5, 2.4, PANEL);
  s.addText("Before", { x: M + 0.4, y: 2.7, w: 4, h: 0.4, fontFace: HF, fontSize: 15, bold: true, color: MUTE });
  s.addText("~2 s", { x: M + 0.4, y: 3.1, w: 4.7, h: 1.2, fontFace: HF, fontSize: 60, bold: true, color: RED });
  s.addText("serial chain, big model", { x: M + 0.4, y: 4.35, w: 4.7, h: 0.4, fontFace: BF, fontSize: 13, color: BODY });
  s.addText("→", { x: 6.3, y: 3.2, w: 0.9, h: 1.0, fontFace: HF, fontSize: 40, bold: true, color: TEAL, align: "center" });
  card(s, 7.3, 2.5, 5.4, 2.4, "E9F3EC", GREEN);
  s.addText("After", { x: 7.7, y: 2.7, w: 4, h: 0.4, fontFace: HF, fontSize: 15, bold: true, color: GREEN });
  s.addText("~300 ms", { x: 7.7, y: 3.1, w: 4.7, h: 1.2, fontFace: HF, fontSize: 60, bold: true, color: GREEN });
  s.addText("hot path only + 8B on Groq LPU", { x: 7.7, y: 4.35, w: 4.7, h: 0.4, fontFace: BF, fontSize: 13, color: BODY });
  s.addText("Only advice stays on the main thread; knowledge extraction & memory-saving become fire-and-forget.", { x: M, y: 5.3, w: 12, h: 0.6, fontFace: BF, fontSize: 16, color: BODY });
  footer(s);
  notes(s, "We re-architected: only advice generation stays on the hot path; knowledge extraction and memory saving became fire-and-forget background jobs. Switching the live tier to an 8B model on Groq's LPU dropped inference from about 2 seconds to about 300 milliseconds.");
})();

// 31 — Diarization
(() => {
  const s = base();
  kicker(s, "Challenge: who said what");
  title(s, "Advise on their words — not yours.");
  const lines = [{ who: "Other", t: "Can you explain your hobbies?", me: 0 }, { who: "You", t: "I'm doing CS and… stuff.", me: 1 }, { who: "Other", t: "What do you like in CS?", me: 0 }];
  lines.forEach((ln, i) => {
    const y = 2.6 + i * 0.95;
    s.addShape(p.ShapeType.roundRect, { x: ln.me ? 6.8 : M, y, w: 5.7, h: 0.75, rectRadius: 0.12, fill: { color: ln.me ? TEAL : PANEL }, line: { type: "none" } });
    s.addText([{ text: ln.who + "  ", options: { bold: true, color: ln.me ? "CFE6E8" : TEAL } }, { text: ln.t, options: { color: ln.me ? "FFFFFF" : INK } }], { x: (ln.me ? 6.8 : M) + 0.3, y, w: 5.1, h: 0.75, fontFace: BF, fontSize: 16, valign: "middle" });
  });
  s.addText("We parse word-level timestamps to split User vs. Other — Wingman reacts to the other person only.", { x: M, y: 5.7, w: 12, h: 0.6, fontFace: BF, fontSize: 16, italic: true, color: BODY });
  footer(s);
  notes(s, "A single mic stream merges speakers and confuses the AI. We parse the word-level timestamps to split User from Other, so Wingman reacts to what the other person said — not your own sentence echoing back.");
})();

// 32 — Hallucination + state (two cards)
(() => {
  const s = base();
  kicker(s, "Two more hard problems");
  title(s, "Hallucination & lost state.");
  const c = [
    { t: "Hallucination", d: "Force graph facts first, plus a strict prompt: “If it's not in the context, say you don't know.”" },
    { t: "Lost state", d: "Stateless HTTP forgets mid-talk. Hold live context in RAM (fast) and persist to Supabase (reliable)." },
  ];
  c.forEach((it, i) => {
    const x = M + i * 6.1;
    card(s, x, 2.5, 5.6, 3.0);
    s.addShape(p.ShapeType.rect, { x, y: 2.5, w: 5.6, h: 0.12, fill: { color: i ? AMBER : TEAL }, line: { type: "none" } });
    s.addText(it.t, { x: x + 0.4, y: 2.8, w: 5, h: 0.5, fontFace: HF, fontSize: 21, bold: true, color: INK });
    s.addText(it.d, { x: x + 0.4, y: 3.45, w: 5, h: 1.9, fontFace: BF, fontSize: 16.5, color: BODY, lineSpacingMultiple: 1.2 });
  });
  footer(s);
  notes(s, "Hallucination: we force graph facts first and add a strict system prompt that tells the model to admit when it doesn't know. State: HTTP is stateless and forgets mid-conversation, so we hold live context in RAM for speed while persisting it to Supabase for reliability.");
})();

// 33 — Reliability (icon rows)
(() => {
  const s = base();
  kicker(s, "Built for reliability");
  title(s, "Production guardrails, not a demo script.");
  const items = [["Circuit breakers", "isolate a failing provider"], ["Token-bucket rate limiting", "Redis Lua, per user"], ["Retries with back-off", "Tenacity on transient faults"], ["Idempotent jobs", "a retry never double-fires"], ["ULID IDs", "sortable, collision-safe"]];
  items.forEach((it, i) => {
    const y = 2.4 + i * 0.82;
    s.addShape(p.ShapeType.ellipse, { x: M, y, w: 0.6, h: 0.6, fill: { color: TEALSOFT }, line: { color: TEAL, width: 1.3 } });
    s.addText("✓", { x: M, y, w: 0.6, h: 0.6, fontFace: HF, fontSize: 16, bold: true, color: TEAL, align: "center", valign: "middle" });
    s.addText([{ text: it[0] + "  —  ", options: { bold: true, color: INK } }, { text: it[1], options: { color: BODY } }], { x: M + 0.9, y, w: 11, h: 0.6, fontFace: BF, fontSize: 17, valign: "middle" });
  });
  footer(s);
  notes(s, "This isn't a demo script — it has production guardrails. Failures isolate, retries are safe, jobs never double-fire, abuse is rate-limited, and IDs are sortable and collision-safe.");
})();

/* ---------------- SECTION 6: FEATURES ---------------- */

// 34 — Feature map
(() => {
  const s = base();
  kicker(s, "What's built");
  title(s, "Ten features — all live in the app.");
  const f = ["Live Wingman", "Consultant", "Confidence meter", "Spaced-repetition drills", "Progress dashboard", "Roleplay scenarios", "Gamification", "Knowledge-graph explorer", "Grammar & sentiment", "Voice & speaker ID"];
  f.forEach((c, i) => {
    const x = M + (i % 5) * 2.42, y = 2.6 + Math.floor(i / 5) * 1.4;
    s.addShape(p.ShapeType.roundRect, { x, y, w: 2.25, h: 1.2, rectRadius: 0.1, fill: { color: i % 2 ? TEALSOFT : CARD }, line: { color: TEAL, width: 1 } });
    s.addText(c, { x: x + 0.1, y, w: 2.05, h: 1.2, fontFace: HF, fontSize: 13.5, bold: true, color: TEALD, align: "center", valign: "middle" });
  });
  s.addText("We'll deep-dive four that show real engineering — then a live demo.", { x: M, y: 5.7, w: 12, h: 0.5, fontFace: BF, fontSize: 15, italic: true, color: MUTE });
  footer(s);
  notes(s, "Breadth shot — every one of these has a real screen and a wired endpoint. We'll deep-dive four that show genuine engineering, not just UI. LIVE DEMO CUE: this is a good point to switch to the app — start a Wingman session, show an insight card, end it, ask the Consultant about it, show the graph, open the dashboard. Keep screenshot fallback ready.");
})();

// 35 — Confidence meter
(() => {
  const s = base();
  kicker(s, "Live Confidence Meter");
  title(s, "On-device, zero added latency.");
  s.addText([{ text: "Counts filler words (“um”, “uh”, “like”) and hedges (“sort of”, “I guess”) over a rolling 8 seconds — smoothed so it doesn't jitter.", options: {} }], { x: M, y: 2.3, w: 12, h: 1.0, fontFace: BF, fontSize: 17, color: BODY, lineSpacingMultiple: 1.2 });
  const bands = [["Low", RED, "F7DAD2"], ["Building", AMBER, "F7E9CF"], ["Confident", GREEN, "D8EEDF"]];
  bands.forEach((b, i) => {
    const x = M + i * 4.05;
    s.addShape(p.ShapeType.roundRect, { x, y: 3.7, w: 3.75, h: 1.4, rectRadius: 0.12, fill: { color: b[2] }, line: { color: b[1], width: 1.4 } });
    s.addText(b[0], { x, y: 3.95, w: 3.75, h: 0.6, fontFace: HF, fontSize: 22, bold: true, color: b[1], align: "center" });
    s.addText(["0.0 – 0.4", "0.4 – 0.7", "0.7 – 1.0"][i], { x, y: 4.55, w: 3.75, h: 0.4, fontFace: BF, fontSize: 14, color: BODY, align: "center" });
  });
  s.addText("Server only stores the per-turn score at session end — for the confidence-trend chart.", { x: M, y: 5.5, w: 12, h: 0.5, fontFace: BF, fontSize: 14, italic: true, color: MUTE });
  footer(s);
  notes(s, "Runs entirely on the phone — counts fillers and hedges over the last 8 seconds, smoothed. The server only stores the per-turn score at session end for the trend chart. Zero added latency to the live loop.");
})();

// 36 — Leitner drills
(() => {
  const s = base();
  kicker(s, "Spaced-Repetition Drills");
  title(s, "Your mistakes → flashcards → 5 Leitner boxes.");
  const days = ["1 d", "3 d", "7 d", "14 d", "30 d"];
  days.forEach((d, i) => {
    const x = M + i * 2.42;
    s.addShape(p.ShapeType.roundRect, { x, y: 3.0, w: 2.2, h: 1.7, rectRadius: 0.1, fill: { color: i % 2 ? PANEL : TEALSOFT }, line: { color: TEAL, width: 1.2 } });
    s.addText("Box " + (i + 1), { x, y: 3.2, w: 2.2, h: 0.5, fontFace: HF, fontSize: 17, bold: true, color: INK, align: "center" });
    s.addText("review every", { x, y: 3.75, w: 2.2, h: 0.35, fontFace: BF, fontSize: 11, color: MUTE, align: "center" });
    s.addText(d, { x, y: 4.05, w: 2.2, h: 0.5, fontFace: HF, fontSize: 22, bold: true, color: TEAL, align: "center" });
  });
  s.addText("Correct → up a box (seen less often).   Wrong → back to Box 1.   XP on every transition (+15 / +5), idempotent.", { x: M, y: 5.1, w: 12, h: 0.6, fontFace: BF, fontSize: 15, color: BODY });
  footer(s);
  notes(s, "Real mistakes from your sessions become cards. Correct moves a card up a box and shows it less often; wrong resets to Box 1. XP on every transition (+15 to advance, +5 for showing up), idempotent so the same transition never double-pays. Spaced-repetition science applied to your weak spots.");
})();

// 37 — Dashboard (stat tiles)
(() => {
  const s = base();
  kicker(s, "Progress Dashboard");
  title(s, "“Am I actually improving?”");
  const tiles = [["Mistakes", "↓ 34%", GREEN], ["Sentiment", "↑ 35%", GREEN], ["Sessions", "+33%", TEAL], ["XP", "+23%", TEAL]];
  tiles.forEach((t, i) => {
    const x = M + i * 3.0;
    card(s, x, 2.6, 2.8, 2.0);
    s.addText(t[1], { x, y: 2.85, w: 2.8, h: 0.9, fontFace: HF, fontSize: 40, bold: true, color: t[2], align: "center" });
    s.addText(t[0], { x, y: 3.8, w: 2.8, h: 0.5, fontFace: HF, fontSize: 16, bold: true, color: INK, align: "center" });
    s.addText("vs previous window", { x, y: 4.2, w: 2.8, h: 0.35, fontFace: BF, fontSize: 11, color: MUTE, align: "center" });
  });
  s.addText("One endpoint, time-bucketed daily / weekly / monthly — pure read-side aggregation, no new tables.", { x: M, y: 5.1, w: 12, h: 0.5, fontFace: BF, fontSize: 15, italic: true, color: MUTE });
  footer(s);
  notes(s, "One endpoint, time-bucketed by range (daily, weekly, monthly). No new tables — pure read-side aggregation over existing data, with previous-window deltas. Mistakes trending down and sentiment up is the entire point of the app, made visible.");
})();

// 38 — Scenario card
(() => {
  const s = base();
  kicker(s, "Roleplay Scenario Generator");
  title(s, "Practice the conversation before you have it.");
  card(s, M, 2.5, 7.0, 3.3, CARD);
  s.addShape(p.ShapeType.rect, { x: M, y: 2.5, w: 7.0, h: 0.12, fill: { color: AMBER }, line: { type: "none" } });
  s.addText("Salary review with your manager", { x: M + 0.45, y: 2.8, w: 6.2, h: 0.6, fontFace: HF, fontSize: 21, bold: true, color: INK });
  s.addText([{ text: "Person:  ", options: { bold: true } }, { text: "Asma (Project Manager)" }], { x: M + 0.45, y: 3.5, w: 6.2, h: 0.4, fontFace: BF, fontSize: 15, color: BODY });
  s.addText([{ text: "Difficulty:  ", options: { bold: true } }, { text: "Hard" }], { x: M + 0.45, y: 3.9, w: 6.2, h: 0.4, fontFace: BF, fontSize: 15, color: BODY });
  s.addText([{ text: "Opening:  ", options: { bold: true, italic: true } }, { text: "“Thanks for making time — I'd like to talk about my role.”", options: { italic: true } }], { x: M + 0.45, y: 4.3, w: 6.3, h: 0.9, fontFace: BF, fontSize: 14.5, color: BODY, lineSpacingMultiple: 1.1 });
  s.addText([{ text: "Generated from your graph\n", options: { bold: true, color: TEAL } }, { text: "Pass it → auto-graded against its success criteria → +40 XP. The feed never repeats — used topics are excluded.", options: { color: BODY } }], { x: 8.0, y: 2.8, w: 4.6, h: 3.0, fontFace: BF, fontSize: 15.5, lineSpacingMultiple: 1.2 });
  footer(s);
  notes(s, "Pulls real people, tasks and events from your knowledge graph and generates practice scenarios. Finish one and it's auto-graded against its success criteria; a pass earns 40 XP. The feed never repeats because used topics are excluded.");
})();

// 39 — Gamification (icon rows)
(() => {
  const s = base();
  kicker(s, "Gamification");
  title(s, "Habit mechanics — for talking.");
  const items = [["Quests", "small daily goals"], ["Achievements", "milestone badges"], ["Rewards", "redeemable points"], ["Streaks", "keep the chain alive"], ["Leaderboard", "opt-in only — consistent with privacy-first"]];
  items.forEach((it, i) => {
    const y = 2.45 + i * 0.78;
    s.addShape(p.ShapeType.ellipse, { x: M, y, w: 0.58, h: 0.58, fill: { color: i === 4 ? "EFE3D2" : TEALSOFT }, line: { color: i === 4 ? AMBER : TEAL, width: 1.3 } });
    s.addText("★", { x: M, y, w: 0.58, h: 0.58, fontFace: HF, fontSize: 15, bold: true, color: i === 4 ? AMBER : TEAL, align: "center", valign: "middle" });
    s.addText([{ text: it[0] + "  —  ", options: { bold: true, color: INK } }, { text: it[1], options: { color: BODY } }], { x: M + 0.9, y, w: 11.3, h: 0.58, fontFace: BF, fontSize: 17, valign: "middle" });
  });
  footer(s);
  notes(s, "Habit mechanics borrowed from Duolingo, applied to talking: quests, achievements, rewards, streaks. The leaderboard is opt-in, consistent with our privacy-first stance.");
})();

// 40 — Graph explorer
(() => {
  const s = base();
  kicker(s, "Knowledge-Graph Explorer");
  title(s, "Your memory, made tangible.");
  s.addText("Browse the people, topics and entities you've mentioned — on a timeline.", { x: M, y: 2.25, w: 5.0, h: 1.6, fontFace: BF, fontSize: 18, color: BODY, lineSpacingMultiple: 1.25 });
  s.addText("The same nodes the AI uses for grounding — now yours to explore.", { x: M, y: 4.4, w: 5.0, h: 1.2, fontFace: BF, fontSize: 14.5, italic: true, color: MUTE, lineSpacingMultiple: 1.2 });
  // mini graph (right half)
  const cx = 9.5, cy = 4.3;
  const nodes = [[cx, cy, "You", TEAL], [cx - 2.0, cy - 1.2, "Asma", AMBER], [cx + 2.0, cy - 1.0, "Project X", TEALD], [cx - 1.5, cy + 1.5, "Friday", AMBER], [cx + 1.7, cy + 1.4, "Report", TEALD]];
  nodes.slice(1).forEach(nd => seg(s, cx, cy, nd[0], nd[1], MUTE, 2));
  nodes.forEach((nd, i) => {
    const d = i === 0 ? 1.05 : 0.9;
    s.addShape(p.ShapeType.ellipse, { x: nd[0] - d / 2, y: nd[1] - d / 2, w: d, h: d, fill: { color: i === 0 ? TEAL : CARD }, line: { color: nd[3], width: 1.8 } });
    s.addText(nd[2], { x: nd[0] - 1.0, y: nd[1] - 0.25, w: 2.0, h: 0.5, fontFace: BF, fontSize: 11.5, bold: true, color: i === 0 ? "FFFFFF" : INK, align: "center", valign: "middle" });
  });
  footer(s);
  notes(s, "The memory made visible — a navigable map of who and what you talk about, on a timeline. The same nodes and edges the AI uses for grounding, now browsable by you.");
})();

/* ---------------- SECTION 7: DATA / PRIVACY / QUALITY ---------------- */

// 41 — Data model
(() => {
  const s = base();
  kicker(s, "Data model");
  title(s, "Three pillars in Postgres.");
  const c = [
    { t: "Vector memory", d: "384-dim embeddings for semantic recall (RAG)." },
    { t: "Knowledge graph", d: "Nodes + edges — people, topics, relationships." },
    { t: "Session logs", d: "Verbatim transcript with speaker role." },
  ];
  c.forEach((it, i) => {
    const x = M + i * 4.07;
    card(s, x, 2.5, 3.75, 2.7, i === 1 ? TEALSOFT : CARD);
    s.addText(it.t, { x: x + 0.35, y: 2.8, w: 3.1, h: 0.9, fontFace: HF, fontSize: 18, bold: true, color: TEALD });
    s.addText(it.d, { x: x + 0.35, y: 3.7, w: 3.1, h: 1.3, fontFace: BF, fontSize: 15, color: BODY, lineSpacingMultiple: 1.2 });
  });
  s.addText("Supabase Postgres + pgvector · 7 versioned, reversible Alembic migrations.", { x: M, y: 5.5, w: 12, h: 0.5, fontFace: BF, fontSize: 14, italic: true, color: MUTE });
  footer(s);
  notes(s, "Three pillars — vector memory (384-dim embeddings for recall), the knowledge graph (nodes and edges), and session logs (verbatim transcript with speaker role). Postgres + pgvector, with versioned, reversible Alembic migrations.");
})();

// 42 — Privacy
(() => {
  const s = base();
  kicker(s, "Privacy-first — a feature, not an afterthought");
  title(s, "Your data stays yours.");
  s.addShape(p.ShapeType.roundRect, { x: M, y: 2.5, w: 3.4, h: 3.0, rectRadius: 0.15, fill: { color: TEALSOFT }, line: { color: TEAL, width: 1.5 } });
  s.addText("🛡", { x: M, y: 2.7, w: 3.4, h: 1.4, fontSize: 60, align: "center", valign: "middle" });
  s.addText("Row-Level\nSecurity", { x: M, y: 4.1, w: 3.4, h: 1.0, fontFace: HF, fontSize: 20, bold: true, color: TEAL, align: "center" });
  s.addText([{ text: "Enforced at the database", options: { bullet: true } }, { text: "A user can only ever touch their own graph & memories", options: { bullet: true } }, { text: "Sharing is opt-in, never default", options: { bullet: true } }, { text: "Personal growth tool — not org surveillance", options: { bullet: true } }], { x: 4.4, y: 2.7, w: 8.2, h: 3.0, fontFace: BF, fontSize: 18, color: BODY, lineSpacingMultiple: 1.35, paraSpaceAfter: 10 });
  footer(s);
  notes(s, "Postgres Row-Level Security means a user can only ever touch their own graph and memories — enforced at the database, not just the app. This turns the third research gap into a design principle: a personal growth tool, not org surveillance.");
})();

// 43 — Observability
(() => {
  const s = base();
  kicker(s, "Production-grade observability");
  title(s, "We can see the system — from day one.");
  const tools = [["Sentry", "errors"], ["Prometheus", "metrics"], ["OpenTelemetry", "traces"], ["Grafana", "dashboards"], ["structlog", "structured logs"]];
  tools.forEach((t, i) => {
    const x = M + (i % 3) * 4.07, y = 2.6 + Math.floor(i / 3) * 1.5;
    card(s, x, y, 3.75, 1.25);
    s.addText(t[0], { x: x + 0.35, y: y + 0.2, w: 3.1, h: 0.5, fontFace: HF, fontSize: 19, bold: true, color: TEAL });
    s.addText(t[1], { x: x + 0.35, y: y + 0.72, w: 3.1, h: 0.4, fontFace: BF, fontSize: 14, color: BODY });
  });
  footer(s);
  notes(s, "From day one we can see the system — errors, traces, latency, metrics, structured logs. This is what separates a deployable system from an FYP demo.");
})();

// 44 — Metrics
(() => {
  const s = base();
  kicker(s, "How we judge success");
  title(s, "Honest numbers.");
  const tiles = [["~300 ms", "advice latency", TEAL], ["≥85%", "transcription target", TEAL], ["low", "hallucination rate", TEAL], ["~80%", "context-accurate answers", AMBER]];
  tiles.forEach((t, i) => {
    const x = M + i * 3.0;
    card(s, x, 2.7, 2.8, 2.3, i === 3 ? "F7E9CF" : CARD, i === 3 ? AMBER : LINE);
    s.addText(t[0], { x, y: 2.95, w: 2.8, h: 0.9, fontFace: HF, fontSize: 33, bold: true, color: t[2], align: "center" });
    s.addText(t[1], { x: x + 0.15, y: 3.95, w: 2.5, h: 0.8, fontFace: BF, fontSize: 14.5, color: INK, align: "center", lineSpacingMultiple: 1.05 });
  });
  s.addText("Across 30+ trial sessions (~350 transcript lines, 45+ graph relations) — and we're driving accuracy up.", { x: M, y: 5.4, w: 12, h: 0.5, fontFace: BF, fontSize: 15, italic: true, color: MUTE });
  footer(s);
  notes(s, "How we judge success: transcription accuracy (WER, target ≥85% in moderate noise), end-to-end glass-to-glass latency, hallucination rate, and retrieval accuracy. On 30+ trial sessions we answered with correct context about 80% of the time — and we're improving it.");
})();

// 45 — Engineering quality
(() => {
  const s = base();
  kicker(s, "Engineering quality");
  title(s, "Discipline, not vibes.");
  const items = [["mypy --strict", "fully typed Python"], ["Ruff", "fast linting"], ["pytest", "unit · integration · e2e"], ["Locust", "load tested for concurrency"], ["Docker multi-stage", "runtime + worker targets"]];
  items.forEach((it, i) => {
    const y = 2.4 + i * 0.82;
    s.addShape(p.ShapeType.roundRect, { x: M, y, w: 0.62, h: 0.62, rectRadius: 0.08, fill: { color: "E9F3EC" }, line: { color: GREEN, width: 1.3 } });
    s.addText("✓", { x: M, y, w: 0.62, h: 0.62, fontFace: HF, fontSize: 16, bold: true, color: GREEN, align: "center", valign: "middle" });
    s.addText([{ text: it[0] + "  —  ", options: { bold: true, color: INK } }, { text: it[1], options: { color: BODY } }], { x: M + 0.9, y, w: 11, h: 0.62, fontFace: BF, fontSize: 17, valign: "middle" });
  });
  footer(s);
  notes(s, "Strict typing, linting, real test layers, load testing for concurrency, and containerized multi-stage builds. Not vibes — discipline.");
})();

/* ---------------- SECTION 8: CLOSE ---------------- */

// 46 — How we worked
(() => {
  const s = base();
  kicker(s, "How we worked");
  title(s, "Iterative R&D, clean ownership.");
  const phases = ["Research", "Analysis", "Design", "Development", "Testing"];
  phases.forEach((ph, i) => {
    const x = M + i * 2.42;
    s.addShape(p.ShapeType.roundRect, { x, y: 2.5, w: 2.25, h: 0.9, rectRadius: 0.1, fill: { color: i % 2 ? PANEL : TEALSOFT }, line: { color: TEAL, width: 1 } });
    s.addText(ph, { x, y: 2.5, w: 2.25, h: 0.9, fontFace: HF, fontSize: 14.5, bold: true, color: INK, align: "center", valign: "middle" });
    if (i < 4) s.addText("›", { x: x + 2.2, y: 2.5, w: 0.25, h: 0.9, fontFace: HF, fontSize: 18, bold: true, color: TEAL, align: "center", valign: "middle" });
  });
  card(s, M, 3.8, 5.7, 1.9, CARD);
  s.addText("Ahmad", { x: M + 0.4, y: 4.0, w: 5, h: 0.45, fontFace: HF, fontSize: 17, bold: true, color: TEAL });
  s.addText("Client · architecture · data model · UI · releases", { x: M + 0.4, y: 4.5, w: 5, h: 1.0, fontFace: BF, fontSize: 15, color: BODY, lineSpacingMultiple: 1.15 });
  card(s, 6.95, 3.8, 5.7, 1.9, CARD);
  s.addText("Attique", { x: 7.35, y: 4.0, w: 5, h: 0.45, fontFace: HF, fontSize: 17, bold: true, color: AMBER });
  s.addText("AI pipeline · memory · backend · workers · evaluation", { x: 7.35, y: 4.5, w: 5, h: 1.0, fontFace: BF, fontSize: 15, color: BODY, lineSpacingMultiple: 1.15 });
  footer(s);
  notes(s, "R&D suits an iterative model — build each hard module (diarization, RAG, knowledge graph) in isolation, test it, then integrate. Ahmad owns client, architecture and data; Attique owns the AI pipeline, memory and backend. Map to the Gantt if the panel asks.");
})();

// 47 — Current scope
(() => {
  const s = base();
  kicker(s, "Current scope");
  title(s, "The honest edges of what's built today.");
  const items = [["English-only", "the language we support right now"], ["Needs internet", "the AI brain lives in the cloud"], ["Thin client by design", "the phone is mic + screen only"]];
  items.forEach((it, i) => {
    const y = 2.6 + i * 1.15;
    s.addShape(p.ShapeType.roundRect, { x: M, y, w: 11.4, h: 0.95, rectRadius: 0.1, fill: { color: PANEL }, line: { type: "none" } });
    s.addText(it[0], { x: M + 0.4, y, w: 4.0, h: 0.95, fontFace: HF, fontSize: 19, bold: true, color: INK, valign: "middle" });
    s.addText(it[1], { x: M + 4.4, y, w: 6.8, h: 0.95, fontFace: BF, fontSize: 16, color: BODY, valign: "middle" });
  });
  s.addText("Design choices, not loose ends — a clear scope for what we demo today.", { x: M, y: 6.1, w: 12, h: 0.4, fontFace: BF, fontSize: 14, italic: true, color: MUTE });
  footer(s);
  notes(s, "State the deliberate boundaries of the current build — not a wishlist, just the edges of what we demo today: English-only, cloud-connected, thin client. These are design choices, and examiners respect a clear scope.");
})();

// 48 — Future plans
(() => {
  const s = base();
  bubble(s, 11.3, 0.4, 2.6, AMBER, 86);
  kicker(s, "Future plans  ·  planned, not yet built", M, 0.62, AMBER);
  title(s, "The runway.");
  const items = [["Multi-language", "Urdu first, then more"], ["Offline fallback", "local STT + small LLM (ONNX already in)"], ["Tone-aware coaching", "live sentiment → tone nudges"], ["Open-source release", "code + methods for the community"], ["Scale & deploy", "cloud GPU, app-store builds"], ["Fine-tuning", "domain-adapt ASR/LLM on sessions"]];
  items.forEach((it, i) => {
    const x = M + (i % 2) * 6.1, y = 2.25 + Math.floor(i / 2) * 1.35;
    s.addShape(p.ShapeType.roundRect, { x, y, w: 5.7, h: 1.15, rectRadius: 0.1, fill: { color: CARD }, line: { color: AMBER, width: 1, dashType: "dash" } });
    s.addText(String(i + 1), { x: x + 0.3, y, w: 0.7, h: 1.15, fontFace: HF, fontSize: 26, bold: true, color: AMBER, valign: "middle" });
    s.addText(it[0], { x: x + 1.1, y: y + 0.18, w: 4.4, h: 0.45, fontFace: HF, fontSize: 16.5, bold: true, color: INK });
    s.addText(it[1], { x: x + 1.1, y: y + 0.62, w: 4.5, h: 0.45, fontFace: BF, fontSize: 13, color: BODY });
  });
  footer(s);
  notes(s, "Be explicit this is the roadmap, separate from everything already demoed. Tie each item to something concrete — the ONNX local-embedding fallback already exists, so offline is a continuation not a fantasy; multi-language and tone coaching extend pipelines we already run. Keep it honest: these are next, not done.");
})();

// 49 — Close
(() => {
  const s = base();
  bubble(s, 10.7, -1.1, 4.0, TEAL, 86);
  bubble(s, 11.8, 1.9, 1.4, AMBER, 84);
  bubble(s, -0.8, 5.7, 2.8, TEAL, 90);
  s.addImage({ path: LOGO, x: M, y: 1.4, w: 1.4, h: 1.4 });
  s.addText("Get better at talking —\none conversation at a time.", { x: M, y: 3.0, w: 11, h: 1.8, fontFace: HF, fontSize: 44, bold: true, color: INK, lineSpacingMultiple: 1.02 });
  s.addText("github.com/qdevaan/Bubbles-AI   ·   qdevaan.github.io/Bubbles-AI", { x: M, y: 5.0, w: 11, h: 0.5, fontFace: BF, fontSize: 16, color: TEAL, bold: true });
  s.addText("Thank you  ·  Questions?", { x: M, y: 5.6, w: 11, h: 0.6, fontFace: HF, fontSize: 22, bold: true, color: BODY });
  footer(s);
  notes(s, "Restate the one-sentence pitch from the first slide. Invite questions. If demo wasn't shown earlier, this is the fallback spot to run it.");
})();

p.writeFile({ fileName: "Bubbles-FYP.pptx" }).then(f => console.log("WROTE", f)).catch(e => { console.error(e); process.exit(1); });
