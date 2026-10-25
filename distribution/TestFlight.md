# Gorilla Leading TestFlight

## Build 5 Preparation (2026-10-25)

Version `1.0 (5)` includes the current working-tree changes: trip replay and altitude charts, driving-event/G-force improvements, AC telemetry, updated appearance controls, the revised first-run tour, and the published support website. This is a TestFlight update, not a public App Store release.

The app and widget share build number 5. The explicit Info.plist export-compliance flag matches the existing build setting (`ITSAppUsesNonExemptEncryption = NO`). This applies to the current AMap-free app, not historical build 2. Re-run `Tests/NoAMapChecks.rb` against the actual archive before upload.

The archive passed `Tests/NoAMapChecks.rb` on the actual app bundle, including the export-compliance flag. The app and widget both report build 5. Upload completed successfully on 2026-10-26; Apple accepted the package for processing (`Upload succeeded`, `EXPORT SUCCEEDED`). The first attempt failed because Xcode had no signed-in Apple Account; it succeeded after the owner signed in.

After the owner restored the separate App Store Connect browser login on 2026-10-26, build 5 was verified as processed without a missing-compliance warning. Its Traditional Chinese What to Test notes were saved from `distribution/TestFlight-1.0-5-notes.txt`. The build detail page confirms assignment to `Self Testing` (Internal, 3 testers) and `Friends Testing` (External, 2 testers). The external Submit for Review flow was completed with automatic tester notification enabled; the Friends Testing Builds page then visibly showed `1.0 (5)` as `Testing`, not Waiting for Review. No production App Store release was submitted, no testers were added, and public-link settings were not changed. Xcode and App Store Connect browser login sessions are independent.

A local distribution export also succeeded: `output/TestFlight-1.0-5/GorillaTranslate.ipa`. Status proof was captured at `/private/tmp/gorilla-testflight-5-external.png` (temporary local file).

## Manual Xcode Upload

1. Open `GorillaTranslation.xcodeproj` in Xcode and select the `GorillaTranslate` scheme. Sign in under Xcode > Settings > Apple Accounts; an App Store Connect browser login alone is insufficient for Xcode upload.
2. In Signing & Capabilities, retain automatic signing and team `JVL487RN2F`. Confirm the app and widget use the same version/build numbers. Choose a new build number greater than the latest uploaded number (after build 5, use 6 or higher).
3. Select `Any iOS Device (arm64)` or the generic iOS device destination, not a simulator, then choose Product > Archive.
4. In Window > Organizer > Archives, select the completed archive and choose Distribute App > App Store Connect / TestFlight & App Store > Upload. Do not choose TestFlight Internal Only if the build must also reach external testers.
5. Complete signing/validation and upload. Wait for Apple processing; resolve any warnings based on their actual cause.
6. In App Store Connect > Gorilla Leading > TestFlight, open the new build, enter What to Test, and assign the existing `Self Testing` and `Friends Testing` groups.
7. Submit for external Beta App Review if requested. Internal availability, external review submission, approval, and notification are separate states. Do not claim external availability until Apple permits it.

If export compliance is requested, assess the specific build including its bundled SDKs. The flag is not a general-purpose way to bypass encryption questions. Keep the old build 2 declaration unchanged unless its SDK encryption classification is resolved.

## Build 4 Preparation

Build `1.0 (4)` was archived and uploaded successfully on 2026-10-13. The app and widget both carry build number 4, and the archive passed the no-AMap checks. It removes the Minecraft map-style picker from Settings and defaults new installations to Canvas Symbols + Dither, while preserving explicitly saved rendering preferences. It includes the local Shenzhen, prediction, parking-flow, paused-camera preview, stationary Live Activity alignment and colorful transparent-glass capture-button changes made after build 3.

The `Friends Testing` external group has one explicitly requested tester. Build 3 was not submitted for external Beta App Review; the developer requested build 4 instead. Do not store review contact phone numbers in this repository.

Apple completed processing build 4 without an export-compliance warning. It was assigned to `Self Testing` and `Friends Testing`. Build 4 was submitted for external Beta App Review using the developer-provided contact details, with no app login required and automatic tester notification enabled. The external group visibly shows `1.0 (4)` as Waiting for Review. This is not approval or confirmation that an external invitation has already been sent. Internal testers can access the assigned build without external Beta App Review approval.

## Current Build: No AMap

At the developer's request, build `1.0 (3)` removes all AMap SDKs, test pages, initialization and CocoaPods integration. Production maps and routing remain Apple MapKit. `Tests/NoAMapChecks.rb` verifies source references, bundled resources, linked frameworks and retained SDK identifiers in the archive.

The remaining cryptographic functionality uses Apple's OS APIs (HTTPS and CryptoKit SHA256 backup-integrity hashes). `ITSAppUsesNonExemptEncryption` is set to `NO` for this replacement build. Do not apply this conclusion retrospectively to build 2, which contains AMap.

The build 2 findings below are historical, not a blocker for the AMap-free replacement.

Build 3 was accepted and processed by Apple on 2026-10-13 with no missing-export-compliance warning, and assigned to the existing `Self Testing` internal group. Its release notes were saved. No external beta review submission, public link or friend invitations were created. The subsequent Shenzhen / prediction / parking-flow fixes are local changes made after build 3 was uploaded; they are not included in build 3.

