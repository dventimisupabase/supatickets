# Explainer Page Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a single-file animated scrollytelling explainer page for the Burst-to-Queue Ledger architecture.

**Architecture:** Single `index.html` with inline CSS, SVG, and vanilla JS. Five full-viewport sections scroll vertically. IntersectionObserver triggers animations as sections enter the viewport. SVG diagrams and bar charts are hand-crafted inline. Zero external dependencies.

**Tech Stack:** HTML5, CSS3 (custom properties, transitions, transforms), inline SVG, vanilla JavaScript (IntersectionObserver, requestAnimationFrame)

---

### Task 1: Scaffold and CSS Foundation

**Files:**
- Create: `index.html`

**Step 1: Create the HTML shell with CSS custom properties and base layout**

Create `index.html` with:
- `<!DOCTYPE html>`, viewport meta, title "Burst-to-Queue Ledger"
- `<style>` block with CSS custom properties:
  - `--bg-dark: #0a0e27` (deep navy)
  - `--bg-section: #0f1538` (slightly lighter for alternating sections)
  - `--blue: #3b82f6` (electric blue — DB1/shielded)
  - `--blue-glow: #60a5fa` (lighter blue for glows)
  - `--amber: #f59e0b` (warm amber — DB2/unshielded)
  - `--amber-glow: #fbbf24`
  - `--text: #f1f5f9`
  - `--text-muted: #94a3b8`
  - `--green: #22c55e` (for success/0% errors)
  - `--red: #ef4444` (for errors)
- CSS reset (box-sizing, margin 0, font-family system stack)
- `.section` class: `min-height: 100vh`, flex column center, padding
- Five empty `<section>` divs with IDs: `hero`, `problem`, `architecture`, `results`, `footer`
- Responsive font sizing using `clamp()`

**Step 2: Verify in browser**

Run: `open index.html` (or serve with `python3 -m http.server`)
Expected: Five dark full-viewport panels, scrollable, no content yet.

**Step 3: Commit**

```bash
git add index.html
git commit -m "feat: scaffold explainer page with CSS foundation"
```

---

### Task 2: Hero Section (What)

**Files:**
- Modify: `index.html`

**Step 1: Add hero content**

In the `#hero` section, add:
- `<h1>` with text "Burst-to-Queue Ledger" — use `font-size: clamp(2.5rem, 6vw, 5rem)`, `font-weight: 800`, gradient text effect using `background: linear-gradient(135deg, var(--blue), var(--blue-glow), var(--amber))` with `-webkit-background-clip: text`
- `<p>` subtitle: "A two-database architecture that absorbs traffic spikes your production database can't." — `font-size: clamp(1rem, 2vw, 1.5rem)`, color `var(--text-muted)`, max-width 700px
- Below: an inline `<svg>` (width 800, height 200, viewBox) containing the hero animation (built in next step)
- At bottom: a scroll indicator — small `<div>` with downward chevron, CSS animation `translateY` bounce

**Step 2: Build hero SVG animation**

The SVG contains:
- Left cluster: 20-30 small circles (requests) that spawn at random Y positions on the left edge and fly rightward
- Center: a rounded-rect "shield" node labeled "DB1" with a blue glow filter (`<filter>` with `feGaussianBlur` + `feComposite`)
- Right: a rounded-rect "ledger" node labeled "DB2" with a subtle amber glow
- Between shield and ledger: a dashed path with a few orderly dots moving along it

JavaScript (in a `<script>` at bottom of file):
- `requestAnimationFrame` loop that:
  - Spawns particles on the left at random intervals
  - Moves them rightward; when they reach the shield, they "absorb" (opacity fade) and occasionally one emerges on the right side moving slowly toward DB2
  - Particles have random speeds and slight Y jitter for organic feel
- Use `class HeroAnimation` to encapsulate state

**Step 3: Verify in browser**

Expected: Bold gradient title, subtitle, animated particles flowing left-to-right through shield to ledger, bouncing scroll indicator.

**Step 4: Commit**

```bash
git add index.html
git commit -m "feat: add hero section with animated particle flow SVG"
```

---

### Task 3: Problem Section (Why)

**Files:**
- Modify: `index.html`

**Step 1: Add problem section content**

