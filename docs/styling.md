# Interface Style

Screenlogger should feel like a focused macOS utility. Native behavior,
legibility, and predictable navigation take priority over decoration.

## Principles

- Use standard AppKit and SwiftUI controls when they express the behavior.
- Make the current state and next safe action obvious.
- Keep technical detail behind disclosure unless it is needed for recovery.
- Use one visual treatment for each semantic role across Library, Timeline,
  Setup, and Settings.
- Prefer calm hierarchy, whitespace, and alignment over nested cards.
- Never use color, hover, animation, or an icon as the only explanation.

## Layout

- Use consistent pane margins and section spacing from `SLDesign`.
- Align row titles, descriptions, state, and trailing controls.
- Let important text wrap. Do not truncate permission, privacy, or error copy.
- Test 820 x 540, 1,060 x 700, and 1,440 x 900 window sizes.
- Use adaptive layouts before introducing horizontal scrolling.

## Typography and color

- Use semantic text styles and system materials.
- Use the Screenlogger palette through shared design tokens.
- Reserve red for destructive actions or failures.
- Pair warning and success colors with plain text and an SF Symbol.
- Keep supporting copy at secondary contrast, not tertiary contrast.

## Navigation

- Library, Timeline, and Settings are durable destinations.
- Back returns to the exact prior Library state after opening a result.
- Search, filters, selection, preview state, and restoration anchors survive a
  Library to Timeline to Library round trip.
- Settings search routes to an exact pane and control, then hands off focus.
- Every primary action must be reachable with keyboard and VoiceOver.

## Controls and states

- Use one primary action per decision point.
- Label icon-only controls when space permits and always provide accessibility
  labels and help.
- Loading preserves useful content where possible.
- Empty states distinguish first use, no results, active filters, and unavailable
  data.
- Errors state the impact and offer a local recovery action.
- Disabled controls include a visible explanation of their prerequisite.
- Destructive actions name their scope and require review.

## Permissions

Screen Recording and Accessibility are one setup journey with separate verified
states. Ask only after an explicit user action. Later actions open the relevant
System Settings pane. Never infer permission from opening Settings, and never
poll with a content-capture API.

When the app is missing from a privacy list, show a stationary draggable app tile
beneath a literal source and destination guide. Also provide Show in Finder and
Add-button instructions because System Settings behavior varies by macOS release.

## Assistant integrations

Each assistant row has one identity, one state, one explanation, and one primary
action. Use the assistant's real mark only for identity. Use SF Symbols for
actions and state. Say Connection verified only when Screenlogger has verified
its own command path. Do not claim that Screenlogger tested the assistant host.

## Motion

Use short motion only to explain a state or spatial transition. Respect Reduce
Motion. Avoid bounce, looping decoration, animated gradients, and moving action
targets.

## Review checklist

- The first safe action is obvious.
- State and recovery copy are truthful.
- Keyboard and VoiceOver follow the pointer flow.
- Light, dark, Increased Contrast, Reduce Motion, and larger text remain usable.
- Reusable spacing, color, typography, and control patterns live in shared code.
- Screenshots at every supported size show no clipping, overlap, dead space, or
  competing primary actions.
