# Sable's Library Design Ethos

Last updated: 2026-06-08

The principles that guide every design decision in Sable's Library. When a UI choice is unclear, check it against this file before adding more settings, more warnings, or more decoration.

The current interface should be verified in the running apps with keyboard, VoiceOver, light mode, and dark mode before release.

## 1. Be a careful Sable first.

Sable's Library works with real folders and files. The app may be whimsical, but file operations are serious. Before anything moves, renames, repairs, exports, contacts a service, or writes a report, the user should understand what will happen and how to recover.

The product goal is quality of life: inclusivity, accessibility, clarity, privacy, safety, and a calm user experience. Good design here reduces worry and decision fatigue. It should help people understand what is happening without making them feel judged for having a messy library.

## 2. Whimsy supports clarity.

The app can sound like a Sable: observant, practical, slightly playful, and protective of the collection. That voice belongs in empty states, progress notes, review summaries, and gentle guidance. It does not belong in a way that hides risk. Destructive actions, privacy notes, errors, and confirmations use plain language first.

Safety copy can still be warm. The important rule is that the metaphor must explain the real file concept, not replace it. A good line can say "Sable checks every book file for file type, odd edges, metadata clues, and reading order" because it still tells the user what is inspected. A bad line says "magic cleanup" because it hides the work.

Good Sable voice:

- "Sable found 12 possible duplicates. Review them before anything changes."
- "Nothing moved yet."
- "This folder needs a closer look."
- "The sidecar is missing, so ComicInfo needs review before folder names are trusted."
- "The volume clue is unclear. Keep this unchecked unless the number looks right."

Avoid:

- jokes in destructive confirmations,
- fantasy words for real file actions,
- cute labels that make a risky action less obvious.

The whole app should sound like it has a careful Sable, not only onboarding. Onboarding can be the most flavorful part because it sets expectations, but the same voice belongs in desk cards, empty states, progress text, review summaries, reports, and gentle guidance. Use library folder, collection, review desk, cleanup plan, receipts, inspect, and pause language when it maps cleanly to real behavior. Pair every flavored phrase with plain safety meaning.

Good onboarding flavor:

- "Choose one library folder" plus "Choose the top folder that holds your books or comics."
- "Let Sable inspect first" plus "Preview before anything moves or renames."
- "Keep the receipts" plus "Reports and undo plans are saved."

Avoid onboarding flavor that hides scope:

- "Let Sable fix everything,"
- "Cast cleanup magic,"
- "Trust Sable,"
- any phrase that implies automatic file changes without review.

For ongoing app copy:

- Use "library check" or "collection check" when the app is inspecting.
- Use "desk note" for on-screen summaries.
- Use "receipt" for saved reports and audit trails.
- Use "placed on the desk" for review queues.
- Keep "file", "folder", "rename", "move", "network", and "undo" explicit whenever risk, privacy, or recovery is involved.

## 3. Review before apply.

The safest flow is preview, review, then apply. Cleanup, duplicate handling, tag review, missing-number moves, ComicInfo refresh, and MangaBaka matching should expose what the app found before changing user files. Automatic work is allowed only when it is narrow, reversible, already explained, and covered by settings or an explicit run choice.

## 4. AI and ML are part of the app, not a personality toggle.

Sable should use local learning, deterministic rules, and Apple Intelligence/Foundation Models when available to improve review notes, confidence labels, explanations, and prioritization. Users should not need to decide whether the app is "AI mode" or "normal mode."

The boundary is strict:

- AI/ML may explain, summarize, sort, flag, and help review.
- AI/ML may not invent facts, silently change rules, rename files by itself, delete files, or override deterministic safety checks.
- When Apple Intelligence is unavailable, the same workflows continue with deterministic suggestions and local learning.
- Network-based metadata tools remain explicit because they contact outside services.

## 5. Native first, custom second.

Use SwiftUI and AppKit primitives when they fit: `NavigationSplitView`, `ScrollView`, `List`, `Menu`, `Picker`, `Toggle`, `Button`, `Stepper`, sheets, alerts, commands, and Settings scenes. Custom cards and surfaces are fine when they make review workflows easier, but they should not replace native behavior people already understand.

