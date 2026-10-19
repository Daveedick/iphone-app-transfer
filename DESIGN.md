# iPhone App Transfer — approved design

Approved 19.10.2026. Product name: **iPhone App Transfer**. Mode: Operate. The interface exists to perform transfers clearly, with the restraint and precision of a native Mac utility.

## Visual authority

Current native reference after the approved Raycast refinement: [dark RU](docs/screenshots/raycast-three-dark.png), [light EN](docs/screenshots/raycast-three-light.png), [five-device narrow](docs/screenshots/raycast-five-narrow.png). These screenshots use explicitly synthetic demo data; their surfaces and selection rules supersede the earlier prototype visuals.

The saved screenshots show the earlier App Transfer branding and remain historical visual evidence. The current app and HTML references use iPhone App Transfer; no screenshot has been relabeled or fabricated for the rename.

Layout and frosted-material reference: [approved-glass.html](prototypes/approved-glass.html). Screenshots: [dark](prototypes/screenshots/approved-dark.png), [settings](prototypes/screenshots/settings-dark.png), [light English](prototypes/screenshots/settings-light-en.png).

The earlier [Raycast-oriented prototype](prototypes/previous-raycast.html) records the basic layout. The approved frosted version supersedes its surfaces, density, settings and motion. The user accepted the frosted concept, then requested deletion and outside-click dismissal. Those corrections are binding even though the saved HTML predates them.

On 19.10.2026 the user approved a visual refinement using supplied Raycast screenshots: quieter neutral selection, fewer borders, flatter controls and more consistent alignment. The requirements in **Raycast refinement** below supersede conflicting visual details in both saved prototypes. The existing library, equal device columns, queue, task flows and dismissal behavior remain the product structure; this is an approved refinement, not a new discovery phase.

Do not reproduce prototype-only shortcomings: fake USB state, demonstration queue on every real launch, sample account names, toy logos, browser-specific wrapping, truncated five-row queue, timer-based download percentages, missing multi-selection, or missing outside-click dismissal. The HTML is not a product codebase.

## Visual language

- Raycast remains the reference for density, search, restrained hierarchy and quick actions. Arc is only the reference for a collapsible library sidebar.
- Soft frosted translucency with substantial tint and contrast. Use appropriate standard macOS materials and vibrancy; avoid exaggerated refractive Liquid Glass effects.
- Background blur samples real window/desktop surroundings in the native app. The colored frame behind the HTML is only a stand-in for desktop scenery; do not ship it as a decorative frame or wallpaper.
- Library and toolbar are distinguishable by slight surface changes; device columns form a continuous workspace with subtle dividers.
- Text/icons stay crisp and opaque. Never reduce entire-window opacity to fake glass.
- Theme variants are equally complete. Respect Reduce Transparency, Increase Contrast and Reduce Motion.

## Geometry and type

Numbers below describe the approved mock, not Apple's universal constants. Prefer native metrics where available and verify the result against the screenshots.

| Element | Starting point |
| --- | --- |
| Main window | Native macOS rounding; mock approximates 16 px |
| Sidebar | About 196–220 pt, collapsible; future resize is optional |
| Device column | Minimum about 240 pt; around 260–300 pt when space allows |
| Compact app row | About 46 pt; default |
| Comfortable app row | About 57 pt |
| App icon | 28 pt compact; 30 pt comfortable |
| Row/control rounding | About 7–9 pt, coordinated with padding |
| Popover rounding | About 14–16 pt in the mock; native geometry first |
| Typography | System/SF; app names 12.5 pt, secondary row text 11 pt |
| Feedback | About 120–160 ms for hover/selection fill; 220–300 ms for sidebar transition |

