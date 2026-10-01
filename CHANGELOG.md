# Changelog

## 1.0.3 — 2026-10-01

- Fixed the screen freezing after swiping between Spaces or full-screen apps (issue #1). With the lid resting near the start angle (Cinematic starts at 100°), the press of a trackpad swipe could start a fold. That fold put up a still of the screen instead of the live picture and held it until the lid opened past 104°.
  - A fold now needs the lid to close at least 2° from where it rested. Typing or swiping no longer starts one.
  - A live fold always starts its live picture, however it began.
  - A fold whose lid is back above the start angle shows nothing, so it lets go after 0.6 s.
  - If macOS stops the screen capture during a fold, it restarts. A capture that finishes starting after it was stopped is closed instead of left running.

## 1.0.2 — 2026-09-14

- Signed with a Developer ID certificate and notarized by Apple. macOS opens Mac Duo without the "Not Opened" warning; no Open Anyway step.
- Bigger sense of depth: the frozen desktop stands at the start angle and the eye sits closer, so the picture converges hard as the lid comes down. Hinge rows frost at the end of the close.
- README and mac-duo.com carry install notes for macOS Sequoia.

## 1.0.1 — 2026-09-11

- Check for Updates now reads GitHub Releases directly and downloads the disk image into Downloads, then opens it.
- Releases publish version-less `Mac-Duo.dmg` and `Mac-Duo.zip` so the download link on mac-duo.com always points at the latest build.

## 1.0.0 — 2026-09-11

First release.

- The Duo fold on the built-in display, driven by the lid angle sensor.
- Three styles (Duo, Soft, Cinematic) and full control in Settings, with a live scrub slider.
- Focus on wake: the desktop comes back into focus after the Mac wakes.
- Menu bar item with a live lid glyph, preview, and style switching.
- Onboarding with the Screen Recording permission flow and an unsupported-Mac state.
- Launch at login, daily update check against mac-duo.com, diagnostics export.
