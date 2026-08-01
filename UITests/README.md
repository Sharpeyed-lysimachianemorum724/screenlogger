# UI Tests

`ScreenlogAppUITests` protects Library, Timeline, Setup, Settings, assistant
routing, exclusions, keyboard navigation, and cross-window restoration.

Tests launch the real app with a fresh temporary data directory and isolated
preferences. Debug-only fixtures seed synthetic moments and declared permission
or assistant states without reading the user's Library, changing TCC, or calling
ScreenCaptureKit.

Run the routed suite:

```sh
Scripts/test-ui.sh
```

The runner refuses to start while another Screenlogger process is active.

`VisualAuditUITests` captures app-owned windows in deterministic light, dark,
default, and minimum-size states. Exported screenshots and result bundles belong
under `build` and are never committed.

Prefer visible labels and roles over coordinates or hierarchy depth. Add stable
accessibility identifiers only when a durable user-facing label cannot uniquely
identify a control.
