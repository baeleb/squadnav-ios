<div align="center">

# Silk Road

### Navigate together. Arrive together.

**The caravan navigation app for groups who move as one.**

*Coming soon to the App Store*

---

</div>

Silk Road keeps your entire group on the same road — real-time location sharing, synchronized turn-by-turn navigation, and instant alerts when anyone falls behind, stops, or goes off-route. Whether it's a road trip with friends, a convoy to a campsite, or a fleet moving in formation, Silk Road turns a scattered group into a caravan.

---

## Features

**Caravan Groups**
Create a group in seconds and share the invite code. Everyone who joins sees each other on a live map from the moment they connect.

**Synchronized Navigation**
The group leader sets a destination. Silk Road calculates the route and distributes it to every member simultaneously — everyone follows the same path, no one guesses.

**Live Caravan Monitoring**
Silk Road watches the caravan so you don't have to. Automatic alerts fire the moment anyone:
- Leaves the route
- Falls more than 2 km behind the group
- Stops moving for over a minute

**Group Chat**
A shared in-group chat keeps communication flowing. System alerts from Silk Road appear inline, so your group stays informed without switching apps.

**File Sharing**
Share documents, screenshots, and anything else with your group directly inside the app.

**CarPlay Support**
Full navigation UI on your car's display. Eyes on the road, hands on the wheel.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Platform | iOS 17+ · SwiftUI · Swift 5.9 |
| Navigation | MapKit · CoreLocation |
| CarPlay | CarPlay framework |
| Auth | Sign in with Apple · Google Sign-In |
| Backend | Firebase (Firestore · Auth · Storage · Cloud Messaging) |
| Build | XcodeGen · Xcode 16 |

---

## Requirements

- iOS 17.0 or later
- iPhone
- Xcode 16 (to build from source)

---

## Getting Started

1. Clone the repo and install [XcodeGen](https://github.com/yonaskolb/XcodeGen):
   ```bash
   brew install xcodegen
   ```

2. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```

3. Add your `GoogleService-Info.plist` to `SilkRoad/Resources/`.

4. Open `SilkRoad.xcodeproj`, set your development team, and run.

---

## Architecture

```
SilkRoad/
├── App/          # Entry point, root navigation
├── CarPlay/      # CarPlay scene delegate and map controller
├── Models/       # Data models (User, Group, Message, MemberLocation)
├── Services/     # Firebase, location, navigation, chat, caravan monitor
├── ViewModels/   # Observable state for each feature
├── Views/        # SwiftUI screens
├── Resources/    # Assets, entitlements, Info.plist
└── Utilities/    # Extensions, polyline encoding
```

---

## License

Proprietary. All rights reserved. See [LICENSE](LICENSE).

---

<div align="center">

Made with care for everyone who's ever lost half their group on the highway.

</div>
