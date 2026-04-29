# Visual Design

Status: reference

## Target devices

Luciana is primarily an app, so visual design targets small devices first
(mobile portrait, ~360–430px wide). All layouts, component sizing, tap
targets, and typography are decided for that context. Desktop is a secondary
target: the app should still look acceptable on wider viewports — typically
by constraining content width and centring it — but no desktop-specific
layout work is required.

## Current approach

[daisyUI](plans/daisyui.md) is sufficient for the visual design of Luciana at
this stage. It provides a coherent set of component classes — navbar, cards,
form controls, buttons, alerts — that cover every screen the app currently
renders (login, signup, placeholder pages). Combined with Tailwind utility
classes for layout, no additional CSS framework or custom design system is
needed.

The two built-in themes (`light` default + `dark` via `prefers-color-scheme`)
give the app a polished, consistent look with zero design decisions required
upfront.

## Icons

Every button has an icon preceding its text label. An icon-less button is a
deliberate exception, not the default.

### Library: Heroicons

[Heroicons](https://heroicons.com/) (MIT, by the Tailwind Labs team).
Chosen for:

- Pairs with Tailwind/daisyUI by design — stroke weight, density, and
  metrics match the existing component sizing without tuning.
- MIT licensed, no attribution requirement.
- **Inline SVG, no web font** — no extra HTTP request, no
  flash-of-unstyled-text, works offline on first paint (matters for a
  PWA), and only the icons actually referenced end up in the bundle.

Outline (1.5px stroke, 24×24) is the default style. Solid (20×20) is
reserved for high-emphasis or destructive actions where the extra visual
weight is wanted.

### Delivery

Each icon lives as a one-line Reflex widget in `Frontend.Widget.Icon`,
with the SVG markup pasted directly from heroicons.com. No runtime
registry, no class lookup — `iconCalendar`, `iconLogOut`, `iconPlus`,
etc. are just `m ()` values. Adding a new icon: copy its SVG from the
Heroicons site, drop it into the module as a new function, use it.

The shared button helper in `Frontend.Widget.Form` accepts an icon
widget alongside the label so the icon-to-label spacing stays consistent
across every call site.

## Customising a daisyUI theme in the future

When the app has a brand identity or specific colour requirements, daisyUI
themes can be customised without replacing the framework. The mechanism works
entirely inside the CSS entry point (`static/src/css/styles.css`).

### Overriding an existing theme

Override individual design tokens on a built-in theme by re-declaring CSS
custom properties after the `@plugin` directive:

```css
@plugin "daisyui" {
  themes: light --default, dark --prefersdark;
}

/* Brand overrides on the light theme */
[data-theme="light"] {
  --color-primary: oklch(55% 0.24 260);    /* custom brand blue  */
  --color-secondary: oklch(65% 0.15 330);  /* custom accent pink */
  --border-radius-btn: 0.5rem;             /* rounder buttons    */
}
```

This keeps every other token from the `light` theme intact and only changes
what is explicitly listed.

### Defining a fully custom theme

For complete control, declare a new theme name and supply all required tokens:

```css
@plugin "daisyui" {
  themes: luciana --default, dark --prefersdark;
}

[data-theme="luciana"] {
  --color-base-100: oklch(98% 0.01 80);
  --color-base-200: oklch(95% 0.01 80);
  --color-base-300: oklch(90% 0.02 80);
  --color-base-content: oklch(25% 0.02 80);
  --color-primary: oklch(55% 0.24 260);
  --color-primary-content: oklch(98% 0 0);
  --color-secondary: oklch(65% 0.15 330);
  --color-secondary-content: oklch(98% 0 0);
  --color-accent: oklch(70% 0.18 150);
  --color-accent-content: oklch(20% 0 0);
  --color-neutral: oklch(40% 0.02 260);
  --color-neutral-content: oklch(95% 0 0);
  --color-error: oklch(55% 0.22 25);
  --color-error-content: oklch(98% 0 0);
  --color-warning: oklch(75% 0.18 85);
  --color-warning-content: oklch(20% 0 0);
  --color-success: oklch(60% 0.19 145);
  --color-success-content: oklch(98% 0 0);
  --color-info: oklch(65% 0.18 240);
  --color-info-content: oklch(98% 0 0);
  --border-radius-btn: 0.5rem;
  --border-radius-badge: 1rem;
  --border-radius-box: 0.75rem;
  --border-btn: 1px;
  --animation-btn: 0.25s;
  --animation-input: 0.2s;
}
```

The full list of available tokens is documented at
[daisyui.com/docs/themes](https://daisyui.com/docs/themes/). All values use
the `oklch` colour space, which is what daisyUI 5 expects.

### What stays the same

Regardless of theme customisation:

- **No Haskell changes are needed.** Component classes like `btn`, `card`,
  `input`, `navbar` remain identical — only the underlying CSS variables
  change.
- **The Nix build is unaffected.** Theme tokens live in the CSS source file;
  the derivation in [`static/default.nix`](static/default.nix) does not need
  modification.
- **Dark mode keeps working.** As long as a `--prefersdark` theme is declared
  in the `@plugin` block, the OS-level toggle continues to function.

## When to revisit

- A brand palette or logo is chosen → override `--color-primary` and friends.
- The period-status colours (green / yellow / red from the
  [goal](plans/goal.md)) need to map to semantic tokens → define `--color-success`,
  `--color-warning`, `--color-error` to match.
- A user-facing theme picker is desired → add more theme names to the
  `@plugin` block and wire a `data-theme` attribute toggle in the frontend.
