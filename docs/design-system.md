# PopRocket Design System

PopRocket should feel like a compact native operations console, not a generic settings form. The interface is built around one question first: is my homelab okay right now, and which trusted bridge knows that?

## Product Principles

- The bridge is the authority. Every operational surface should name or imply the active bridge and distinguish live state from cached state.
- Status comes before action. Health and bridge reachability sit above WOL and command controls because they answer whether action is safe.
- Actions are deliberate. WOL, command tiles, widget trust, reconnect, save, and delete controls must show pressed feedback, progress, and a result.
- Widgets are cached surfaces. Widgets may be glanceable and actionable, but they must show freshness and only run explicitly trusted saved actions.
- Text stays operational. Labels should be short, concrete, and stateful: `Live`, `Cached`, `Down`, `Trusted`, `Locked`, `Last confirmed`. Use `Ready` sparingly; prefer explicit ability labels such as `Can Wake`, `Can Run`, `Available`, or `Confirmed`.
- Widget action controls use trust language. Say `Trust` before an action is available to widgets and `Trusted` after it is allowed; avoid vague labels like `Widget` on a button.
- Positive health copy must name the evidence. Say `Checks Confirmed`, `Confirmed Up`, or `All Checks Confirmed`; avoid broad claims like “homelab healthy” unless every surface behind that claim is measured.

## UX Principles

- Navigation hierarchy: top-level tabs are destinations, not actions. A screen should have one primary job and should not duplicate another screen's job.
- Chunking: split unrelated jobs into separate tabs, sheets, or mode selectors. Do not ship one long vertical list that mixes status, setup, action, history, and settings.
- Progressive disclosure: show saved, repeatable operations first. Put raw/manual command entry behind an expansion or editor so it does not dominate the main action surface.
- Affordance and signifiers: tappable areas need iconography, pressed feedback, clear labels, and visible state. Disabled controls must explain why they are unavailable.
- Action tile accessibility must expose the same operational state as the visible tile: cached/locked/busy/running/failed/sent, the disabled reason when present, and the bridge that will execute the action.
- Feedback loop: every operation needs start, progress, success, failure, and recovery feedback. Visual feedback is mandatory, haptics are on by default, and audio cues are opt-in.
- Feedback controls must never feel dead. If haptics and audio are disabled, preview/test controls still produce visible confirmation.
- Noise budget: remove repeated bridge copy when the bridge is healthy. Surface bridge detail when it changes the user's decision: offline, cached, locked, failed, reconnecting, not added, or explicitly trusted for widgets.
- Trust boundary: widgets and command tiles must communicate what is trusted, what is cached, and what will run before the user taps.
- Trust counts are scoped to the current action type. A command section counts trusted command tiles only, a wake section counts trusted wake actions only, and mixed totals are reserved for the Widgets settings summary.
- Trust state should be shown once per row. Avoid repeating `Trusted` in a badge, body copy, and status line inside the same small surface.
- Settings surfaces should summarize authority and cache, then expose controls. Avoid restating the same bridge status or trusted-action count in the panel header, body, and row badges.

## Navigation