Native menu contents stay native. Style the visible trigger or surrounding chrome, not the system menu popover.

## 6. Design for macOS.

Sable's Library is a Mac app, so it should feel comfortable in a resizable, persistent workspace. Use the sidebar for location and compact actions, the toolbar and menu bar for common commands, and the main area for the current review desk. Prefer keyboard shortcuts, pointer-friendly hit targets, contextual menus, drag/drop where it genuinely helps, and system Settings over custom control patterns.

Mac users expect to keep working while a window changes size, sits beside Finder, or stays open during long tasks. Layouts must handle roomy desktop windows without feeling empty, and smaller windows without hiding the primary workflow. Use progressive disclosure and sheets for deeper explanations, not for routine navigation.

## 7. Accessibility is the floor.

Every normal design should be accessible by default. Do not create a separate "accessible mode" to fix weak contrast or unclear controls. Check VoiceOver labels and values, keyboard navigation, focus, contrast, color blindness, scalable text, reduced motion, Reduce Transparency, Increase Contrast, and non-native English wording.

Color cannot be the only state signal. Use status words, icons, counts, shape, selection checks, and clear button labels.

## 8. Calm beats clever.

The app should feel calm even when the library is messy. Prefer fewer choices, clearer grouping, shorter labels, and progressive disclosure. Advanced options belong where repeated users can find them without overwhelming first-time users.

Do not add a setting unless it gives real control over risk, privacy, performance, accessibility, or repeated workflow comfort.

### Sidebar Advanced Explanations

The sidebar is the stable context layer. It may show short guidance at rest, but its info buttons are the home for deeper subject explanations: what a workflow concept means, which settings affect it, where privacy or network boundaries sit, what evidence the user should expect, and what an advanced inspector should eventually expose.

Keep the division clear:

- Settings are durable controls, not an education dump.
- The main dashboard is for current actions and review work, not long explanations.
- Sidebar popups can teach deeply because the user explicitly asked for more detail.
- Privacy and assist education belong in the sidebar unless they expose a durable control.
- Safety, privacy, receipts, undo, conflicts, and network-backed rows should be explained in concrete file-management terms.
- A short visible row should still be understandable without opening the popup.

## 9. Appearance is a system.

Use system light/dark as the base, semantic color roles for meaning, and a curated accent for brand chrome and selected states. Status colors stay semantic: success, warning, error, info, review, running, undo, and neutral should not become arbitrary accent colors.

Accent color should guide attention, not flood the workspace. Keep accent presets slightly muted in standard contrast, reserve stronger variants for increased contrast, and let neutral surfaces carry dense review content.

Routine info, success, warning, review, running, and undo states should use the selected accent plus clear words and symbols. Keep red for true errors. Avoid introducing unrelated yellow, blue, or green status tints unless a future workflow needs a distinct, documented safety meaning.

Liquid Glass is a hierarchy tool, not decoration. Use thin glass for small controls and chrome, regular glass for readable panels, and stronger glass only when text remains readable. Reduce Transparency, Increase Contrast, older macOS versions, and unsupported glass paths must keep solid readable fallbacks.

Current implementation note: the ambient background must also quiet itself under Reduce Transparency, Differentiate Without Color, and Increase Contrast. Decorative patterning is optional; readability is not.

When glass is unavailable or disabled, tinted glass surfaces must not lose their meaning or brand signal. Use a solid readable surface with a visible accent edge or rule instead of a translucent tint wash. In Increase Contrast, strengthen the border/rule; in Differentiate Without Color, never rely on the color alone to communicate state.

### Sable's Library Liquid Glass Rules

Sable's Library uses Liquid Glass as a brand and workspace preference, not as loose decoration. Glass should make the app feel like a persistent Mac work surface while preserving the seriousness of file review, recovery, and safety copy.

Use glass hierarchy deliberately:

- chrome, sidebars, and toolbar-adjacent surfaces can use stronger glass because they frame the workspace,
- active buttons and menu triggers use interactive glass so available actions feel alive and discoverable,
- content panels use readable glass with enough fill and contrast for scanning rows, badges, paths, and counts,
- text-heavy sheets and confirmations use the strongest readable surface over patterned backgrounds,
- safety copy, path text, receipt paths, undo details, and conflict warnings must remain clear before any decorative treatment.

