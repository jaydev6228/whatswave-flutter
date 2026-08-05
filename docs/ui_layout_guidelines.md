# UI layout guidelines

Binding rules for any UI code in this app (new screens, edits to existing ones). Rooted in the user's standing instruction: layout must never cut off/overflow on any screen size or accessibility setting. Grounded in current official docs (linked per section, checked 2026-08).

## Why this exists

A device can shrink or grow your available space along **three independent axes**, and any of them can break a layout that only accounts for the other two:

1. **Physical screen size** — a compact phone (iPhone SE, small Android) vs. a large one.
2. **System font scale** — an accessibility setting, independent of screen size. Android 14+ allows up to **200%**, applied with a *nonlinear* curve where small text (like nav labels, badges, captions) scales *more aggressively* than large headline text. iOS Dynamic Type has a similar range via "Larger Text."
3. **Android "Display size" / zoom** — a *separate* setting from font scale. It changes the effective density (dp), shrinking or growing *everything* — icons, padding, touch targets, not just text.

A layout tuned only against axis 1 (e.g. a nav-bar label scaled down for narrow screens) can still overflow on a *wide* phone if the user has axis 2 or 3 cranked up. This is exactly what happened with the Communities tab label.

Sources: [Android — Support user-scalable content](https://developer.android.com/develop/ui/compose/accessibility/scalable-content), [Flutter — Deprecate textScaleFactor in favor of TextScaler](https://docs.flutter.dev/release/breaking-changes/deprecate-textscalefactor).

## Rules

### 1. Never size a text-containing widget with a fixed height

Fixed heights are what actually cause overflow/clipping when text scale grows — the text needs more vertical room and the container doesn't have it. Prefer:
- `Flexible`/`Expanded` inside `Row`/`Column` instead of `SizedBox(height: X)` around anything with text.
- Let `Column`/`Row` size to content (`MainAxisSize.min` where needed) rather than pinning a height.
- If a fixed height is unavoidable (e.g. an image), put the *text* in a `Flexible`/`Expanded` sibling, not the same box.

### 2. Cap `maxLines` + `TextOverflow.ellipsis` on anything that must stay single-line by design

Don't let unconstrained text silently wrap and push other layout around. If a label is meant to be one line, say so explicitly:
```dart
Text('Communities', maxLines: 1, overflow: TextOverflow.ellipsis)
```
This doesn't fix cramped space by itself (rule 4 does), but it guarantees a *predictable, non-broken* failure mode instead of unpredictable wrapping/overflow.

### 3. Never assume screen-width scaling covers accessibility text scaling too

Scaling a font size down for narrow *screens* (like this app's existing `navigationLabelScaleForWidth`) says nothing about the user's *system* text-scale setting. Both apply simultaneously and multiply together. Always test the combination (see Testing checklist), not just screen width in isolation.

### 4. For fixed-chrome UI (nav bars, tab bars, app bars, badges) — clamp text scale, don't fight it

Primary navigation chrome has a fixed slot it must fit in; letting it scale all the way to 200% will break it no matter how the layout is built. Flutter's official, current API for this is `MediaQuery.withClampedTextScaling`:

```dart
MediaQuery.withClampedTextScaling(
  maxScaleFactor: 1.3, // tune per element; nav labels can usually tolerate ~1.2-1.4x
  child: NavigationBar(...),
)
```
Reserve this for **chrome/navigation only**. Never clamp scaling for actual readable content (message text, story captions, settings, body copy) — that's the exact audience the accessibility setting exists for, and suppressing it there defeats the purpose.

Source: [Flutter — Deprecate textScaleFactor in favor of TextScaler](https://docs.flutter.dev/release/breaking-changes/deprecate-textscalefactor) (`MediaQuery.withClampedTextScaling`, `MediaQuery.withNoTextScaling`, stable since Flutter 3.16).

### 5. Reading the current scale in code

`textScaleFactor` is deprecated. Use:
```dart
final scale = MediaQuery.textScalerOf(context).scale(fontSize);
```
not `MediaQuery.of(context).textScaleFactor` (legacy, still works but don't write new code against it).

### 6. Prefer flexible layout primitives over manual pixel math

- `Wrap` for a row of chips/actions that might not fit on one line at any scale, when wrapping to a second line is actually acceptable there (unlike primary nav — see rule 4).
- `FittedBox` to scale content down to fit its box, for cases where shrinking is preferable to wrapping/clipping (use sparingly — it can make text too small to read, which is its own accessibility problem).
- `LayoutBuilder`/`MediaQuery.sizeOf(context)` when a decision genuinely depends on available space, not a guessed breakpoint.
- Avoid `Row`s of many fixed-width items with no `Expanded`/`Flexible` anywhere — one growing element is what absorbs the slack instead of overflowing.

### 7. Don't hardcode icon/tap-target sizes below the platform minimum

Minimum 48x48dp tap target (Android) / 44x44pt (iOS), even when an icon glyph inside is small. This isn't primarily a scaling issue but comes from the same accessibility research base — cite it here so it isn't relitigated per-widget.

## iOS notes (secondary priority, but do not skip)

- iOS Dynamic Type maps onto the same `MediaQuery.textScalerOf(context)` value Flutter uses on Android — the rules above apply identically; no iOS-specific API is needed in this codebase's Flutter code.
- iOS's accessibility text sizes (the "AX" sizes, beyond the standard Dynamic Type range) can exceed even Android's 200% — treat 200% as the floor for testing, not the ceiling.

## Testing checklist (before considering any UI change done)

Test at minimum this combination, not just default settings:
1. **Narrowest supported phone width** (this app already has device-matrix widget tests for iPhone SE / small Android — use them) **crossed with** **largest font scale**.
2. Android: Settings → Display → Font size → largest (200% on Android 14+). Separately, Settings → Display → Display size → largest — this is a *different* setting from font size and must be tested independently, not assumed covered by font-size testing.
3. iOS: Settings → Accessibility → Display & Text Size → Larger Text → drag to maximum, including the "Larger Accessibility Sizes" toggle.
4. Confirm: no clipped text, no silently-hidden buttons, no overlapping widgets. Wrapping to a second line is acceptable *only* for content explicitly designed to wrap (rule 6's `Wrap` case) — never for primary nav/chrome (rule 4).

## Precedent already in this codebase

The user's standing instruction from earlier in this project: layout must never cut off on any screen size, prioritize what's important, auto-scale rather than clip (see the Communities "Add to community" button fix, which replaced a `Wrap`/`SingleChildScrollView` fight with an icon-only button that simply fits). Apply the same standard to text-scale overflow, not just narrow-width overflow — they're the same underlying requirement.
