# NeuroTrace design system

This is the design system for the app in `app/`. It is the reference for every screen: new work extends it and doesn't restyle it. The values live in `app/styles.css` (tokens at the top) and `app/copy.js` (every user-facing sentence). If this file and the CSS disagree, fix whichever is wrong, and don't let them drift.

**Who it's for:** adults aged 55–85, some with tremor or low vision, on an iPhone or an iPad (Apple Pencil in collection mode). Every rule below follows from that.

## Principles

1. **Legible before expressive.** Type is large, contrast is at least 4.5:1, touch targets are at least 44 px, and the main action is at least 56 px (64 px in collection mode).
2. **One accent, no verdict colours.** The accent marks what you can act on and what is selected. There is never red, amber or green to mean good or bad. A result's level is shown by words and position, never by colour (ClaimsRules, "no probability").
3. **Solid surfaces.** No glass, blur, gradients or glow. Depth comes from a surface colour against the page, a hairline, or one soft shadow with an offset.
4. **Motion answers a person.** Movement shows what changed. Nothing bounces, and all of it switches off together (see Motion).
5. **The product's own words.** Sentences come from `app/copy.js`, checked against `Markdowns/NeuroTrace_ClaimsRules.md`. Buttons name their action in sentence case.

## Colour

| Token | Light | Dark | Use |
|---|---|---|---|
| `--bg` | `#f5f5f7` | `#000000` | page |
| `--surface` | `#ffffff` | `#1c1c1e` | cards, tab bar, inputs |
| `--ink` | `#1d1d1f` | `#f5f5f7` | text |
| `--ink2` | `#6e6e73` | `#aeaeb2` | secondary text (never below 15 px) |
| `--line` | `rgba(0,0,0,.08)` | `rgba(255,255,255,.1)` | hairlines |
| `--fill` | `#e8e8ed` | `#3a3a3c` | tracks, segmented pad, disabled |
| `--guide` | `#d2d2d7` | `#48484a` | the spiral guide, halfway marks |
| `--accent` | accent (light) | accent (dark) | links, selected state, dots |
| `--accent-fill` | accent (light) | dark fill | primary button background (white text) |
| `--accent-soft` | 10% accent on white | 32% fill on black | selected chip, tab pill |

**Accents** are chosen in Settings and set with `<html data-accent>`. Each has three values, and every one passes 4.5:1 in both modes:

| Accent | Light | Dark text | Dark fill |
|---|---|---|---|
| Blue (default) | `#0066cc` | `#2997ff` | `#0071e3` |
| Indigo | `#4f46e5` | `#8e8cff` | `#5b54e8` |
| Violet | `#7c3aed` | `#bf8bff` | `#8b4ff0` |
| Teal | `#00747a` | `#40c8d4` | `#00808a` |
| Amber | `#a65200` | `#ffa94d` | `#b35900` |
| Rose | `#c2185b` | `#ff7eb0` | `#c7206a` |
| Graphite | `#4a4a4f` | `#b8b8be` | `#5a5a60` |

- **Adding an accent:** check contrast first. Never add a green or a pure red.
- **Theme:** Automatic, Light or Dark, set with `<html data-theme>`. The dark token block appears twice in `styles.css`, once under `prefers-color-scheme` and once under `[data-theme="dark"]`. The two copies must stay identical.

## Type

Two families, self-hosted in `app/fonts/` (SIL OFL), preloaded, with `font-display: swap`:

- **Newsreader** (`--font-display`, variable weight and optical size) is for titles only: `h1`, `h2`, `h3`, the brand name and the measuring title. Use weight 500 for `h1` and 600 for `h2`/`h3`, with letter-spacing −0.01em.
- **Atkinson Hyperlegible Next** (`--font-body`), drawn by the Braille Institute for low-vision readers, is for everything people read or tap. Use weight 400 for text and 600 for labels, buttons and selected states. Letter-spacing is 0; never tighten it.

Sizes are written as `calc(N * var(--px))` so they follow iOS Dynamic Type. On iOS the base comes from `-apple-system-body`; `--px` is 1/17 rem.

| Role | Size | Notes |
|---|---|---|
| Home headline (signed out) | 40 | Newsreader 500 |
| Collection titles | 44 / 40 | iPad |
| Large title (`h1`) | 34 | Newsreader 500 |
| Result verdict | 32 | Newsreader 500, text from `copy.TIERS` |
| Section / card title | 21 | Newsreader 600 |
| Group title (`h3`) | 19 | Newsreader 600 |
| Body | 17 (19 at ≥700 px) | Atkinson 400, line-height 1.5 |
| Secondary (`.sub`) | 15 | the floor; nothing smaller |

Numbers that change use `font-variant-numeric: tabular-nums` (`.num`).

## Space and shape

- **Spacing:** use the existing steps: 4, 6, 8, 10, 12, 14, 16, 18, 20, 24, 28, 36 px. Keep more space above a heading than below it.
- **Page:** each screen is a column 560 px wide (collection mode is full width on iPad). Side padding is 24 px, or the safe-area inset where larger. The primary action sits at the bottom.
- **Radii:**
  - cards 16
  - segmented pad 12, and 9 for its thumb
  - number inputs 12
  - pad sheet 24 (28 on iPad)
  - buttons, chips and the tab pill: full pill