## Prepared Build

- Bundle ID: `com.gorilla.translation`
- Version: `1.0`, build `2`
- Scheme: `GorillaTranslate`, configuration: `Release`
- Minimum OS: iOS / iPadOS 26.0
- Export configuration: `distribution/TestFlightExportOptions.plist`
- Export is local only; this configuration does not upload or invite testers.
- Local archive and App Store Connect export succeeded on 2026-10-13. Export used Cloud Managed Apple Distribution for the app and widget, with store provisioning profiles.
- Exported package: `output/TestFlight-1.0-2/GorillaTranslate.ipa`. Successful export is not an accepted upload or TestFlight availability.
- Xcode Organizer validation subsequently failed: team "Kwun Lun Tony YIP (Personal Team)" is not enrolled in the Apple Developer Program. Membership enrollment or selecting an enrolled team is required before distribution. No upload or invitation was completed.
- Follow-up account inspection confirmed active Apple Developer Program membership for the same team, renewing 2027-10-13. The previous Xcode enrollment error does not reflect the website membership state; refresh Xcode account/team information before retrying. App Store Connect currently requires the account holder to review and accept its Terms of Service before app setup can continue.
- App Store Connect record created: Gorilla Leading, Apple ID `6822058970`, primary locale Traditional Chinese, SKU `gorilla-leading-ios`.
- After the user accepted App Store Connect terms, explicit-team command-line upload succeeded on 2026-10-13. Build `1.0 (2)` is awaiting Apple's processing; it is not yet confirmed installable.
- Beta description and developer-selected feedback email were saved in App Store Connect. No external testers have been invited and no public link enabled.
- Internal group `Self Testing` created with manual distribution. The existing account holder was added as its sole tester; build assignment remains pending processing.
- Apple processing completed. Build `1.0 (2)` is listed with status "Missing Export Compliance". It cannot yet be assigned for testing. No encryption declaration was submitted.

## Historical Build 2 Export Compliance Blocker

The AMap binaries contain more than OS-provided TLS calls. Local symbol inspection found bundled OpenSSL-style functions in AMapNaviKit, XXTEA encryption functions in AMapFoundationKit, and AES/RSA wrappers. Symbol presence does not establish which algorithms are exercised or their legal classification. Do not declare OS-only encryption or set `ITSAppUsesNonExemptEncryption=NO` solely to clear the warning.

Obtain an export-compliance statement from AMap for the exact SDK versions before submitting the declaration. Suggested support request (not sent):

> We are preparing an iOS app for TestFlight using AMapNavi-NO-IDFA 11.2.100, AMapFoundation-NO-IDFA 1.9.1 and AMapLocation-NO-IDFA 2.12.2. Please provide the SDK's encryption export-compliance guidance: whether it includes proprietary/unpublished cryptography or non-OS implementations of standard cryptography, the applicable classification/CCATS/ECCN where available, and any documentation required for Apple App Store Connect, including France. We found XXTEA and OpenSSL-related symbols in the SDK binaries; please confirm their use and classification.

Apple guidance: https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance
- `TestFlightUploadOptions.plist` uses `destination=upload` and sends the archive to Apple; unlike `TestFlightExportOptions.plist`, it is not a local-only export.

## App Store Connect Setup

1. Confirm active Apple Developer Program membership and App Store Connect access.
2. Create an app record for the existing bundle ID if it does not already exist.
3. In Xcode Organizer, distribute the archive using App Store Connect / TestFlight & App Store, not TestFlight Internal Only if friends will test it.
4. Wait for Apple to process the build and resolve any validation warnings.
5. Complete export-compliance questions accurately. Review the encryption used by bundled third-party SDKs before declaring an exemption.
6. Add a feedback email, beta description and review contact. Do not use an account email automatically as the public feedback email.
7. For self-testing, add the account as an internal tester. For friends, create an external testing group and submit the build for Beta App Review, then invite them after approval.

## Suggested Beta Description

Gorilla Leading helps drivers remember parking locations, parking floors and parking photos, find nearby parking meters, and review visits and journeys. This beta focuses on real-world driving, parking and location reliability.

## What To Test

- Location and driving status while foregrounded, backgrounded and after reopening.
- Parking location, floor estimates, manual floor corrections and parking timers.
- Parking meter details and navigation; check local signs before parking.
- Live Activities and Dynamic Island timers.
- Language selection and stored data after restarting the device.
- Backup, restore and sharing a find-car card. Use a backup before testing restore.
- Long-session responsiveness, battery consumption and thermal behavior.

Floor estimates are not guaranteed. Operate the interface only when safely stopped. Never send private parking photos or precise coordinates in feedback unless you intend to share them.

## Remaining Release Checks

- Distribution signing and provisioning must succeed.
- Apple must accept the upload before a build is available in TestFlight.
- Confirm the replacement archive passes `ruby Tests/NoAMapChecks.rb <archive-path>`.
- Obtain the developer's chosen feedback email and external-review contact details.
- Invite only explicitly selected testers. A public link is not enabled by default.

Apple documentation: https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/
