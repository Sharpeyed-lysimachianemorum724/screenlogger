# Architecture

Screenlogger has three product targets:

- `Screenlogger.app` owns capture, permissions, preferences, the Library, and
  all database writes.
- `screenlog` is a bounded local client used by Terminal and assistants.
- `ScreenlogCore` contains capture, recognition, storage, search, retention,
  exclusions, permissions, and local IPC.

## Capture path

The capture engine selects a display, captures a still, reads application and
website context, performs on-device recognition, applies exclusions, and writes
one transaction through `Store`. Capture pauses on missing permission, excluded
activity, strict privacy uncertainty, inactivity when enabled, or low disk space.

## Storage

SQLite runs in WAL mode and is owned by the app process. Schema migrations are
transactional. Search uses FTS indexes. Managed stills and compacted videos are
referenced from database rows and verified by maintenance, backup, restore, and
deletion operations.

## Process boundary

The CLI connects to the running app through a local socket protocol with explicit
version negotiation, bounded payloads, stable error documents, and separate
read-only versus mutation capabilities. It never receives a database handle.

## Project generation

`project.yml` is the XcodeGen source of truth. `Screenlog.xcodeproj` remains
checked in so contributors can open the project immediately. CI regenerates it
and fails when the checked-in project differs.

## Platform frameworks

The implementation uses public Apple frameworks including SwiftUI, AppKit,
ScreenCaptureKit, Vision, AVFoundation, ApplicationServices, ServiceManagement,
OSLog, and Core Graphics, plus system SQLite and compression libraries.

## Updates

Sparkle provides the native update interface, atomic app replacement, and
relaunch behavior. It reads a signed appcast from the project's GitHub Pages
site and downloads DMGs from the project's GitHub Releases. The app requires
both a signed feed and pre-extraction Ed25519 archive verification. The private
key is held outside the repository in the maintainer Keychain and the protected
`release-signing` GitHub Environment. Keep Screenlogger Offline gates every
update check through the updater delegate. GitHub releases are separately
protected with Developer ID, Hardened Runtime, Apple notarization, and stapled
tickets on both the app and DMG.
