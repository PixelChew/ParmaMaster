# Parma Master 1.0

Parma Master is a native, local-first iPhone app built with SwiftUI, SwiftData,
MapKit, Core Location, UserNotifications, PhotosUI, and UIKit camera/image
bridges. It targets iOS 26 and has no server, login, analytics, advertising,
CloudKit, or third-party runtime dependencies.

## Open and run on an iPhone

1. Open `ParmaMaster.xcodeproj` in Xcode beta.
2. Select the **ParmaMaster** project, then the **ParmaMaster** app target.
3. Open **Signing & Capabilities**.
4. Leave **Automatically manage signing** enabled and choose your Personal Team.
5. Keep `com.fergohamish.ParmaMaster` if Xcode accepts it. If it is unavailable
   for your team, change it once to another stable reverse-DNS identifier.
6. Connect and unlock the iPhone, trust the Mac if prompted, and select the
   iPhone as the run destination.
7. Enable Developer Mode on the iPhone if iOS requests it, then press **Run**.
8. If iOS asks you to trust the development certificate, follow the prompt in
   **Settings > General > VPN & Device Management**, then run again.

No paid-program entitlement is required.

## Configured permissions and capabilities

- Location When In Use, requested explicitly from the onboarding Location button
  or when location behaviour is enabled.
- Always/background location, requested as an optional escalation after
  foreground access; `UIBackgroundModes` contains `location`. With Always access,
  background delivery uses the standard silent path and does not create a visible
  `CLBackgroundActivitySession` in the Dynamic Island.
- Local notification permission, requested from its onboarding button or when
  reminders are enabled.
- Camera and photo-library permissions, requested together from their onboarding
  button. Camera can also be requested when **Take Photo** is chosen.
- Security-scoped Files directory access for explicit backup and restore.
- No CloudKit, remote notifications, app groups, server, or analytics entitlement.

## Architecture

- `ParmaMasterApp` owns the SwiftData container and long-lived services.
- `ParmaEntry` is one canonical venue; `RatingRevision` stores immutable rating
  snapshots so scale changes never rewrite history.
- `EntryRepository` centralises deduplication, edits, re-ratings, and deletion.
- `PhotoStore` owns resized JPEGs under Application Support. Resizing preserves
  aspect ratio; all photo surfaces use native aspect-fill cropping.
- `BackupService` writes a versioned JSON backup containing entries, history,
  attributed notes, settings, and photo data to a user-selected Files folder.
- `LocationService` uses current Core Location service-session/live-update APIs,
  keeps When In Use updates foreground-only, and enables silent background
  delivery only after Always authorization. `PubDetectionService` then applies
  dwell, speed, distance, ambiguity, throttle,
  skip, and departure-rearm rules before suggesting a venue.
- `AppSettings` persists appearance, rating, photo, location, reminder, and
  backup preferences locally.

## Major files and components

- `Sources/App`: app lifecycle, dependency graph, root tabs, sheets, and deep links.
- `Sources/Models`: settings, canonical entries, rating snapshots/history,
  backup payloads, and MapKit venue identity.
- `Sources/Services`: repository, photo ownership, Apple Maps search, backup,
  notifications, Core Location, and pub-detection policy.
- `Sources/Features/Onboarding`: welcome and manual Location, Camera & Photos,
  and Notifications permission controls with live approved-state ticks.
- `Sources/Features/Home`: recent entries and new/returning venue suggestions.
- `Sources/Features/Logger`: venue picker, decimal/category scoring, attributed
  notes, camera/PhotosPicker/Files images, duplicate handling, edits, and re-rates.
- `Sources/Features/ParmaLog` and `Sources/Features/Search`: canonical-entry lists,
  normalised sorting, search across venue/address/note text, and delete flows.
- `Sources/Features/Details`: current score, components, photo, notes, history,
  edit, re-rate, and confirmed deletion.
- `Sources/Features/Settings`: appearance, configurable scales/modes/categories,
  photo/location/reminder behaviour, backup/restore, and factory reset.
- `Sources/Shared`: semantic brand styling, DM Serif display typography, score,
  card, sorting, empty-state, and aspect-fill image components.
- `Tests` and `UITests`: model/repository/image regressions and primary UI flow.

## Verification completed

- Clean simulator build succeeds with Xcode 27.0 and an iOS 26 deployment target.
- Ten unit tests pass, including over-maximum rating rejection, bounded input,
  global Stars propagation, repository validation, historical snapshots, and
  proportional photo resizing.
- The UI test passes onboarding, verifies the three manual permission controls,
  visits Home, Parma Log, Settings, Appearance, Behaviour, and Search, and proves
  Settings returns to its root after changing tabs on iPhone 17 Pro.
- The custom DM Serif Display font and the Figma hero asset are present in the
  built app bundle and were visually checked in the simulator.

The installed simulator runtime is iOS 27.0; an iOS 26 runtime was not available
on this Mac. Compilation still enforces the iOS 26 minimum deployment target.

## Physical-device checks

During user testing, verify each onboarding permission prompt and approved tick,
camera capture, When In Use to Always location escalation, silent background
location delivery after locking/leaving the app, local notification delivery,
Apple Maps results at real coordinates, Files bookmarks after relaunch, and
backup-folder availability after reboot. Background pub detection is
intentionally best-effort because iOS controls suspension and location delivery.

The AppIcon asset slot is present, but no bespoke app-icon artwork was supplied
in the Figma source, so custom icon art remains a visual follow-up.