Readability and accessibility override the glass preference. Reduce Transparency, Increase Contrast, Differentiate Without Color, older macOS versions, unsupported API paths, and user-disabled glass must fall back to solid readable surfaces with visible borders or accent rules. If a glass treatment makes a file path, warning, receipt, or confirmation harder to understand, simplify the surface before changing the copy.

### Window Mirror Rules

The window mirror effect is part of Sable's Liquid Glass personality. It should feel like the workspace continues into the window chrome, not like random content is being duplicated.

Mirror effect rules:

- Mirror is tied to the Liquid Glass preference and turns off with Reduce Transparency, Increase Contrast, Differentiate Without Color, or solid-surface fallback.
- Use mirror only on surfaces that behave like chrome, orientation, or education: the main sidebar/navigation layer, Settings shell, onboarding shell, and focused workflow-detail sheets.
- Future approved candidates: a report/receipt inspector window, a dedicated duplicate-comparison inspector, or a persistent bottom status rail if it touches window chrome.
- Do not use mirror on review rows, path text, confirmation dialogs, apply buttons, warning panels, dense settings controls, or anything the user must parse while deciding whether files change.
- If the mirrored area shows live text in a confusing way, either simplify the reflected surface or remove mirror from that view before weakening safety copy.

## 10. Privacy is visible.

Local scans, local learning, and on-device Apple Intelligence should be described as local. Anything that contacts an outside service must say so in plain language. MangaBaka/API work should remain explicit, visible, and reviewable.

Do not make broad privacy claims unless the code supports them.

## 11. Errors are recovery paths.

An error message should answer: what happened, whether files changed, what is safe, and what the user can do next. Avoid blame, vague technical output, or long raw logs as the primary UI. Keep detailed reports available for troubleshooting, but make the main screen understandable.

## 12. Ship in small, reviewable changes.

Do not rewrite the whole app to chase an aesthetic. Port design ideas in small passes: docs, design system, settings, shell, dashboard, run screens, then review screens. Each pass should build, preserve existing behavior, and explain its risk.

## Apple HIG Reference Map

Use these Apple Human Interface Guidelines pages as the main external reference set for future UI and workflow passes. Keep one reference per HIG topic, even when a topic affects several parts of the app.

### Trust, Safety, and Recovery

