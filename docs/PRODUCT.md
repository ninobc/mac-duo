# Mac Duo — Product Spec

**One line:** The iPhone Duo fold, on your MacBook. Close the lid and your desktop folds with it: the picture stays put in the room while the glass tilts over it, softening into frosted light from the hinge outward. Open it, and everything comes back into focus.

Website: https://mac-duo.com · Bundle ID: `com.mac-duo.app` · macOS 14+ · Apple silicon + Intel

## The effect (what people praised on iPhone Duo)

Apple's fold transition does three things at once, and Mac Duo reproduces all three:

1. **Content is locked in space.** The UI does not move with the moving pane; the pane shows what the fixed content looks like *through* it (fixed front-view re-projection). On a MacBook the lid is the moving pane and the desktop is the content.
2. **Progressive frost.** Blur and darkening follow the *content's* coordinates, growing from the hinge outward, so the far edge dissolves first. Colour bleeds past the picture's edges into the dark, like light through frosted glass.
3. **Continuity.** No cut. Closing and opening are the same curve run backwards, driven by the real hinge angle, with a spring so the 10 Hz sensor feels like 120 Hz.

Mac Duo adds a **glass sheen** (a faint highlight that travels across the frost mid-fold) and a **focus-on-wake** reveal (the desktop un-frosts when you open the lid), both optional.

## Surfaces

- **Menu bar item** with a custom lid glyph. Menu: status/angle, Enabled, Preview, Style presets, Settings…, Check for Updates…, About, Quit.
- **Settings window** (General · Effect · Advanced · About). Effect tab has a *scrub* slider that folds the real screen live while you drag.
- **Onboarding** on first launch: Welcome → Screen Recording → Ready (Launch at Login, Try it).
- **Unsupported Mac** state: clear message listing supported models.

## Presets

| Preset | Start | Span | Blur | Dim | Depth | Sheen |
|---|---|---|---|---|---|---|
| Duo (default) | 100° | 60° | 96 pt | 100% | 1.0 | on |
| Soft | 95° | 45° | 60 pt | 70% | 0.8 | on |
| Cinematic | 110° | 75° | 140 pt | 100% | 1.3 | on |

## Non-goals (v1)

External displays. Windows/Linux. Sound. Sparkle auto-update (manual check only).

## Definition of done

- [ ] App builds with `Scripts/build.sh`, launches, shows onboarding, grants permission, runs the effect on a real lid close.
- [ ] Preview works without moving the lid. Scrub slider folds the screen live.
- [ ] Settings persist; presets apply; reset works; launch at login works.
- [ ] Focus-on-wake works after unlock.
- [ ] No effect on external-only setups; graceful on Macs without the sensor.
- [ ] 60 fps on M-series, idle CPU < 0.5%, no capture running when idle.
- [ ] Unit tests for geometry, curves, spring, state machine, version compare.
- [ ] App icon (.icns), menu bar glyph, DMG packaging, release script, GitHub Actions.
- [ ] Website for mac-duo.com with interactive fold demo, download, install guide, FAQ, privacy.
- [ ] README, LICENSE (MIT), CHANGELOG, privacy statement.
