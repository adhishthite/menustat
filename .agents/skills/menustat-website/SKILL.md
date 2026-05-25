---
name: menustat-website
description: Build, refine, and verify the MenuStat website under website/, including product-grounded copy, responsive checks, theme persistence, external links, and Apple Silicon download messaging.
---

# MenuStat Website

Use this skill from the MenuStat repository root when working on the website in
`website/`, website copy, screenshots, theme behavior, analytics links, or
Apple Silicon support messaging. For app release packaging, use
`menustat-release` instead.

## Source Anchors

- Main pages and styling: `website/app/layout.tsx`, `website/app/page.tsx`,
  `website/app/globals.css`
- Interactive pieces: `website/app/ThemeToggle.tsx`,
  `website/app/LiveTelemetry.tsx`, `website/public/theme-init.js`
- Product assets: `docs/screenshots/menustat-panel.png`,
  `Resources/AppIcon.iconset`
- Release/download copy touchpoints: `README.md`, `docs/releasing.md`,
  `script/package_release.sh`

## Workflow

1. Inspect current state before editing:
   ```bash
   git status --short
   rg -n "Apple Silicon|Intel|MenuStat|target=|rel=|analytics|theme" website README.md docs script
   ```

2. Keep the design anchored in the actual product:
   - Prefer MenuStat telemetry, HUD, menu-bar, and panel language over generic
     SaaS landing-page patterns.
   - Use real app screenshots or repo assets when possible.
   - Avoid fake Finder/menu-bar chrome around the product preview.
   - Make the first viewport identify MenuStat clearly and hint at the next
     section on both mobile and desktop.

3. Preserve hardware support clarity:
   - If the app is Apple Silicon-only, say that directly near download and
     install surfaces.
   - Do not rely only on runtime alerts for Intel users; keep website/README
     copy explicit.
   - If exploring universal startup support, verify `x86_64` behavior through
     the release path before presenting it as supported.

4. Build and verify:
   ```bash
   cd website
   pnpm build
   pnpm dev
   ```

5. Inspect the served page in a browser:
   - Desktop width and about 390 px mobile width.
   - Header and nav do not overflow.
   - Theme toggle persists after reload.
   - External links that open new tabs use `target="_blank"` with
     `rel="noopener noreferrer"`.
   - Dynamic year and analytics/link behavior match source intent.

6. Before finishing, report the exact build/browser checks run and any known
   gaps. If a screenshot is useful, store it under a repo-local scratch or docs
   path and reference the file.

## Failure Modes

- If the page feels like a generic template, re-ground the copy and visuals in
  live telemetry, app screenshots, and MenuStat's actual UI.
- If mobile header text wraps or clips, reduce density and verify at 390 px
  before calling it fixed.
- If link behavior is in doubt, inspect the served DOM rather than only reading
  source.