- [File Management](https://developer.apple.com/design/human-interface-guidelines/file-management) - Treat the chosen library folder, report folder, Finder handoff, file previews, renames, moves, and restore plans as the core product contract. Every file-changing step should clearly show the source path, destination path, collision state, and receipt path.
- [Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy) - Keep local scans, saved folder access, local learning, Apple Intelligence, and network-backed MangaBaka work visible and specific. Do not imply privacy guarantees unless the code enforces them.
- [Undo and Redo](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo) - Make undo plans and receipts feel like a normal Mac recovery path, not a hidden developer artifact. File-changing flows should offer a clear route back or explain when a change requires manual recovery.
- [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts) - Reserve alerts for moments that need immediate attention, such as destructive operations, unresolved collisions, failed writes, or permission loss. Keep the copy plain: what happened, whether files changed, and what the user can do next.
- [Modality](https://developer.apple.com/design/human-interface-guidelines/modality) - Use sheets and modal confirmation only for focused interruptions such as onboarding, settings, destructive confirmation, or narrow correction flows. The main review/apply flow should stay in the primary window.
- [Notifications](https://developer.apple.com/design/human-interface-guidelines/notifications) - Consider notifications only for long-running scans or apply operations that finish while the user is elsewhere. Notifications should never replace the in-app receipt and summary.
- [iCloud](https://developer.apple.com/design/human-interface-guidelines/icloud) - If iCloud Drive libraries are supported, be clear about sync timing, unavailable files, provider errors, and changes that may appear on other devices. Avoid assuming local disk behavior for cloud-backed folders.

### Core Mac Experience

- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos) - Keep Sable's Library recognizably Mac-native: resizable windows, command menus, keyboard shortcuts, pointer-friendly review rows, Finder integration, and a persistent work surface.
- [Launching](https://developer.apple.com/design/human-interface-guidelines/launching) - Launch into the last useful state without surprise work. If a saved library exists, show it and wait for Inspect; if not, show a calm first action.
- [Loading](https://developer.apple.com/design/human-interface-guidelines/loading) - Start quickly, then load heavy scan data after the app is interactive. Avoid blank waiting states; show the selected library, last known status, and a clear "Inspect" action while heavier context warms up.
- [Windows](https://developer.apple.com/design/human-interface-guidelines/windows#macOS-window-states) - Preserve a useful window size and layout across launches. The dashboard should work at compact, default, and large desktop sizes without clipping controls or stretching sparse content.
- [Multitasking](https://developer.apple.com/design/human-interface-guidelines/multitasking) - Design for side-by-side use with Finder, Preview, web metadata pages, or a text editor. Long tasks should not block reading receipts, checking settings, or reviewing already prepared rows unless the underlying file state would become unsafe.
- [The Menu Bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar) - Put persistent commands in predictable Mac menus: Choose Folder, Inspect, Stop, Open Reports, Show Onboarding, Reset Settings, and future Restore from Undo Plan. Menu items should mirror toolbar availability and shortcuts.
- [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) - Keep only high-frequency commands in the toolbar: Choose Folder, Inspect/Inspect Again, Reports, Settings, and Stop. Step-specific actions like Apply Checked belong in the step panel where their scope is visible.
- [Settings](https://developer.apple.com/design/human-interface-guidelines/settings) - Keep settings for durable preferences: risk, privacy, appearance, network use, accessibility comfort, and repeated workflow choices. Do not add settings for one-time decisions that belong in review rows.
- [Offering Help](https://developer.apple.com/design/human-interface-guidelines/offering-help) - Add help where users hesitate: folder choice, disabled network rows, collision rows, undo plans, reports, and correction feedback. Prefer contextual help text, tooltips, and links to receipts over long instruction screens.

### Navigation and Review Structure

- [Split Views](https://developer.apple.com/design/human-interface-guidelines/split-views) - Keep the sidebar and main desk as the stable shell. The sidebar owns library location and utility status; the main pane owns the current step and review decisions.
- [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars) - Use the sidebar for persistent context, not a toolbox. It should show the selected library folder, status, reports, and settings without competing with the step flow.
- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout) - Keep the dashboard dense but breathable. Use consistent alignment, predictable spacing, and stable row dimensions so review decisions do not jump around while counts or status labels update.
- [Scroll Views](https://developer.apple.com/design/human-interface-guidelines/scroll-views) - Long review plans should scroll without hiding the current stage, apply scope, or summary state. Avoid nested scrolling unless a focused comparison table genuinely needs it.
- [Lists and Tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables) - Use list/table patterns for large review sets, sorting, filtering, and comparison. Suggested changes should be scannable by stage, confidence, safety, operation, and path.
- [Outline Views](https://developer.apple.com/design/human-interface-guidelines/outline-views) - Consider outline-style review for hierarchical library data: series > volumes > files, duplicate groups > candidate files, or folders > ComicInfo state. This could improve review without flattening everything into cards.
- [Path Controls](https://developer.apple.com/design/human-interface-guidelines/path-controls) - Use path controls or path-like breadcrumbs for the selected library, proposed destinations, report folder, and receipts. They can make deep folder context easier to inspect than raw truncated paths alone.
- [Panels](https://developer.apple.com/design/human-interface-guidelines/panels) - Use panels for auxiliary information that can stay beside the main task, such as receipt previews, detailed file metadata, duplicate comparison, or an inspector-style explanation pane.
- [Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers) - Use popovers for short explanations, confidence details, row actions, or correction reasons. Avoid placing critical safety information only in a popover.
- [Text Views](https://developer.apple.com/design/human-interface-guidelines/text-views) - Use selectable, readable text views for receipts, logs, correction notes, and raw report previews. Keep logs secondary to human summaries.

### Controls, Input, and Interaction

- [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) - Make action weight match risk and scope. Inspect can be prominent; Apply Checked must stay near the visible checked plan; Stop and destructive actions need clear roles.
- [Toggles](https://developer.apple.com/design/human-interface-guidelines/toggles) - Use checkboxes/toggles for binary review decisions and durable preferences. In review rows, make checked state visible with text, icon, and selection state, not color alone.
- [Focus and Selection](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection) - Support keyboard and pointer review. Selection should expose the active row, details, and available actions without changing checked state accidentally.
- [Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards) - Add shortcuts for common Mac workflows: choose folder, inspect, stop, open reports, find/filter, select all safe suggestions, check/uncheck selected rows, and open receipt.
- [Pointing Devices](https://developer.apple.com/design/human-interface-guidelines/pointing-devices) - Treat hover, right-click, trackpad, and precise pointer selection as first-class. Context menus can expose row-level actions such as Reveal in Finder, Copy Path, Mark Wrong Series, or Skip.
- [Gestures](https://developer.apple.com/design/human-interface-guidelines/gestures) - Use gestures only when they complement Mac expectations, such as trackpad scrolling, disclosure expansion, and drag/drop. Do not rely on gestures for essential cleanup decisions.
- [Drag and Drop](https://developer.apple.com/design/human-interface-guidelines/drag-and-drop) - Allow dropping a folder onto the app as an alternative to Choose Folder. Future review flows could accept dropped files/folders for focused inspection or let users drag report paths to Finder.
- [Progress Indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators) - Show determinate progress when file counts are known and indeterminate progress when discovery is still open-ended. Pair progress with a plain current activity and a safe Stop behavior.

### Visual System and Content

- [Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode) - Use semantic colors and materials so the app remains legible in system light and dark appearances. Avoid hardcoded tints that make warning, review, or disabled states ambiguous.
- [Color](https://developer.apple.com/design/human-interface-guidelines/color) - Use color as reinforcement, not the only signal. Status colors should remain semantic for safe, review, warning, error, running, network, and undo states.
- [Typography](https://developer.apple.com/design/human-interface-guidelines/typography) - Keep headings, badges, file paths, summaries, and receipt text in a clear hierarchy. Dense review surfaces should remain readable at larger text sizes.
- [Icons](https://developer.apple.com/design/human-interface-guidelines/icons) - Keep the app icon and any custom imagery simple, legible at small sizes, and aligned with the careful Sable identity without making risky actions look playful.
- [SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols) - Prefer SF Symbols for toolbar buttons, row badges, state markers, and utility actions. Keep symbol meaning consistent across sidebar, toolbar, and review rows.
- [Writing](https://developer.apple.com/design/human-interface-guidelines/writing) - Balance the Sable voice with concrete file language. The copy should explain scope, safety, and recovery before adding flavor.
- [Inclusion](https://developer.apple.com/design/human-interface-guidelines/inclusion) - Avoid assumptions about how people organize books, comics, manga, languages, naming traditions, reading order, or technical skill. Let corrections teach the app without shaming the user.
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) - Treat accessibility as baseline quality. Check VoiceOver labels, keyboard navigation, focus rings, contrast, reduced transparency, increased contrast, scalable text, and non-color status.
- [Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding) - Keep first-run guidance short, skippable, and available later. It should teach the safety model: choose folder, inspect first, review checked changes, keep receipts.
- [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback) - Make every scan and apply result answer "what happened?", "did files change?", "what needs review?", and "what is the safest next action?".

### Intelligence, Automation, and Future Reach

- [Machine Learning](https://developer.apple.com/design/human-interface-guidelines/machine-learning) - Use local learning to prioritize, explain, and reduce repeated review work. Always show evidence for a suggestion, and never let learning override deterministic safety checks.
- [Generative AI](https://developer.apple.com/design/human-interface-guidelines/generative-ai) - Use generative help for summaries, review notes, explanations, and candidate comparisons. Do not allow generated text to invent metadata, silently rename files, or hide uncertainty.
- [Siri](https://developer.apple.com/design/human-interface-guidelines/siri) - A future Siri/App Intents layer could open the app, inspect the selected library, show the last receipt, or start a safe review flow. Avoid voice-triggered file changes unless the user confirms in the app.