- **Shadows:** only three, each with an offset:
  - the welcome hero sheet
  - the segmented thumb
  - the toast

## Components

- **Buttons (`.btn`).**
  - Primary: `--accent-fill` background, white text.
  - Secondary: transparent, `--accent` text, 1.5 px inset accent ring.
  - Disabled: `--fill` background, `--ink2` text, with a sentence nearby saying what's missing.
  - Pressed: scale 0.97.
- **Chips (`.chip`)** are radios styled as pills in a 2-column grid. The selected chip gets `--accent-soft`, a 2 px accent ring, weight 600 and a tick. An odd last chip spans the full row.
- **Segmented control (`.segmented` > `.segment`)** puts one choice from 2–3 in a single pad, with a sliding white thumb (`#636366` in dark). It needs no script, because the thumb position comes from `:has()`. Used for Theme, Motion and the results spiral picker.
- **Accent row (`.accents` > `.accent-option`)** is seven 32 px dots in one row. The selected dot is ringed and ticked, and its name appears in the legend (`.legend-split`), so the choice never depends on colour alone.
- **Cards (`.card`)** are `--surface` with a 16 px radius, a hairline border and 20 px padding. They are never nested.
- **Tab bar (`.tabbar`)** is docked to the bottom edge, solid `--surface`, with one top hairline. It holds Dashboard, Testing, Training, Progress and Settings, each with an icon and a 15 px label. The current tab uses accent colour plus the `.tab-lens` pill behind its icon, which slides between tabs. It appears only on those five screens, once logged in. Logged out, the only screen is Home, which has no tab bar.
- **Measure row (`.measure`)** has three parts:
  - the name
  - the plain-language percentile sentence (from `copy.measureSentence`)
  - an `aria-hidden` track with a 20 px dot and a halfway mark.
  The sentence is the content; the dot is a second reading of it.
- **Level strip (`.levels`)** has three equal bars. Only the current one is filled, and it is labelled. It is not a meter.
- **Status card (`.status`)** is an inline message with an info icon, `role="status"`, with its first sentence in bold.
- **Mascot (`[data-mascot]`)** is a spiral shell around a face. Idle, it bobs and blinks; while measuring, it traces its own shell. It never reacts to a result.

## iPad

Same system, wider layout. There's no separate iPad app; it's all media queries in `styles.css`.

- **700 px and up:** body text is 19 px. The drawing column widens to 760 px, so the pad reaches about 700 px on a portrait iPad. The tabs group in the centre, up to 160 px each.
- **900 px and up** (landscape, 12.9-inch portrait): Dashboard, Settings and results widen to 1040 px. Testing, Training and Progress stop at 760 px.
  - **Dashboard:** check-in and medication cards on the left, history on the right.
  - **Results:** the reading (verdict, reference, meaning, next steps, drawing) is a pinned left column; "What stood out" and "Every measure" sit on the right. On a phone, both wrappers use `display: contents` and CSS `order`, so the phone sequence is unchanged.
  - **Settings:** cards flow into two columns.
- **Kept to one narrow column on every size:** Home (signed out), consent, about-you and the participant form. Collection mode is already laid out for the iPad.

## Motion

- **One switch:** `<html data-motion="reduce">`, set before first paint (`index.html`) from Settings > Motion or the device setting. Under it, every CSS animation and transition jumps to its end state. JavaScript helpers check `reduced()` from `app/motion.js`.
- **Easing:** `--ease` (`cubic-bezier(0.22, 1, 0.36, 1)`), an exponential ease-out. No springs, overshoot or bounce.
- **Durations:** 160–360 ms for controls, up to 640 ms for the result reveal.
- **What moves:**
  - page transitions (View Transitions: tabs slide, other screens rise in)
  - the tab pill
  - the segmented thumb
  - the results reveal, with the dot travelling out from halfway while its number counts up
  - the level bar filling in
  - the measuring overlay
  - pen-tip glow and the fade between trials
  - the too-short nudge
  - the toast
- **Not used:** glass or refraction, ripples, hover sheens, and staggered entrances on lists.

## Browser surfaces

- Text selection is tinted with the accent. The caret and `accent-color` follow the accent.
- Scrollbars are hidden everywhere; scrolling still works.
- The focus ring is 3 px `--accent`, offset 3 px, on every control.
- The viewport allows pinch-zoom.

## Don't

- Don't use a second typeface, a webfont from a CDN at runtime, or negative tracking on Atkinson.
- Don't add colour that carries meaning about health, show a probability, or show a combined score.
- Don't add glass, blur, gradients, glow, zero-offset halos, or coloured side-borders on cards.
- Don't add bouncy easing or animation that nobody triggered and that can't be switched off.
- Don't use icon-only controls, text under 15 px, or targets under 44 px.
- Don't reuse a class name for a different component. Two collisions (`.swatch` and `.legend-row`) have already broken layouts here. Search `styles.css` before naming.
