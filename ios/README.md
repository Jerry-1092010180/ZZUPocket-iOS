# ZZUPocket iOS (iOS 17+)

Native SwiftUI client, separate from the Android app. Current scope: CAS login (including SMS MFA), undergraduate semester schedule, graduate semester schedule (separate school web CAS login), campus card balance and recent 30-day transactions, electricity lookup by full room ID or online room picker, basic focus timer with local records, and school library website. Custom timetable, room occupancy, statistics, notifications and widgets are **not** implemented. No account data is embedded in the build. Graduate sign-in uses a WKWebView; the web session may expire and require signing in again. Focus timer runs only while the app process is alive (no background service yet).

## Electricity trends

Lighting and air-conditioning meters have separate remaining-electricity charts with hour, day, week and month ranges. Tap or drag to inspect a sample. Successful foreground and system-scheduled background refreshes accumulate local history for 90 days; the school lookup does not supply historical backfill. Missing intervals remain gaps and balance increases are marked as possible recharges. Recorded decreases describe sampled intervals, not a complete electricity bill. History is isolated by account, meter kind and full room ID. It is stored only on this device; logging out hides it, and signing back into the same account restores it.

## Background refresh

Background App Refresh is enabled by default after login and can be disabled under 我的 → 后台刷新. A BGAppRefreshTask request asks for execution no earlier than 15 minutes later; iOS chooses the actual time and may defer or skip it. Requests are chained after each background attempt and renewed when returning to or leaving the app. Existing pending requests are preserved rather than postponed on every launch. System restrictions and Low Power Mode are shown in settings, along with the most recent attempt, data update and result.

Background queries use the existing Keychain token, update the same meter histories, and cancel cooperatively when the system expires the task. Expired school credentials require signing in again; no password is stored or automatic SMS login attempted. Background refresh cannot guarantee uninterrupted monitoring and does not backfill missed school readings. Enable Background App Refresh in iOS Settings, disable Low Power Mode when testing, and avoid force-quitting the app when expecting background updates.

To check refresh outcomes on macOS without school credentials:

```sh
swiftc -parse-as-library ios/ZZUPocket/ElectricityHistory.swift ios/ZZUPocket/PocketModel.swift ios/Tests/PocketModelChecks.swift -o /tmp/zzupocket-checks
/tmp/zzupocket-checks
```

A device build must contain `UIBackgroundModes = [fetch]` and the `com.zzupocket.campus.refresh` identifier in `BGTaskSchedulerPermittedIdentifiers`. A simulated task launch verifies handler wiring, not the system's automatic scheduling frequency. Inspect the in-app timestamps after leaving the app in the background to confirm natural execution.

## Build

For maintainers publishing a Windows sideload package: enable Actions in your fork, then run **Publish Windows sideload package** with a new version such as `ios-v0.1.0`. It builds an unsigned IPA, checks launch metadata and the absence of personal provisioning data, and creates a GitHub Release containing the IPA, checksum and Windows instructions. Reusing an existing release tag fails instead of overwriting downloads. This workflow requires repository contents write permission; it does not sign apps or upload to TestFlight. The new release workflow must be run and checked on GitHub before advertising a download as available.

On macOS with Xcode 16.4 and XcodeGen:

```sh
xcodegen generate --spec ios/project.yml --project ios
xcodebuild -project ios/ZZUPocket.xcodeproj -scheme ZZUPocket -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /tmp/ZZUPocketBuild CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
mkdir -p /tmp/ZZUPocketPayload/Payload
cp -R /tmp/ZZUPocketBuild/Build/Products/Release-iphoneos/ZZUPocket.app /tmp/ZZUPocketPayload/Payload/
(cd /tmp/ZZUPocketPayload && zip -r ZZUPocket-iOS-unsigned.ipa Payload)
```

Or run **Actions > iOS unsigned IPA > Run workflow** and download the `ZZUPocket-iOS-unsigned` artifact. No signing certificate, Apple account, GitHub secret or provisioning profile is needed to **build**. The workflow does not publish a Release; artifacts are available from the workflow run. GitHub Actions must be enabled in the repository.

The IPA is **unsigned**: standard iOS installation will reject it. TrollStore installation only works on device/iOS versions actually supported by TrollStore; an iOS 17 deployment target does **not** imply that TrollStore supports every iOS 17.x version. Verify your specific device and version before installing. A personal development build has been tested on an iPhone 16; release IPA sideloading requires separate verification.

Authentication tokens live in Keychain and are removed on logout. The password is not stored. Room ID is stored in UserDefaults. School API contracts may change; verify login and data requests on device. This is an unofficial client.

## iPhone layout checks

The generated app declares `UILaunchScreen` in `project.yml` so iPhone can use its native display size. Keep this declaration when changing the project specification; checking only the SwiftUI view layout will not catch missing launch metadata.

After building, check the packaged app's `Info.plist` for a `UILaunchScreen` dictionary. On a physical iPhone, verify that:

- Content fills the display within the system safe areas, without large compatibility-mode black bars.
- All five tabs (课表, 研究生, 校园, 专注, 我的) are directly accessible, with no system More tab. Library access is under 我的 → 图书馆座位, with a working back button.
- Long course titles, locations and teacher names wrap, including with larger accessibility text sizes.
- The final course card can scroll clear of the floating tab bar, in light and dark appearance.

For personal signing, keep any local specification in `ios/project.personal.yml` (ignored by Git), generate the project from that file, and select your own development team. Do not commit personal signing settings or generated Xcode files.

## Timetable cache and network redirects

Successful undergraduate timetable syncs save the selected semester, lessons and sync timestamp locally. Restarting the app restores this cache for the same login session. Failed refreshes retain previously saved lessons; the UI shows the last successful sync time. Logout removes the cache, and a different login token does not inherit it. A successful online sync is required before offline viewing; cached lessons do not guarantee current room or time changes.

The client handles HTTP redirects before JSON parsing. It follows at most four distinct URLs and forwards authorization only to HTTPS API paths on `jwxt.zzu.edu.cn` with the default port. CAS redirects request reauthentication; other destinations are reported without forwarding credentials. Error destinations exclude query strings and fragments. Certificate validation remains enabled. Campus-only connectivity problems cannot be fixed by cached data; a separately configured private network route can provide access, but this app does not embed a VPN client.

## Optional Raspberry Pi history snapshot

The history screen supports an optional local `ios/ZZUPocket/PrivateHistorySnapshot.json` resource. This repository deliberately contains no personal readings. A private build can supply JSON with `generatedAt` (Unix seconds) and `meters`, each containing `kind` (`lighting` or `ac`) and `samples` (`timestamp`, `quantity`). A newer bundled snapshot is cached on device. This is a packaged offline snapshot, not continuous network synchronization. Do not commit this resource or personal signing settings.

## Local regression checks

Run each executable independently because the model checks supply their own isolated fake API and in-memory storage:

```sh
swiftc -parse-as-library ios/ZZUPocket/ElectricityHistory.swift ios/ZZUPocket/PocketModel.swift ios/Tests/PocketModelChecks.swift -o /tmp/zzupocket-model-checks
/tmp/zzupocket-model-checks
swiftc -parse-as-library ios/ZZUPocket/ElectricityHistory.swift ios/ZZUPocket/PocketModel.swift ios/Tests/ScheduleCacheChecks.swift -o /tmp/zzupocket-schedule-checks
/tmp/zzupocket-schedule-checks
swiftc -parse-as-library ios/ZZUPocket/Network.swift ios/Tests/AcademicRedirectChecks.swift -o /tmp/zzupocket-redirect-checks
/tmp/zzupocket-redirect-checks
```
