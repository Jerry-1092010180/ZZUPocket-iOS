# ZZUPocket iOS (iOS 17+)

Native SwiftUI client, separate from the Android app. Current scope: CAS login (including SMS MFA), undergraduate semester schedule, graduate semester schedule (separate school web CAS login), campus card balance and recent 30-day transactions, electricity lookup by full room ID or online room picker, basic focus timer with local records, and school library website. Electricity history, custom timetable, room occupancy, statistics, offline schedule cache, notifications and widgets are **not** implemented. No account data is embedded in the build. Graduate sign-in uses a WKWebView; the web session may expire and require signing in again. Focus timer runs only while the app process is alive (no background service yet).

## Build

On macOS with Xcode 16.4 and XcodeGen:

```sh
xcodegen generate --spec ios/project.yml --project ios
xcodebuild -project ios/ZZUPocket.xcodeproj -scheme ZZUPocket -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /tmp/ZZUPocketBuild CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
mkdir -p /tmp/ZZUPocketPayload/Payload
cp -R /tmp/ZZUPocketBuild/Build/Products/Release-iphoneos/ZZUPocket.app /tmp/ZZUPocketPayload/Payload/
(cd /tmp/ZZUPocketPayload && zip -r ZZUPocket-iOS-unsigned.ipa Payload)
```

Or run **Actions > iOS unsigned IPA > Run workflow** and download the `ZZUPocket-iOS-unsigned` artifact. No signing certificate, Apple account, GitHub secret or provisioning profile is needed to **build**. The workflow does not publish a Release; artifacts are available from the workflow run. GitHub Actions must be enabled in the repository.

The IPA is **unsigned**: standard iOS installation will reject it. TrollStore installation only works on device/iOS versions actually supported by TrollStore; an iOS 17 deployment target does **not** imply that TrollStore supports every iOS 17.x version. Verify your specific device and version before installing. This build has not been tested on a physical iPhone.

Authentication tokens live in Keychain and are removed on logout. The password is not stored. Room ID is stored in UserDefaults. School API contracts may change; verify login and data requests on device. This is an unofficial client.

## iPhone layout checks

The generated app declares `UILaunchScreen` in `project.yml` so iPhone can use its native display size. Keep this declaration when changing the project specification; checking only the SwiftUI view layout will not catch missing launch metadata.

After building, check the packaged app's `Info.plist` for a `UILaunchScreen` dictionary. On a physical iPhone, verify that:

- Content fills the display within the system safe areas, without large compatibility-mode black bars.
- All five tabs (课表, 研究生, 校园, 专注, 我的) are directly accessible, with no system More tab. Library access is under 我的 → 图书馆座位, with a working back button.
- Long course titles, locations and teacher names wrap, including with larger accessibility text sizes.
- The final course card can scroll clear of the floating tab bar, in light and dark appearance.

For personal signing, keep any local specification in `ios/project.personal.yml` (ignored by Git), generate the project from that file, and select your own development team. Do not commit personal signing settings or generated Xcode files.

