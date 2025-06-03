# Nice

A weather app that notifies you when it's exactly 69°F outside.

Nice monitors your local weather and sends push notifications when conditions reach that perfect 69º. Features an iOS app with real-time weather data, location services, and a web companion for browser notifications.

## Installation

**iOS App**
Open `App/Nice.xcodeproj` in Xcode and build for your device. Requires iOS 16+ and location permissions for weather monitoring.

**Server**
Navigate to the `Server` directory and run with Swift Package Manager:

```
swift run Nice
```

**Web App**
Serve the `Web` directory from any HTTP server. The service worker handles push notifications for supported browsers.

## Authors

Harlan Haskins ([harlan@harlanhaskins.com](mailto:harlan@harlanhaskins.com))