- Top-level app navigation uses five tabs: Home, Monitors, Actions, Activity, Settings.
- Home is the first screen and uses a structured overview, not a vertical list. It may summarize several areas, but each section must have one clear job.
- Home starts with a read-only evidence rail for `Bridge`, `Health`, `Actions`, and `Runs`. These are compact metric tiles, not navigation buttons: each tile shows one label, one value, one supporting detail, and one semantic state marker. They should fit as one row or a stable two-column grid before falling back to a vertical stack.
- Home must not duplicate the tab bar with another row of navigation tiles. It shows the current bridge situation, health exceptions, primary saved actions, and recent activity only when recent activity exists or needs attention.
- Legacy status snapshots are not a standing Activity section. Surface them on Home only as `Status Alerts` when a snapshot is stale while the bridge is reachable, reports an error, or has a warning/destructive state.
- The Home header should not show a large primary navigation button when the state is confirmed and the tab bar already provides navigation. Use the button only for offline, setup, warning, or recovery paths.
- The Home header should not explain successful routine state twice. If the bridge is live and health is confirmed, the header metrics carry the state; show the larger focus/recovery row only for setup, stale, unknown, down, failed, or offline situations.
- Settings belongs in the tab bar. Do not repeat gear buttons across Home, Monitors, Actions, and Activity unless a modal sheet specifically needs a local settings escape hatch.
- Settings first-run bridge setup must collapse into one `Bridge` empty-state section with one `Add Bridge` action. Do not stack `Active Bridge`, `Saved Bridges`, and `New Bridge` when no bridge exists.
- Actions are split by mode: Wake and Run. Manual command entry is progressive disclosure beneath saved command tiles.
- Use compact segmented controls for local modes such as Wake vs Run. Do not use large cards for a binary mode switch.
- Mode selectors select only. They may show an icon and label, but they must not repeat counts, status summaries, or explanatory copy that belongs in the selected section.
- The selected section owns counts and status context; do not duplicate the same count in the selector, section badge, and subsection header.
- The Actions tab always needs one compact authority strip after the mode selector. It names the bridge that will execute Wake or Run actions, so full tiles do not need repeated live bridge chips. When the bridge is fully live, the strip can be title + badge only; explanatory copy returns for cached, warning, or offline states.
- Activity is a run log, not another dashboard. Do not lead it with a second status summary that repeats Home.
- Tab badges are attention markers only: down monitors, failed recent runs, failed action state, or an already-configured bridge going offline. Do not badge first-run setup, routine healthy state, or routine cached content.
- Settings is for bridge authority, widget trust, and feedback preferences. It is not a duplicate dashboard.
- Secondary screens use plain screen titles instead of boxed header cards. Status panels belong inside content only when the status is actionable or exceptional.
- Secondary screens must not repeat the bridge header when the active bridge is healthy. Show bridge context there only while refreshing, offline, stale, or warning; missing-bridge screens use one empty-state recovery panel instead.
- Section names must describe the user's mental model, not the implementation. Prefer `Health`, `Quick Actions`, `Devices`, `Commands`, `Recent Runs`, and `Run Log` over generic labels such as `Cards`, `Operate`, `Recent`, or `Snapshots`.
- Each section gets one job. Do not mix saved command tiles, raw command entry, and command output in one visual group; split them into `Command Tiles`, `Run Once`, and `Latest Result`.
- Healthy routine context should disappear except where it establishes execution authority. Hide readiness panels and per-tile bridge chips when the active bridge is live and the screen-level context already identifies the authority; show them again for cached, locked, failed, or multi-authority decisions.
- Pairing is a trust-establishment flow, not a generic form. Scanner views must include a bridge-pairing title, local-trust copy, a visible close affordance, a scan frame, and a recovery path to paste the payload when camera access is unavailable.
- Manual bridge pairing must validate and normalize the URL before a network request. Empty and malformed bridge URLs show local feedback immediately instead of waiting for a timeout.
- Manual pairing includes the installer-provided pairing code as a secure field; explain that older bridges may not require one without weakening the new secure default.
- Notification permission is contextual: explain it during pairing, never prompt on first launch, and provide a Settings recovery surface for enabling permission, opening iOS Settings, reconnecting missing relay access, and refreshing APNs registration.
- Empty states should state the missing requirement once and show one obvious action. Do not nest a CTA panel inside a status panel when a single full-width action button carries the affordance.
- Secondary tab headers identify the screen; unavailable-content panels explain the missing bridge and own the single recovery action. Do not put an `Add Bridge` button in both places.

## Color Semantics

These meanings are mandatory across the app and widgets:

- Success green `#16A34A` light / `#4ADE80` dark: confirmed healthy, successful completion, recovered state.
- Warning orange `#D97706` light / `#FBBF24` dark: degraded, failed, down, timeout, unreachable, or needs attention.
- Stale gray `#64748B` light / `#94A3B8` dark: cached, stale, inactive, unknown, locked, or unavailable.
- Destructive red `#DC2626` light / `#F87171` dark: destructive operations and rare security-relevant failure.
- Domain accents identify area, not status: action blue `#2563EB`, bridge cyan `#0891B2`, health green `#16A34A`, wake violet `#7C3AED`, command indigo `#4F46E5`, activity teal `#0D9488`, widget emerald `#059669`.

Use `AppDesign.Palette` in app code and keep `WidgetDesign.Palette` aligned for WidgetKit surfaces.
Widgets must use the same light/dark semantic pairs as the app. Widget WOL controls use wake violet, command controls use command indigo, and trusted-action status uses bridge cyan so action type and trust boundary remain visually distinct.

## Surfaces

