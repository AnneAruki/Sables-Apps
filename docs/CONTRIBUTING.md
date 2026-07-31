# Contributing to Sable's Library

This doc defines the working lane for Sable's Apps. Use it with [DESIGN.md](DESIGN.md), the repository README, and the current code before proposing or implementing larger changes.

Sable's Library is a macOS tool for making messy comic, manga, and ebook folders easier to review and maintain. The app can be charming, but the work is real file safety: scan, explain, preview, review, apply, restore, and report.

## The Lane

Work fits Sable's Library when it improves at least one of these:

- QOL for repeated library cleanup.
- Safer file changes.
- Clearer review-before-apply flows.
- Better accessibility and inclusive wording.
- More native macOS behavior.
- Calmer settings, progress, errors, and results.
- More useful local learning, deterministic suggestions, or Apple Intelligence review assist.
- Better recovery: cancel, restore, undo plans, reports, and clear next steps.

Work is suspicious when it mainly adds:

- more settings without reducing risk or repeated work,
- more personality without making the workflow clearer,
- automatic file changes without review,
- custom controls where native SwiftUI/AppKit controls already fit,
- network behavior hidden inside unrelated actions,
- appearance variety instead of a coherent appearance system.

## Locked Principles

### File safety

- Preview before apply is the default shape.
- Any action that moves, renames, repairs, writes sidecars, exports reports, contacts a service, or restores files needs plain wording.
- Duplicate detection can identify exact matches, but deletion should not become automatic.
- Restore and undo wording must say what changed and what remains untouched.

### Sable voice

- The app may sound like a careful Sable.
- Use whimsy for warmth, progress, empty states, and low-risk guidance.
- Use plain language for danger, privacy, errors, network access, and destructive confirmation.
- Never rename a risky action into a joke.

### AI/ML

- AI/ML is part of the app. Use it where it improves review quality.
- Local learning and on-device Apple Intelligence can explain, summarize, prioritize, and flag uncertainty.
- AI/ML must not silently apply file changes, invent title facts, delete files, or override deterministic safety checks.
- If Apple Intelligence is unavailable, deterministic behavior and local learning continue.
- Network metadata tools remain explicit because they contact outside services.

### Appearance

- Prefer system light/dark plus curated accent and semantic status colors.
- Status colors communicate meaning. Accent communicates brand chrome and selection.
- Liquid Glass goes through shared helpers and must have readable solid fallbacks.
- Native menus stay native. Style visible triggers or surrounding chrome, not system popovers.

## Safe PR Areas

These are usually good places to work:

- Documentation: `README.md`, `SECURITY.md`, `docs/DESIGN.md`, this file, and focused behavior notes.
- Accessibility: VoiceOver labels/values, keyboard navigation, focus, contrast, scalable text, Reduce Transparency, Increase Contrast.
- Microcopy: clearer settings, progress, error, restore, and review wording.
- Design-system migration: replacing one-off surfaces/colors with shared palette roles and surface helpers.
- Review screens: filters, counts, Select All/None, clearer empty states, safer row actions.
- Build/test hardening: focused tests, diagnostics, safer async/cancellation paths.
- AI/ML review assist: better notes, confidence labels, summaries, and fallbacks.

## Coordinate First

Ask or audit before changing:

- core file-move behavior,
- duplicate deletion or automatic duplicate handling,
- MangaBaka/network behavior,
- restore/undo semantics,
- app-wide appearance architecture,
- new top-level navigation,
- new settings sections,
- anything that changes what Inspect Library prepares by default,
- any AI/ML behavior that could affect file changes.

## Do Not Add

- Hidden background cleanup.
- Auto-delete duplicates.
- Broad AI apply behavior.
- Network calls without visible user intent.
- Custom menu popovers.
- An appearance playground.
- Lore-heavy onboarding.
- Error messages that mainly show raw logs.

## Review Checklist

Before calling work done:

- Does it match `docs/DESIGN.md`?
- Does it fit this contributing lane?
- Does the user know whether files changed?
- Is network access visible when relevant?
- Does AI/ML assist review only?
- Are native controls used where they fit?
- Are VoiceOver, keyboard access, contrast, scalable text, Reduce Transparency, and Increase Contrast considered?
- Does the app build?
- Are remaining manual checks clear?