In the `#problem` section, add:
- `<h2>` headline: "Production databases weren't built for flash mobs." — large, bold, white
- `<p>` copy (3-4 sentences): "When 10,000 fans hit 'Buy' at the same moment, your transactional database faces a wall of concurrent writes. Rows lock. Connections saturate. Users get errors — or worse, inconsistent state."
- Below copy: an inline `<svg>` (width 600, height 300) for the overwhelmed-DB animation
- Below SVG: a stat callout `<div>` with large text: "At 500 concurrent users, a direct database takes 3.4s p95 and drops 1 in 10 requests." — styled with amber left border, padded, `font-size: clamp(1rem, 1.8vw, 1.3rem)`

**Step 2: Build problem SVG animation**

The SVG shows:
- A single database icon (amber rounded rect, labeled "DB") centered
- Request dots flood in from the left
- An animated counter above the DB shows error rate climbing: "0.0% → ... → 10.7% errors" using JS text interpolation
- Some dots reaching the DB turn red and bounce away (rejected requests)
- Others slow down and pile up (latency)

JavaScript:
- `class ProblemAnimation` — triggered when `#problem` enters viewport via IntersectionObserver
- Counter animates from 0 to 10.7 over 2 seconds using `requestAnimationFrame`
- Particle behavior: spawn from left, some reach DB and succeed (turn green, pass through), some turn red and deflect

**Step 3: Add IntersectionObserver scaffold**

At the bottom of `<script>`, create a generic `ScrollAnimator` class:
- Observes all `.section` elements
- Adds `.visible` class when section is >20% in viewport
- Calls registered animation start/stop callbacks per section ID
- `threshold: [0, 0.2, 0.5]`

Wire up `ProblemAnimation` to start when `#problem` becomes visible.

**Step 4: Verify in browser**

Scroll to problem section. Expected: headline fades in, DB gets overwhelmed by dots, counter climbs to 10.7%, stat callout visible.

**Step 5: Commit**

```bash
git add index.html
git commit -m "feat: add problem section with overwhelmed-DB animation"
```

---

### Task 4: Architecture Section (How)

**Files:**
- Modify: `index.html`

**Step 1: Add architecture section layout**

In the `#architecture` section, add:
- `<h2>` headline: "How it works" — large, bold
- A large inline `<svg>` (width 900, height 400, responsive via viewBox) — this is the main architecture diagram
- Below the SVG: four step description `<div>`s in a row/grid, each with:
  - A step number badge (1-4) in a circle
  - A bold label (Claim / Sweep / Bridge / Ledger)
  - One sentence of description
  - These have class `.arch-step` and data attributes for step number

**Step 2: Build the architecture SVG**

The SVG contains four main nodes arranged left-to-right:
1. **"User"** — person icon or simple circle, far left
2. **"DB1"** — blue rounded rect with "DB1 (Intake)" label, left-center
3. **"Queue"** — a pipe/cylinder shape labeled "pgmq", center
4. **"Bridge"** — a hexagon or function icon labeled "Edge Fn", right-center
5. **"DB2"** — amber rounded rect with "DB2 (Ledger)" label, far right

Connecting arrows between each node, initially at `opacity: 0` with class `.arch-path`.

Each node group has a class `.arch-node` and a `data-step` attribute.

**Step 3: Build architecture scroll animation**

JavaScript `class ArchitectureAnimation`:
- Uses IntersectionObserver on the `#architecture` section
- As the section scrolls into view, steps reveal sequentially with 600ms delays:
  - Step 1: User → DB1 arrow draws (SVG stroke-dashoffset animation), DB1 node glows blue, step 1 description highlights
  - Step 2: DB1 → Queue arrow draws, queue node appears, step 2 highlights, step 1 dims to 60% opacity
  - Step 3: Queue → Bridge → DB2 arrows draw, bridge node appears, step 3 highlights, previous dims
  - Step 4: DB2 glows amber, step 4 highlights, all nodes remain visible at reduced opacity, full diagram complete
- CSS class `.arch-step.active` highlights the current step description (blue left border, white text)
- CSS class `.arch-step.dimmed` dims previous steps (muted text)

**Step 4: Verify in browser**

Scroll to architecture section. Expected: diagram builds step by step, descriptions highlight in sequence, full diagram visible at end.

**Step 5: Commit**

```bash
git add index.html
git commit -m "feat: add architecture section with step-by-step SVG diagram"
```

