# Knight Rider Bar (Zsh/ZLE)

This document describes the Knight Rider style bar implemented in `KnightRider.zsh`, and how it maps to the upstream `spinner.ts` algorithm (from opencode/opentui).

## Goals

- Render a Knight Rider scanner in the Zsh line editor (ZLE) with colors.
- Avoid mixing `/dev/tty` writes with `zle redisplay` to prevent desync.
- Keep the editor buffer empty after the animation.
- Match the upstream look as closely as possible, including:
  - trail palette (head + bloom + exponential tail)
  - state machine (forward + holdEnd + backward + holdStart)
  - inactive dot fading (fade-in on movement, fade-out on holds)

## Rendering Strategy (ZLE-safe)

- The bar is drawn by setting `BUFFER` to the bar text and calling `zle -R`.
- Colors are applied via `region_highlight` only (no ANSI escapes in `BUFFER`).
- The bar is rendered as:

  - `BUFFER="[<viewLen chars>]"`  (so total width is `viewLen + 2`)
  - `region_highlight` contains:
    - a bracket style for `[` and `]`
    - a baseline style for the interior (inactive dots)
    - per-cell styles for active trail cells (overriding the baseline)

Important detail: `region_highlight` style attributes must be comma-separated (e.g. `fg=#RRGGBB,bg=#RRGGBB`). Space-separated `fg=... bg=...` will not apply correctly.

## Model: Visible Window + Padding

We keep a “world” model that is larger than the visible window:

- `viewLen`: number of visible cells inside the bar
- `padL`: left invisible padding
- `padR`: right invisible padding

The world coordinate system is 1-based.

- Visible range (world coords):
  - `viewStart = padL + 1`
  - `viewEnd = padL + viewLen`

- The scanner head position is a single world coordinate:
  - `activePos` in `[viewStart .. viewEnd]` during movement
  - stays at edges during holds

## Mapping to `spinner.ts`

Upstream uses a 4-phase cycle (bidirectional) computed by `getScannerState(frameIndex, width, ...)`.

### Defaults (from `spinner.ts`)

These are the upstream defaults and where they live:

- `width` (visible length): `8`
  - `createFrames`: `const width = options.width ?? 8`
- `holdStart`: `30`
  - `createFrames`: `const holdStart = options.holdStart ?? 30`
- `holdEnd`: `9`
  - `createFrames`: `const holdEnd = options.holdEnd ?? 9`
- `trailSteps`: `6`
  - `deriveTrailColors(brightColor, steps = 6)`
- `inactiveFactor`: `0.2`
  - `deriveInactiveColor(brightColor, factor = 0.2)`
- `minAlpha`: `0.0` (default param in `createKnightRiderTrail`)
- `enableFading`: `true` (default param in `createKnightRiderTrail`)

### Translation to `KnightRider.zsh`

- `padL = holdStart` (default 30)
- `padR = holdEnd` (default 9)
- `viewLen = width` (default 8)
- `trainLen = trailLength = trailSteps` (default 6)

Total frames per full cycle:

- Upstream: `totalFrames = width + holdEnd + (width - 1) + holdStart`
- Zsh: `totalFrames = viewLen + padR + (viewLen - 1) + padL`

With defaults: `8 + 9 + 7 + 30 = 54`.

## State Machine (Port of `getScannerState`)

For each `frameIndex` in `[0 .. totalFrames-1]`:

1) Moving forward (length = `viewLen`)

- `activePos = padL + 1 + frameIndex`
- `dir = +1`
- `isHolding = 0`
- `movementProgress = frameIndex`
- `movementTotal = viewLen`

2) Hold at end (length = `padR`)

- `activePos = padL + viewLen`
- `dir = +1`
- `isHolding = 1`
- `holdProgress = frameIndex - viewLen`
- `holdTotal = padR`

3) Moving backward (length = `viewLen - 1`)

- `backwardIndex = frameIndex - viewLen - padR`
- `activePos = padL + viewLen - 1 - backwardIndex`
- `dir = -1`
- `isHolding = 0`
- `movementProgress = backwardIndex`
- `movementTotal = viewLen - 1`

4) Hold at start (length = `padL`)

- `activePos = padL + 1`
- `dir = -1`
- `isHolding = 1`
- `holdProgress = frameIndex - viewLen - padR - (viewLen - 1)`
- `holdTotal = padL`

## Trail Coloring (Core of `calculateColorIndex`)

Upstream computes a “directional distance” from the head; only cells behind the direction are active.

In `KnightRider.zsh`, for each world position `p` in `[viewStart..viewEnd]`:

- `dist` (directional distance, behind the head):
  - if moving forward (`dir > 0`): `dist = activePos - p`
  - if moving backward (`dir < 0`): `dist = p - activePos`

Upstream hold behavior shifts the trail index:

- if holding: `idx = dist + holdProgress`
- else: `idx = dist`

A cell is active iff:

- `idx >= 0 && idx < trailLen`

Color selection:

- head is `idx == 0`
- trailing cells use `idx == 1..trailLen-1`

## Palette Derivation (Port of `deriveTrailColors`)

Upstream builds trail colors from a single bright color:

- `i = 0`: `alpha=1.0`, `brightnessFactor=1.0`
- `i = 1`: `alpha=0.9`, `brightnessFactor=1.15` (bloom)
- `i >= 2`: `alpha = 0.65^(i-1)`, `brightnessFactor=1.0`

In terminals we can’t apply true alpha; in `KnightRider.zsh` we simulate alpha by blending with a configured background.

## Background Blending (Why a Background Hex Is Needed)

Upstream uses RGBA, so the perceived color depends on the background:

- `final = alpha * color + (1 - alpha) * background`

`KnightRider.zsh` implements this by requiring a background hex:

- `_overlay_bg_hex` (e.g. `'#303446'`)

Both the trail palette and the inactive dots are pre-blended against `_overlay_bg_hex` so that:

- fading is visible and matches the RGBA look
- the bar background can be forced with `bg=${_overlay_bg_hex}` via `region_highlight`

## Inactive Dots: Fade Factor (Core of “Global Fading”)

Upstream fades inactive dots globally based on the current phase:

- During movement: fade-in from `minAlpha` to `1.0`
  - `progress = movementProgress / max(1, movementTotal - 1)`
  - `fadeFactor = minAlpha + progress * (1 - minAlpha)`

- During holds: fade-out from `1.0` to `minAlpha`
  - `progress = min(holdProgress / holdTotal, 1)`
  - `fadeFactor = max(minAlpha, 1 - progress * (1 - minAlpha))`

In `KnightRider.zsh`, this affects the inactive dots color by scaling the configured inactive factor:

- `alpha = inactiveFactor * fadeFactor`
- then blended with `_overlay_bg_hex`

## Timing

`spinner.ts` does not define frame duration; it only defines the sequence of frames and colors.
The consumer chooses how fast to advance `frameIndex`.

`KnightRider.zsh` uses real-time pacing so the perceived speed is consistent across tmux vs non-tmux:

- `_overlay_frame_ms`: target frame time in milliseconds (e.g. 33ms ~ 30fps)
- `_overlay_poll_cs`: polling interval passed to `zselect -t` (centiseconds; `1` = 10ms)

The loop polls at `_overlay_poll_cs` and advances to the next frame only when the real-time deadline expires (using `EPOCHREALTIME`).

## Where This Lives

- Implementation: `KnightRider.zsh`
- Reference algorithm: `spinner.ts`