- Use `AppSection` as a lightweight section label and spacing wrapper, not as a card. It should not create a boxed surface around other boxed content.
- Use `appSemanticPanel` for status, notices, summaries, and contextual panels.
- Use `appActionSurface` for tappable action tiles.
- Semantic color must be visible enough to communicate hierarchy, not just a hairline border. Panels use a restrained tinted fill plus a clear rail; action tiles use stronger tint because the whole tile is tappable.
- Action tile primary buttons should state the operation, such as `Wake Now` or `Run Now`, instead of generic labels when the result affects real machines.
- Action surfaces must identify execution authority before the user taps. Prefer one compact screen-level authority strip on Actions; use per-tile bridge chips when the screen-level context is absent, cached, locked, failed, or otherwise ambiguous.
- Destructive or trust-removal controls should be labeled with text (`Remove`, `Delete`) unless they are inside a platform swipe action or confirmation dialog that already supplies the label.
- Full action tiles with a visible `Trust`/`Trusted` widget button must not also show a second `Trusted` chip in the same tile. Overview tiles may show a compact trusted chip because they do not expose the trust control.
- Full action tiles should not repeat a ready state in the badge, body, and footer. If the footer says `Wake Now` or `Run Now`, the body should reserve state lines for last run, cached, disabled, or failure evidence.
- Settings panes should not restate the same bridge/widget/action state in the header, body, and row footer. One primary status marker plus one supporting explanation is enough.
- Use `appField` for form fields and command input surfaces.
- Do not add new one-off rounded rectangles in feature files unless the shared design layer cannot express the needed state.
- Do not put card-like panels inside card-like panels. If a section contains panels, the section itself should be unframed.

## Interaction

- Primary and tile-like buttons use `AppPressButtonStyle`.
- Selection taps use light selection haptics.
- Top-level tab changes also use light selection haptics and dismiss active text input. Moving between app areas should feel acknowledged without leaving a keyboard trapped on the next screen.
- Long bridge operations show progress immediately.
- Running/progress states use action or domain tint, not warning orange. Orange is reserved for degraded, down, failed, timed out, or blocked states.
- Success uses success haptic and a transient confirmation.
- Failure uses warning/error haptic and a recovery-oriented message. The transient failure message should name the immediate cause when known, such as timeout, unreachable bridge, or trust failure; longer output can remain in the result panel.
- Shared action buttons carry an accessibility state and must receive a `disabledReason` or `runningReason` when the surrounding UI could otherwise feel dead or ambiguous.
- Shared icon buttons carry the same accessibility state. Any icon-only control that can become disabled or show progress must receive a concrete `disabledReason` or `runningReason`.
- Disabled toolbar actions must have a visible nearby notice and an accessibility hint that names the blocking requirement, such as the missing field or in-progress save.
- Restrained tones are off by default, use ambient audio, respect the hardware silent switch, can be enabled in Settings, and must be rate-limited so repeated bridge events do not stack into noise. They must support feedback, not decorate the app.

## Required States

Every user-facing feature should define these states before shipping:

- Empty: what to do next.
- Loading: what is happening now.
- Success: what was confirmed and by which bridge.
- Failure: what failed and how to recover.
- Disabled: why the control cannot run.
- Cached/stale: when it was last confirmed.
- Cached app monitor rows must carry the cache qualifier near the evidence timestamp: use `Cached · checked 2m ago`, never bare `Confirmed 2m ago`.
- Destructive: explicit confirmation before removal.

## Widgets

- Small widget: overall cached homelab status.
- Medium health widget: service/device monitor summary.
- Medium action widget: explicitly trusted WOL and command tiles only.
- Lock Screen/accessory widget: compact cached critical status.
- Widget text must never imply live state. Use `Cached`, `Stale`, `Confirmed`, or last-run labels.
- Widget snapshots must include the last app-confirmed bridge reachability state. If the app has confirmed the active bridge is offline, widgets show `Offline`, use warning treatment, and trusted action rows become non-runnable recovery rows.
- Widget freshness copy must pair cache state with evidence timing: use wording like `Cached · checked 2m ago`, `Stale · checked 18m ago`, or `Cached · updated 4m ago` instead of bare `Confirmed 2m ago`.
- Any app or intent write to App Group widget state must request a WidgetKit timeline reload. Widget correctness depends on cache writes and timeline invalidation being treated as one operation.
- Individual monitor rows must also carry the cache qualifier when showing a timestamp: use `Cached · checked 2m ago`, never bare `Checked 2m ago` or `Confirmed 2m ago`.
- Lock Screen circular widgets must use evidence labels such as `Up`, `Stale`, or `None`; avoid vague real-time labels such as `OK`.
- Widget headlines should use confirmed/cached wording for healthy state, such as `Confirmed Up`, because widgets display App Group snapshots rather than live bridge state.
- Stale widget action rows should foreground `Cached` unless the last run failed; a stale success should not present as a fresh success.
- Stale trusted widget actions are recovery rows, not executable buttons. Show `Open App` and let the widget deep-link to Actions so the app can refresh bridge state before the user runs a real machine operation.
- Trusted widget actions must not disappear silently when their cached command or device details are incomplete. Show an unavailable row with an explicit recovery path, such as `Open App`, instead of hiding the trusted selection or firing a stale WOL/command action.
- Widget background taps must deep-link into the relevant tab: status to Home, health to Monitors, actions to Actions, and Lock Screen status to Home. Interactive widget buttons remain limited to explicitly trusted saved actions.
