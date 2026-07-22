# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

SquadNav is an iOS 17+ SwiftUI app (Swift 5.9, iPhone-only, follows system light/dark appearance) for group "caravan" navigation: a leader sets a shared destination, every member gets the same turn-by-turn route, live member locations and statuses are synced through Firestore, and each group has chat and file sharing. Backed by Firebase (Auth, Firestore, Storage) with CarPlay support. There are no tests or linters configured.

GitHub repo: `baeleb/squadnav-ios`, default branch `main`.

## Current state (as of 2026-07-21 — update or delete this section when stale)

Live Firebase project **`squadnav-dev`** is wired up: real `GoogleService-Info.plist` (gitignored, see below), Email/Google/Apple auth enabled, Firestore + Storage created (`us-central1`), and security rules deployed from this repo (`firestore.rules`, `storage.rules`, `firebase.json`, `.firebaserc`).

A `SquadNavTests` XCTest target now exists (standalone — compiles app sources directly, no app host, no live Firebase). Its 22 tests document 13 verified bugs found in a 2026-07 audit (12 intentionally failing tests = bug evidence, 7 passing controls; 2 crash-documenting tests skipped, 1 untestable skipped). Worst: `NavigationService.estimatedPolylineIndex` never resets (infinite off-route loop + possible range crash on shorter routes), member reroute dead-ends on nil `selectedDestination`, `RouteEncoder.decode` crashes on malformed polylines, monitor evaluates members at default (0,0)/stale locations as off-route, invalid `CLLocation.speed` (-1) yields false "stopped" and "-2 mph". None of these are fixed yet. Access-level test seams (private→internal, commented) exist in `NavigationService`, `CaravanMonitorService`, `NavigationViewModel`.

Outstanding follow-ups (none started):

- **Fix the verified audit bugs** (see test suite for the failing-test evidence).
- **Backfill `memberIds`**: groups created before the refactor have no `memberIds` field and will not appear in anyone's group list until a one-time script/Cloud Function copies each group's `members` subcollection doc IDs into the array. (Rules also default missing `memberIds` to `[]`, so pre-backfill groups are unreadable by members.)
- **Groups are readable by ANY signed-in user** (`allow get, list: if signedIn()` in `firestore.rules`) because `joinGroup` queries by `inviteCode` pre-membership. Fix = invites collection + Cloud Function join, then tighten reads to `uid in memberIds`. Also note: 6-char invite codes are guessable.
- **CarPlay navigation is not wired up** (see CarPlay section below).
- **Deferred**: App Check, `squadnav-prod` project, Android app registration, Java install for local rules emulator testing.

## Build commands

The Xcode project, `SquadNav/Resources/Info.plist`, **and** `SquadNav/Resources/SquadNav.entitlements` are all generated from `project.yml` by XcodeGen. Never edit `project.pbxproj`, `Info.plist`, or the entitlements file directly — change `project.yml` and regenerate. Adding/removing Swift files also requires regeneration:

```bash
xcodegen generate
```

Build for the simulator (resolves Firebase SPM packages on first run, which takes several minutes):

```bash
xcodebuild -project SquadNav.xcodeproj -scheme SquadNav \
  -destination 'generic/platform=iOS Simulator' build
```

Tests: `xcodebuild -project SquadNav.xcodeproj -scheme SquadNavTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test` (many failures are intentional bug documentation — see "Current state").

**`GoogleService-Info.plist` is gitignored** (real per-environment config). New devs: copy `SquadNav/Resources/GoogleService-Info.plist.example` → `SquadNav/Resources/GoogleService-Info.plist` with real values from the Firebase console (project `squadnav-dev`), update the `com.googleusercontent.apps.*` URL scheme in `project.yml` to the plist's `REVERSED_CLIENT_ID`, then `xcodegen generate`.

Security rules live in this repo (`firestore.rules`, `storage.rules`); deploy with `firebase deploy --only firestore:rules,storage` (requires `firebase login`, project alias in `.firebaserc`). Rules changes must go through the repo + deploy, not console edits.

The CarPlay entitlement (`com.apple.developer.carplay-maps`) requires Apple approval to run on real hardware; the CarPlay simulator works without it.