---

### Task 5: Results Section (Proof)

**Files:**
- Modify: `index.html`

**Step 1: Add results section layout**

In the `#results` section, add:
- `<h2>` headline: "Don't take our word for it." — bold, white
- `<p>` subtitle: "Real load test results from Grafana Cloud k6, co-located in AWS us-east-1." — muted

Three panel `<div>`s with class `.result-panel`, each containing:
- A panel title
- An inline `<svg>` for the chart
- Caption text below

**Step 2: Build Panel 1 — Shielded vs Unshielded bar chart**

Title: "500 Concurrent Users: Shielded vs Unshielded"

SVG horizontal bar chart with three metric pairs:
- Throughput: blue bar "691 rps" vs amber bar "440 rps"
- p95 Latency: blue bar "991ms" vs amber bar "3,408ms"
- Error Rate: blue bar "0%" (with green accent) vs amber bar "10.7%" (with red accent)

Each bar has a `<rect>` that animates `width` from 0 to proportional value when visible. Labels sit at the end of each bar.

JavaScript: `class BarChartAnimation` — generic, takes data array, animates bars on IntersectionObserver trigger. Duration 1.5s with easeOutCubic.

**Step 3: Build Panel 2 — Optimization Journey**

Title: "The Optimization Path"

Three horizontal grouped entries, each showing:
- Label: "Coupled", "Decoupled", "Sequence-based"
- Two metrics: throughput bar + median latency value
- Data:
  - Coupled: 1,113 rps / 105ms median
  - Decoupled: 1,836 rps / 10ms median
  - Sequence: 950 rps (cloud ceiling) / ~0% CPU

Arrow indicators between entries showing the improvement (e.g., "-90% latency", "+65% throughput").

**Step 4: Build Panel 3 — The Punchline**

Title: "Algorithm beats hardware"

Large side-by-side comparison:
- Left card (blue border): "Micro" / "$25/mo" / "Sequence-based" / "907 rps"
- Right card (amber border): "XL" / "$150/mo" / "SKIP LOCKED" / "839 rps"
- A ">" symbol between them, animated to pulse
- Below: "Smart algorithms on cheap hardware outperform brute-force compute scaling."

**Step 5: Verify in browser**

Scroll to results. Expected: bars animate in, optimization journey shows progression, punchline comparison is clear and impactful.

**Step 6: Commit**

```bash
git add index.html
git commit -m "feat: add results section with animated bar charts and comparisons"
```

---

### Task 6: Footer and Polish

**Files:**
- Modify: `index.html`

**Step 1: Add footer section**

In the `#footer` section, add:
- "Explore" heading
- Three link cards in a row:
  - GitHub repo (icon + "Source Code" + link to `https://github.com/dventimiha/pg-ticketing-system`)
  - Demo app (icon + "Live Demo" + link placeholder)
  - Load test results (icon + "Benchmarks" + link to `load-test-results.md`)
- Tech stack badges row: Supabase, PostgreSQL, pgmq, pg_cron, Deno, Next.js, k6 — styled as small rounded pills with text

**Step 2: Add entrance transitions for all sections**

CSS:
- `.section` starts with `opacity: 0; transform: translateY(40px)`
- `.section.visible` transitions to `opacity: 1; transform: translateY(0)` over 0.8s ease-out
- Individual elements within sections can have staggered `transition-delay`

**Step 3: Add responsive styles**

Media queries:
- Below 768px: reduce SVG viewBox widths, stack result panels vertically, reduce font sizes
- Below 480px: further font reduction, hide non-essential SVG details, full-width panels

**Step 4: Verify in browser at multiple widths**

Check: desktop (1440px), tablet (768px), mobile (375px). All sections readable, animations work, no horizontal overflow.

**Step 5: Final commit**

```bash
git add index.html
git commit -m "feat: add footer, entrance transitions, and responsive styles"
```

---

### Task 7: Final Review and Push

**Step 1: Full scroll-through verification**

Open `index.html` in browser. Scroll top to bottom:
- Hero: particles animate, title is bold and gradient
- Problem: counter climbs, dots overwhelm DB
- Architecture: diagram builds step-by-step
- Results: bars animate, punchline is clear
- Footer: links work, badges display

**Step 2: Commit any final tweaks and push**

```bash
git push origin main
```