Apple's recent design describes concentricity: nearby nested corners follow the container's geometry. Compact Mac controls retain rounded rectangles. Do not turn every control into a large pill. Standard window geometry should follow the running OS rather than copying a constant from one screenshot. See [Apple's design system](https://developer.apple.com/videos/play/wwdc2025/356/) and [macOS 27 AppKit updates](https://developer.apple.com/videos/play/wwdc2026/289/).

Use `NSVisualEffectView` with a purpose-appropriate material via a narrow AppKit wrapper when SwiftUI alone does not provide the desired behind-window effect. The baseline must still work on macOS 15. Do not make APIs introduced in 26/27 unconditional. [Apple: NSVisualEffectView](https://developer.apple.com/documentation/appkit/nsvisualeffectview)

## Raycast refinement — approved 19.10.2026

The supplied Raycast launcher, settings, account, menu and tooltip screenshots establish the direction: hierarchy through spacing, typography and small luminance differences. Borders identify structure or a focused control rather than outlining every interactive element. Preserve the frosted window with a substantial neutral tint, using approximately 78% tint as the implementation starting point; text and icons remain opaque and readable over different desktop backgrounds.

- **Rows:** flat at rest, with no persistent stroke or shadow. Hover uses a subtle neutral fill. Selection uses a stronger neutral gray fill, lighter in the dark theme and darker in the light theme, with a coordinated 7–8 pt radius. Do not use green app selection. Keyboard focus has one thin neutral indicator visible during keyboard navigation; it must not stack with a second focus contour. Increase Contrast may strengthen these distinctions.
- **State semantics:** ordinary ready library items have no permanent checkmark. Exceptional states such as missing IPA, failure and active work retain an explicit icon or label. Selection, archive readiness and drag destination are separate visual states. A highlighted drop destination and action label appear during a drag only.
- **Borders:** retain structural hairlines between library/devices, between device columns and above the queue. Avoid row borders, nested panel outlines and per-job separators. Search has a soft resting fill without an idle border; a focused search receives an appropriate visible indicator.
- **Toolbar/navigation:** ordinary tools are borderless, with a restrained hover/open fill. The selected device shortcut uses a neutral fill. Show the library shortcut as a quiet keyboard hint rather than a separate prominent control. Hierarchy should keep account/settings/update actions from competing with app content.
- **Column alignment:** use a consistent 68 pt device/library header region, then align search and count lines across columns. Keep compact rows at 46 pt and comfortable rows at 57 pt. Use 28/30 pt icons, 12.5 pt app names and 11 pt details; names should not all look like heavy section headings. Use one global drag hint instead of repeating the same instruction in every column.
- **Actions/queue:** a compact 44 pt contextual selection bar presents selection count and relevant actions. The queue header is 40 pt. Quiet completed tasks, small state icons and progress distinguish task status. Cancel and other ordinary controls do not need permanent button plates. Preserve all queue states, cancel boundaries and access to every task.
- **Settings/accounts:** aligned label/control rows and spacing separate groups. Keep account rows, input surfaces and action controls visually quiet; show clear focus, errors and authorization state. Menus/popovers have one outer boundary with a restrained shadow and neutral item selection. Existing outside-click, deactivation and Escape dismissal still applies.
- **Motion:** animate hover/selection fills briefly, without scaling ordinary buttons on each press. Sidebar and queue changes remain smooth and short. Respect Reduce Motion, Reduce Transparency and Increase Contrast; these preferences must preserve focus and status readability.

Verification for this refinement includes light/dark themes, both densities, single/multiple selection, mouse and keyboard focus, a visible drop destination, library/queue visibility, three-device composition and five-device overflow. Synthetic visual fixtures must be labeled as such; a single connected phone does not prove multi-device live transfer behavior.

## Main window

Toolbar: traffic lights, app name, Devices / Activity navigation, Accounts, Settings. The library toggle exposes `⌘S`. Settings exposes `⌘,`.

Below the toolbar: connected-device quick navigation. The count and names are derived from live discovery; each navigation control scrolls to its device column.

Each device header includes name, model, iOS and USB/connection state. Where names collide, show a short disambiguator. Search, app count and optional free storage follow. Distinguish installed and offloaded apps; show unknown metadata honestly.

Row: icon, app name, version, compact state. Avoid displaying bundle IDs, Apple request details or long account labels on every phone row. Put these in details/context actions where relevant.

Selection action bar: app/count, current location, meaningful destinations, save-to-library, and library deletion when the selection is in the library. No permanent global source/target pickers. For many devices, destination actions may use a menu rather than overflow into tiny buttons.

## Library and deletion affordance

Header: Library + help; count/size; independent search. Multiple stored variants must be distinguishable by version/build and account in details. Do not present a license from one account as interchangeable with another.

Tooltip: “Здесь хранятся скачанные приложения для установки на другие устройства. Может потребоваться Apple Account, под которым они скачаны.” Provide an English equivalent.

Add **Delete from Library…** to context menu and selection action bar, with trash icon plus understandable label. `⌘⌫` may invoke this only with library selection/focus and only via the confirmation flow. Explain that installed apps stay on phones. Busy archives cannot be removed silently.

Device uninstall, if implemented, is a separate destructive action named with the destination phone. It is never a side effect of library cleanup.

## Queue and activity

Queue header always offers collapse/expand and an honest pause/resume control. Paused, awaiting device, awaiting account, downloading, validating, installing, verifying, done, skipped, canceled and failed are distinct states.

Show source → destination, version when relevant, readable current stage, progress only where measured, and an appropriate cancel control. Percentages for downloading and installing are separate; do not invent one precise combined percentage or ETA.

Finished items may be visually quieter. Every queued item remains accessible even if there are hundreds; use a scrolling or virtualized queue rather than the HTML's demonstration slice.

Activity shows full account emails as approved, but no auth secrets. Errors explain recovery: reconnect/unlock device, choose account, sign in again, select another version, free space, retry a failed network request.

## Popovers, keyboard and animation

- Settings: language, density, theme; immediate application and persisted preferences.
- Accounts: saved identities, authorization state, add/remove identity, reauthenticate. Passwords only in secure input, 2FA field separate.
- Close ordinary popovers on outside click inside the app, outside the main window, app deactivation, Escape, or another popover opening.
- Use native transient behavior plus appropriate app/window notifications. System menus/Keychain panels must not destroy an auth flow. Dismissal is not task cancellation.
- Return keyboard focus to the triggering control. No Accessibility permission just to dismiss a panel.
- Brief fill-only press/selection feedback; smooth sidebar expansion with content tracking; clear drop target and inserted-row feedback. No scale on ordinary button presses, perpetual shimmer, bounce on every text update or delayed access while animation finishes.
- Reduced Motion substitutes quiet immediate changes. Focus rings and state labels remain visible in all themes.

[Apple transient popovers](https://developer.apple.com/documentation/appkit/nspopover/behavior-swift.enum/transient) and [motion guidance](https://developer.apple.com/design/human-interface-guidelines/motion) inform implementation; prototype timers do not dictate SwiftUI architecture.

## Required visual states

1. No devices: connect/unlock/trust instructions in place.
2. One device plus library: downloading/installation from library still available.
3. Three connected devices: approved default composition.
4. Five devices in a narrow window: readable columns, horizontal navigation and drag-edge scrolling.
5. Phone locked / trust pending / disconnected: truthful header and task state.
6. Empty library, populated library, search-empty, missing local IPA, multiple versions/accounts.
7. Library hidden, queue hidden, both hidden.
8. Downloading → validating → installing → device readback → success.
9. Missing license, unsupported TestFlight metadata, account reauthentication, invalid IPA, no space.
10. Single/multiple library deletion, busy-file conflict, optional phone-uninstall confirmation.
11. Settings/accounts open and dismissed by outside interaction.
12. Light/dark, Russian/English, compact/comfortable, accessibility preferences.

Validate the native app against these states. A web-like settings overlay glued to the window or a terminal disguised as a log does not meet the approved direction.


## Queue update approved 19.10.2026 — 0.1.2

- The top queue divider is a full-width drag target with an understated center grip and vertical-resize cursor. Height persists between launches; ↑/↓ and accessibility adjustment also change it. Default body height is 240 pt, desired range 80–900 pt; the effective maximum reserves room for the device/library header, controls and at least a compact app row. Shrinking a window clamps display without overwriting the saved preferred height.
- New tasks display first. Explicit retry moves that row to the top. Progress and completion never change the presentation order, and the coordinator's stored execution array remains independent; retry changes presentation recency without moving the job's execution position. No user sorting control.
- Accepted enqueue and retry show a short confirmation in the queue header, highlight affected rows and scroll to the corresponding task. If the queue is collapsed, confirmation stays in its header without expanding it. Progress polling does not scroll. A duplicate pending request identifies and reveals the existing task instead of silently doing nothing.
- The confirmation is ephemeral; saved tasks, account/library data and the chosen height persist. Queue feedback contains app names/counts, never secrets.


## Queue resize refinement approved 19.10.2026 — 0.1.3

The resize target is a full-width **20 pt** band, twice the previous height. Its center grip is 40 × 3 pt and becomes clearer on hover or keyboard focus. AppKit owns cursor tracking and native mouse dragging for the entire band, rather than a one-shot SwiftUI hover cursor. Cursor updates retain the vertical-resize cursor while dragging. Fixed screen-coordinate deltas prevent the moving divider from changing the drag origin. SwiftUI retains one keyboard/accessibility adjustment control. The extra band height is included in the workspace's queue limit.