## Repository layout

```
project.yml                      # XcodeGen source of truth (targets, SPM deps, Info.plist, entitlements)
SquadNav/
  App/
    SquadNavApp.swift            # @main, FirebaseApp.configure() in AppDelegate, .onOpenURL, DeepLinkRouter
    ContentView.swift            # Auth gate: LaunchView → SignInView or HomeView
  Models/                        # Firestore Codable structs (see data model below)
    Group.swift  MemberLocation.swift  Message.swift  SharedFile.swift  User.swift (AppUser)
    NavigationState.swift        # Local-only turn-by-turn state (phase, steps, ETA) — not persisted
  Services/                      # All Firebase/CoreLocation/MapKit access; own the @Published live data
    AuthService.swift            # AuthServiceProtocol, FirebaseAuthService, UserRepository,
                                 #   and the FirestoreService singleton (defined at the bottom of this file)
    GroupService.swift           # Group CRUD, invite codes, membership, group/member listeners
    ChatService.swift            # Messages listener (last 200), text/system/alert senders
    FileStorageService.swift     # Firebase Storage upload/delete + files listener
    LocationService.swift        # CLLocationManager wrapper, throttled Firestore upload gate
    NavigationService.swift      # MKDirections routing, off-route detection, step advancement
    CaravanMonitorService.swift  # Leader-only member health checks (off-route/behind/stopped)
  ViewModels/                    # @MainActor ObservableObject; forward services' objectWillChange
    AuthViewModel.swift  GroupViewModel.swift  NavigationViewModel.swift
    ChatViewModel.swift  FilesViewModel.swift
  Views/
    Auth/      SignInView, SignUpView
    Home/      HomeView (group list, deep-link handling), CreateGroupView, JoinGroupView
    Group/     GroupDetailView (tab container: Map/Chat/Files/Members + navigation lifecycle hooks),
               ChatView, FilesView, MemberStatusView, MessageBubbleView
    Navigation/ DestinationSearchView, NavigationMapView, ManeuverBannerView
  CarPlay/
    CarPlaySceneDelegate.swift   # CPMapTemplate root, map buttons; registered in project.yml scene manifest
    CarPlayMapController.swift   # MKMapView for the CPWindow
    CarPlayNavigationManager.swift # NavigationState → CPNavigationSession bridge (NOT yet driven by the app)
  Utilities/
    RouteEncoder.swift           # Google encoded-polyline encode/decode
    Extensions.swift             # AppTheme (colors/gradients), Color(hex:), glassCard, button styles, timeAgoDisplay
  Resources/                     # Generated Info.plist, dummy GoogleService-Info.plist, assets, entitlements
```

## Architecture

Layers: `Views` (SwiftUI) → `ViewModels` (`@MainActor ObservableObject`) → `Services` (Firebase/CoreLocation/MapKit) → `Models` (Firestore `Codable` structs).

**Reactivity convention (load-bearing):** Services own the `@Published` live data (e.g. `GroupService.members`, `ChatService.messages`); views read it *through* view models (`groupViewModel.groupService.members`). Since nested `ObservableObject` changes don't propagate in SwiftUI, every view model forwards its services' `objectWillChange` via Combine in `init` (see `GroupViewModel.init` for the pattern). Any new view model holding a service must do the same, or its views silently stop updating.

### Firestore data model

`FirestoreService.shared.db` is the singleton handle (defined at the bottom of `AuthService.swift`, not in its own file).

