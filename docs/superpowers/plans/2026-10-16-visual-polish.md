# Wearly visual polish implementation plan

Execute inline using dev-flow/executing-plans. User requests broad visual refinement and smoother interaction, authorizing implementation; preserve accepted Wearly identity and full-width layout.

## Design brief

Retain white #FFFFFF, canvas #F7F8F7, plum #65394D, ink #252329, muted #67636A, soft #ECE5E9. Manrope display and Be Vietnam Pro UI remain local. Improve hierarchy and rhythm, not add decorative gradients or generic repeated card entrances. Hero owns visual emphasis; commerce remains calm and legible. Keep all mock interactions and disclosures.

Desktop: full-width header / balanced hero text + portrait / curated product grid / stylist editorial / room steps / collection story / structured footer. Mobile: compact header / copy + garment / two-column products / stacked forms. Reading and dialog widths stay bounded. Catalog expands to four columns when content width permits.

## Tasks

- [x] Shared system: motion tokens (160/220ms, easeOutCubic), accessible hover/focus image treatment, gentle route content fade, theme states for controls/panels/data tables; reduced motion means no scale/opacity tween.
- [x] Reference pages: responsive hero typography/photo aspect, catalog density/filter panel, product image framing and selection polish. Keep Home/Catalog/Detail coherent before other pages.
- [x] Whole-app finish: active navigation, refined footer, calmer disclosures/states, align forms and panels across account/checkout/AI/admin with shared theme; no real API or new dependencies.
- [x] Verify motion can be interrupted, reduced-motion content is immediately visible, keyboard/selection work, mobile and150% text remain usable. Existing commerce/privacy tests must stay green.
- [x] Analyze/build, desktop/mobile browser flows and screenshots375/768/1440/1920, independently review changes, revise visuals and document limits.

## Rulings / constraints

- No Git repository, edit existing workspace without commits/worktrees. Existing assets7 photos, still repeated by fixture; no fabricated views/AI photos. Final report must distinguish visual improvements from remaining photography/real-service work.
- Keep scene animations finite; no shimmer or continuous ambient motion. Hover scale confined to photo clipping, no layout shifts. Button labels/accessible names stable for keyboard/browser checks.
- Avoid making all pages a field of rounded cards. Panels identify forms/summary/assistant context only; product cards remain flat.
