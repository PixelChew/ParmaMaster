# Parma Master 1.3

Parma Master is a native, local-first iPhone app built with SwiftUI, SwiftData,
MapKit, Core Location, UserNotifications, PhotosUI, and UIKit camera/image
bridges. It targets iOS 26 and has no server, login, analytics, advertising,
CloudKit, or third-party runtime dependencies.

V1.3 Home Refresh adds Home stats, area tracking, and configurable re-run
suggestions on top of the Insights map and analytics introduced in V1.2.

## V1.3 Home Refresh

- **Home stats row** (shown when there are 2+ entries): Parmas logged and Areas
  visited. Areas are unique MapKit localities (suburb/town); the Areas card
  opens an Insights sheet listing each area with venue and log counts, search,
  and sort.
- **Re-run suggestion card** on Home for venues not logged for a configurable
  number of months (default 5). Tap to rate again, or dismiss to hide the card
  for a configurable window. The card yields to the location “Welcome to”
  suggestion when that is active, and stays hidden when nothing is eligible.
- **Per-venue opt-out** from Parma Details so a place can be excluded from
  re-run suggestions permanently.
- **Behaviour settings** for enabling suggestions, the stale-months threshold,
  and how long dismissed (or re-logged) suggestions stay hidden.
- **Insights “At a glance”** rebalanced to six cards, including Areas visited
  and Parmas logged this year, with ratings submitted as subtext under Parmas
  logged.

## Insights

The Insights tab sits between Parma Log and Settings in the native iOS 26 tab
bar. It provides:

- A selectable MapKit map with one marker per canonical Parma venue. Marker
  scores are shown on a comparable normalised `/10` scale, and map framing
  adapts to one or many saved locations.
- An “At a glance” grid for Parmas logged (with ratings-submitted subtext),
  average, highest, lowest, areas visited, and Parmas logged this year.
  Cross-entry comparisons use `currentTotal / currentMaximum`, never raw totals
  from different rating scales.
- Highest/lowest venue cards, perfect-score venues, independently normalised
  component averages, empty and low-data states, invalid-coordinate protection,
  accessible marker labels, and actions that open the existing Parma Details
  flow.

Insights values are calculated in memory from current canonical `ParmaEntry`
records. Historical `RatingRevision` snapshots contribute only to explicitly
historical metrics such as ratings submitted; they do not create duplicate
venues or map pins. Derived statistics are not persisted, so they stay correct
after edits, rerates, deletions, restores, and rating-scale changes.

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
- `LocationService` uses Core Location service sessions and standard
  `CLLocationManager` updates, keeps When In Use updates foreground-only, and
  enables silent background delivery only when reminders are enabled and Always
  authorization is granted. `PubDetectionService` then applies
  dwell, speed, distance, ambiguity, throttle,
  skip, and departure-rearm rules before suggesting a venue.
- `AppSettings` persists appearance, rating, photo, location, reminder, and
  backup preferences locally.
- `ParmaInsightsCalculator` is the UI-independent analytics layer. It derives
  normalised overall and component averages, tie-preserving extremes, perfect
  scores, rating-event totals, revisit counts, and calendar-year metrics.

## Major files and components

- `Sources/App`: app lifecycle, dependency graph, root tabs, sheets, and deep links.
- `Sources/Models`: settings, canonical entries, rating snapshots/history,
  backup payloads, and MapKit venue identity.
- `Sources/Services`: repository, photo ownership, Apple Maps search, backup,
  notifications, Core Location, and pub-detection policy.
- `Sources/Features/Onboarding`: welcome and manual Location, Camera & Photos,
  and Notifications permission controls with live approved-state ticks.
- `Sources/Features/Home`: recent entries, stats row, re-run suggestions, and
  new/returning venue suggestions.
- `Sources/Features/Logger`: venue picker, decimal/category scoring, attributed
  notes, camera/PhotosPicker/Files images, duplicate handling, edits, and re-rates.
- `Sources/Features/ParmaLog` and `Sources/Features/Search`: canonical-entry lists,
  normalised sorting, search across venue/address/note text, and delete flows.
- `Sources/Features/Details`: current score, components, photo, notes, history,
  edit, re-rate, and confirmed deletion.
- `Sources/Features/Insights`: the native map, statistic cards, venue insight
  cards, empty states, and existing-details routing for selected venues.
- `Sources/Features/Settings`: appearance, configurable scales/modes/categories,
  photo/location/reminder behaviour, Home re-run suggestion preferences,
  backup/restore, and factory reset.
- `Sources/Shared`: semantic brand styling, DM Serif display typography, score,
  card, sorting, empty-state, and aspect-fill image components.
- `Tests` and `UITests`: model/repository/image regressions, Insights calculator
  cases, tab placement, empty state, and primary UI flow.

## Verification completed

- Clean simulator build succeeds with Xcode 27.0 and an iOS 26 deployment target.
- The full simulator suite passes, including location-activity policy,
  migration and backup compatibility, rating validation, historical snapshots,
  proportional photo resizing, Insights normalisation/tie/perfect-score cases,
  component averages, and zero-entry behavior.
- The UI test passes onboarding, verifies the three manual permission controls,
  visits Home, Parma Log, Insights, Settings, Appearance, Behaviour, and Search,
  and proves Settings returns to its root after changing tabs on iPhone 17 Pro.
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
