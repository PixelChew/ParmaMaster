# Parma Master 1.3

A local-first iPhone app for rating, remembering, and discovering great parmas.

Parma Master helps you keep a personal log of venues, rate each parma by its components, add notes and photos, and find places worth returning to. It is built natively for iPhone with SwiftUI and Apple frameworks.

V1.3 Home Refresh adds Home stats, area tracking, and configurable re-run
suggestions on top of the Insights map and analytics introduced in V1.2. The
app introduces no server, login, analytics, ads, CloudKit, or third-party
runtime dependency.

## What you can do

- Record a venue from Apple Maps search or your current location.
- Rate a parma using configurable categories, scales, and numeric or star-based scoring.
- Save notes, photos, and the full history of rating changes.
- Browse your Parma Log, sort by rating or recency, and search venues, addresses, and notes.
- Get returning-venue and new-venue suggestions based on your configured location behaviour.
- Receive optional local reminders when you are near a venue worth logging.
- Edit entries, re-rate venues, manage duplicates, and delete entries with confirmation.
- Back up and restore entries, rating history, notes, settings, and photos through a user-selected Files folder.
- Personalise the appearance and scoring behaviour to match how you judge a great parma.

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

Insights is a normal tab between Parma Log and Settings. It includes:

- A selectable MapKit map with one marker per canonical venue. Markers show a
  comparable normalised `/10` score, and the camera frames one or many saved
  locations automatically.
- An “At a glance” grid for Parmas logged (with ratings-submitted subtext),
  average rating, highest rating, lowest rating, areas visited, and Parmas
  logged this year. Cross-entry comparisons use `currentTotal / currentMaximum`,
  never raw totals from different rating scales.
- Highest and lowest venue cards, perfect-score venues, and independently
  normalised Parma, Chips, and Salad averages.
- Empty and low-data states, invalid-coordinate protection, accessible marker
  labels, and actions that open the existing Parma Details flow.

Insights values are calculated in memory from current canonical `ParmaEntry`
records. Historical `RatingRevision` snapshots contribute only to explicitly
historical metrics such as ratings submitted; they do not create duplicate
venues or map pins. Derived statistics are not persisted, so they stay correct
after edits, rerates, deletions, restores, and rating-scale changes.

## Built with

- SwiftUI for the interface
- SwiftData for local persistence
- MapKit and Core Location for venue search, area resolution, and location-based suggestions
- UserNotifications for optional local reminders
- PhotosUI, UIKit, and the camera for image capture and selection

## Requirements

- macOS with Xcode 27.0 or later
- An iPhone or simulator running iOS 26 or later
- An Apple Developer account for physical-device signing; simulator builds do not require a paid program membership

## Run Parma Master

1. Open `ParmaMaster.xcodeproj` in Xcode.
2. Select the **ParmaMaster** project and app target.
3. For a physical iPhone, open **Signing & Capabilities** and select your own Apple Developer team. Simulator builds can usually run without a signing team.
4. Change the Bundle Identifier to a unique reverse-DNS identifier for your team, such as `com.example.ParmaMaster`. Do not reuse the maintainer’s bundle identifier.
5. Select an iPhone or iOS simulator as the run destination.
6. Build and run.

On a physical iPhone, Xcode may ask you to enable Developer Mode or trust the development certificate in **Settings > General > VPN & Device Management**.

## How the app is organised

- `Sources/App`: app lifecycle, dependency wiring, navigation, tabs, sheets, and deep links
- `Sources/Models`: venues, rating snapshots, settings, backup payloads, and venue identity
- `Sources/Services`: repository, photo storage, Apple Maps search, backups, notifications, location, venue-detection policy, area resolution, and re-run suggestions
- `Sources/Features/Onboarding`: guided permission setup
- `Sources/Features/Home`: recent entries, stats row, re-run suggestions, and venue suggestions
- `Sources/Features/Logger`: venue selection, scoring, notes, photos, duplicates, edits, and re-ratings
- `Sources/Features/ParmaLog`: the canonical venue list and sorting
- `Sources/Features/Search`: search across venues, addresses, and notes
- `Sources/Features/Details`: scores, components, photos, notes, history, editing, deletion, and per-venue re-run opt-out
- `Sources/Features/Insights`: the native map, statistic cards, venue insight cards, the areas list, empty states, and existing-details routing
- `Sources/Features/Settings`: appearance, scoring, behaviour, Home re-run suggestion preferences, permissions, backups, and reset controls
- `Sources/Shared`: brand styling, DM Serif typography, score displays, cards, empty states, and reusable UI components
- `Tests` and `UITests`: model, repository, backup, rating, migration, re-run suggestion, Insights-calculator, and primary navigation coverage

The data model keeps each venue as a canonical entry and stores rating revisions as immutable snapshots. This means changing the scoring configuration does not rewrite historical ratings.

## Verification

The current V1.3 branch builds against the iOS 26 deployment target and passes
the full iOS Simulator suite, including V1→V3 migration, backup compatibility,
re-run suggestion policy, Insights normalisation, tie handling, perfect-score
detection, component averages, areas aggregation, zero-entry behavior, and the
Insights tab empty-state UI flow.

## Permissions

Parma Master asks only when a feature needs access:

- Location access for current-location venue search and optional nearby reminders
- Notifications for optional local reminders
- Camera and photo library for adding venue photos
- Files access when you explicitly choose a backup folder


## License

Parma Master is available under the Apache License 2.0. See [LICENSE](LICENSE).

The bundled DM Serif Display font is distributed under its own license in [Resources/Fonts/OFL.txt](Resources/Fonts/OFL.txt).