- `users/{uid}` — `AppUser` (displayName, email, photoURL, createdAt). Created by `UserRepository` at email sign-up, or on first Google/Apple sign-in.
- `groups/{groupId}` — `Group`: `name`, `inviteCode` (6 chars from a charset excluding O/0/I/1), `createdBy` (leader's uid), `destinationLatitude/Longitude/Name`, `routePolyline` (encoded polyline string), `isNavigating` (Bool), `createdAt`, `memberIds: [String]`.
  - `members/{uid}` — `MemberLocation`: displayName, `role` (`"leader"`/`"driver"`), latitude, longitude, heading, speed, `lastUpdated` (`@ServerTimestamp Date?`), `status` (`DriverStatus` raw values `on_route`/`off_route`/`behind`/`stopped`/`idle`), `currentStepIndex`.
  - `messages` — `Message`: senderId (`"system"` for app-generated), senderName, text, `type` (`text`/`system`/`alert`), timestamp. Listener orders by timestamp, `limit(toLast: 200)`.
  - `files` — `SharedFile` metadata; the binary lives in Firebase Storage at `groups/{groupId}/files/{fileId}_{fileName}`.

**Membership invariant:** the `members/{uid}` subcollection doc and the `memberIds` array on the group doc must stay in sync. `createGroup` writes `memberIds: [creator]` up front; `joinGroup` pairs the member-doc write with `FieldValue.arrayUnion`; `leaveGroup` pairs the delete with `arrayRemove` (and deletes the whole group when the last member leaves). These paired writes are not currently atomic — a batched write would be an improvement. `listenToUserGroups()` is a single `whereField("memberIds", arrayContains: uid)` listener; sorting is client-side by `createdAt` descending because `arrayContains` + server-side `order(by:)` would require a composite index.

**Decoding pitfall:** writes that use `FieldValue.serverTimestamp()` must decode through `@ServerTimestamp var x: Date?` — a non-optional `Date` fails to decode in latency-compensated local snapshots and the document silently drops out of `compactMap`-based listeners (this bit `MemberLocation.lastUpdated` once already).

### Auth

`FirebaseAuthService` (behind `AuthServiceProtocol`) supports email/password, Google Sign-In, and Sign in with Apple (nonce + SHA256 via CryptoKit). `AuthViewModel` owns it and gates the root UI in `ContentView`; it waits 500 ms at launch for Firebase to restore the session before deciding signed-in/out. Services do **not** receive the user by injection — they all read `Auth.auth().currentUser` directly (known limitation).

### Leader/member navigation flow (the core feature)

Spread across `NavigationViewModel`, `NavigationService`, `GroupService`, `CaravanMonitorService`, and `GroupDetailView`.

- **Roles:** the group creator (`group.createdBy`) is the leader; `isLeader` is computed in both `GroupViewModel` and `NavigationViewModel` by comparing against `Auth.auth().currentUser?.uid`.
- **Leader starts:** `DestinationSearchView` → `NavigationViewModel.setDestinationAndCalculateRoute` calculates an `MKRoute` via `MKDirections`, encodes its polyline (`RouteEncoder`, Google encoded-polyline format) and writes destination + polyline to the group doc (`GroupService.setDestination`). `startNavigation()` then starts local tracking, sets the group-wide `isNavigating = true`, posts a system chat message, and starts the 5-second caravan-monitor timer.
- **Members react:** `GroupDetailView.onChange` of `activeGroup?.isNavigating` (guarded with `!isLeader`): on `true` → `joinNavigation()` decodes the shared polyline via `setRouteFromPolyline` (which still runs `MKDirections` from the polyline's first coordinate to get step data) or falls back to calculating its own route, starts tracking, and presents the navigation UI; on `false` → `endNavigationLocally()` tears down. `stopNavigation()` always tears down locally but only writes `isNavigating = false` when `isLeader` — a member stopping must not end navigation for everyone.
- **Turn-by-turn engine (`NavigationService`):** consumes every location tick. Off-route = >75 m from the route polyline for ≥5 s → phase `.rerouting`, fires `onOffRoute` (chat alert + local reroute in `NavigationViewModel`). Steps advance within 50 m of the current step's end; arrival fires `onArrived` (chat message). Distance-to-polyline checks are windowed around `estimatedPolylineIndex` for performance.
- **Caravan monitor (leader-only):** the 5 s timer in `NavigationViewModel.startCaravanMonitoring` calls `CaravanMonitorService.evaluateMembers`, which skips the current user and classifies each *other* member: off-route >100 m from route, behind >2 km from the leader or >3 steps behind, stopped <1.4 m/s for >60 s. On a status change to a problem state it posts a chat alert and writes via `GroupService.updateMemberStatus(groupId:memberId:status:)`. Do not run the monitor on members — it duplicates chat alerts. Note the distinction: `updateMemberStatus` writes another member's status field only; `updateMemberLocation` always writes the *current user's* member doc.
- **Location pipeline (`LocationService`):** `kCLLocationAccuracyBestForNavigation`, 5 m distance filter, background updates enabled. Every tick goes to `onLocationUpdate` (→ navigation engine); uploads to Firestore are throttled through `onShouldUploadToFirestore` (≥3 s elapsed or ≥10 m moved).

### URL handling & deep links

The app uses the SwiftUI scene lifecycle, so `AppDelegate.application(_:open:)` is never called — all incoming URLs go through `.onOpenURL` in `SquadNavApp`: Google Sign-In callbacks are offered to `GIDSignIn.handle` first, then `squadnav://join/CODE` invite links go to the `DeepLinkRouter` environment object (validates a 6-char code into `pendingInviteCode`). `HomeView` observes `pendingInviteCode`, presents `JoinGroupView` with the code prefilled, and clears it on dismiss. Invite QR codes (generated in `GroupService.generateQRCode`) encode `squadnav://join/CODE` and are meant to be scanned with the system camera — the in-app scanner was removed.

### CarPlay

`CarPlaySceneDelegate` is registered in the scene manifest (`project.yml`). Hard-won constraints:

- `CPMapTemplate` may only be the **root** template — pushing it onto another template raises an exception.
- Setting leading/trailing navigation-bar buttons on `CPMapTemplate` has caused internal crashes (see comment in `CarPlaySceneDelegate.setupMapButtons`); `mapButtons` (zoom/recenter) are safe.

**Status: scaffolded, not functional navigation.** CarPlay currently shows only a map with zoom/recenter buttons. `CarPlayNavigationManager` (NavigationState → `CPNavigationSession`/`CPManeuver` bridge, trip creation/preview) compiles but nothing calls `updateManeuvers`, `createTrip`, or `presentTripPreview` — the CarPlay scene has no connection to the phone app's `NavigationService` (they are separate scenes with no shared state path yet). Wiring this (likely via a shared singleton or notification from `NavigationViewModel`) is the main remaining CarPlay task.

### Chat & files

`ChatService` sends user texts plus system messages/alerts (sender id `"system"`); the caravan monitor and navigation callbacks are the main system senders. `FileStorageService` uploads via `putData` with progress observation bridged to async/await, then writes a `SharedFile` metadata doc; upload state resets in a `defer` so failures don't leave `isUploading` stuck. Both are owned by `GroupViewModel` and started/stopped per group in `selectGroup`/`deselectGroup` (called from `GroupDetailView.onAppear`/`onDisappear`).

## Conventions & gotchas

- All services and view models are `@MainActor`. Firestore listener callbacks assign `@Published` state directly (snapshot listeners deliver on the main queue).
- Firestore listeners use `compactMap { try? $0.data(as:) }` — decode failures are silent. If documents "disappear", suspect a decoding mismatch (see the `@ServerTimestamp` pitfall above).
- Model fields added after launch must be optional on the struct (`memberIds: [String]?` is the precedent) so pre-existing docs still decode.
- `AuthService.swift` is a grab-bag: protocol, Firebase implementation, `UserRepository`, `FirestoreService` singleton, and a mid-file `import FirebaseFirestore`. Expect to find auth-adjacent things there.
- UI styling goes through `AppTheme` and helpers in `Utilities/Extensions.swift` (`Color(hex:)`, `.glassCard()`, button styles, `Date.timeAgoDisplay`).
- FirebaseMessaging is linked in `project.yml` and `remote-notification` is in `UIBackgroundModes`, but there is no messaging/push code yet.

## Known limitations

- Groups created before the `memberIds` refactor need a backfill before they appear in the group list (see "Current state" above).
- Group docs are readable by any signed-in user (invite-code lookup constraint; see "Current state").
- `joinGroup`/`leaveGroup` paired writes (member doc + `memberIds`) are not atomic batches.
- Auth flows assume `Auth.auth().currentUser` for identity throughout services rather than injecting the user.
- CarPlay navigation is unwired (see CarPlay section).
- No linters; 13 audit-verified bugs documented by the failing test suite remain unfixed.
