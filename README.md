# Parma Master

A local-first iPhone app for rating, remembering, and discovering great parmas.

Parma Master helps you keep a personal log of venues, rate each parma by its components, add notes and photos, and find places worth returning to. It is built natively for iPhone with SwiftUI and Apple frameworks.

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
- `Sources/Features/Settings`: appearance, scoring, behaviour, permissions, backups, and reset controls
- `Sources/Shared`: brand styling and reusable UI components

The data model keeps each venue as a canonical entry and stores rating revisions as immutable snapshots. This means changing the scoring configuration does not rewrite historical ratings.

## Permissions

Parma Master asks only when a feature needs access:

- Location access for current-location venue search and optional nearby reminders
- Notifications for optional local reminders
- Camera and photo library for adding venue photos
- Files access when you explicitly choose a backup folder


## Contributing

Issues, suggestions, and pull requests are welcome. If you are changing the scoring model, data model, backup format, or location behaviour, please explain the user-facing impact in your pull request.

## License

Parma Master is available under the Apache License 2.0. See [LICENSE](LICENSE).

The bundled DM Serif Display font is distributed under its own license in [Resources/Fonts/OFL.txt](Resources/Fonts/OFL.txt).
