# Parma Master

A local-first iPhone app for rating, remembering, and discovering great parmas.

Parma Master helps you keep a personal log of venues, rate each parma by its components, add notes and photos, and find places worth returning to. It is built natively for iPhone with SwiftUI and Apple frameworks.

The app is local-first: your venue records, ratings, notes, photos, history,
backups, and insights remain on the device unless you explicitly choose a Files
location for a backup. There is no server, login, analytics, advertising,
CloudKit, or third-party runtime dependency.

## What you can do

- Record a venue from Apple Maps search or your current location.
- Rate a parma using configurable categories, scales, and numeric or star-based scoring.
- Save notes, photos, and the full history of rating changes.
- Browse your Parma Log, sort by rating or recency, and search venues, addresses, and notes.
- Explore a map of logged venues and understand your history with normalised ratings, revisit statistics, perfect scores, and component averages.
- Get returning-venue and new-venue suggestions based on your configured location behaviour.
- Receive optional local reminders when you are near a venue worth logging.
- Edit entries, re-rate venues, manage duplicates, and delete entries with confirmation.
- Back up and restore entries, rating history, notes, settings, and photos through a user-selected Files folder.
- Personalise the appearance and scoring behaviour to match how you judge a great parma.

## Map and insights

The Insights tab sits between Parma Log and Settings. It includes:

- A selectable MapKit map with one marker per canonical venue. Markers show a
  comparable normalised `/10` score, and the camera frames one or many saved
  locations automatically.
- Headline cards for Parmas logged, average rating, highest rating, and lowest
  rating. Cross-entry comparisons use `currentTotal / currentMaximum`, never
  raw totals from different rating scales.
- Highest and lowest venue cards, perfect-score venues, ratings submitted,
  most revisited places, Parmas logged this year, most recently logged, and
  independently normalised Parma, Chips, and Salad averages.
- Empty and low-data states, invalid-coordinate protection, accessible marker
  labels, and actions that open the existing Parma Details flow.

Insights values are calculated in memory from current canonical `ParmaEntry`
records. Historical `RatingRevision` snapshots contribute only to explicitly
historical metrics such as ratings submitted and most revisited; they do not
create duplicate venues or map pins. Derived statistics are not persisted, so
they stay correct after edits, rerates, deletions, restores, and rating-scale
changes.

## Built with

- SwiftUI for the interface
- SwiftData for local persistence
- MapKit and Core Location for venue search and location-based suggestions
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
- `Sources/Services`: repository, photo storage, Apple Maps search, backups, notifications, location, and venue-detection policy
- `Sources/Features/Onboarding`: guided permission setup
- `Sources/Features/Home`: recent entries and venue suggestions
- `Sources/Features/Logger`: venue selection, scoring, notes, photos, duplicates, edits, and re-ratings
- `Sources/Features/ParmaLog`: the canonical venue list and sorting
- `Sources/Features/Search`: search across venues, addresses, and notes
- `Sources/Features/Details`: scores, components, photos, notes, history, editing, and deletion
- `Sources/Features/Insights`: the native map, statistic cards, venue insight cards, empty states, and existing-details routing
- `Sources/Features/Settings`: appearance, scoring, behaviour, permissions, backups, and reset controls
- `Sources/Shared`: brand styling, DM Serif typography, score displays, cards, empty states, and reusable UI components
- `Tests` and `UITests`: model, repository, backup, rating, Insights-calculator, and primary navigation coverage

The data model keeps each venue as a canonical entry and stores rating revisions as immutable snapshots. This means changing the scoring configuration does not rewrite historical ratings.

## Verification

The app builds against the iOS 26 deployment target and the simulator suite
covers Insights normalisation, tie handling, perfect-score detection, component
averages, zero-entry behavior, and the Insights tab empty-state UI flow.

## Permissions

Parma Master asks only when a feature needs access:

- Location access for current-location venue search and optional nearby reminders
- Notifications for optional local reminders
- Camera and photo library for adding venue photos
- Files access when you explicitly choose a backup folder


## License

Parma Master is available under the Apache License 2.0. See [LICENSE](LICENSE).

The bundled DM Serif Display font is distributed under its own license in [Resources/Fonts/OFL.txt](Resources/Fonts/OFL.txt).
