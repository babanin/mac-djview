# App Store Setup — Manual Steps

## Prerequisites

1. **Enroll in Apple Developer Program** ($99/year) at https://developer.apple.com/programs/
2. **Open Xcode → Settings → Accounts** → add your Apple ID, select your team
3. **Create app icon**: a single 1024×1024 PNG image (any design tool or AI image generator)
4. Place the PNG as `Sources/MacDjView/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png`

## Xcode Project Setup

1. **Open** `Package.swift` in Xcode (File → Open → select `Package.swift`)
2. Xcode resolves the SPM package and shows the `MacDjView` target
3. **Select the MacDjView scheme** → Edit Scheme → set Build Configuration to Release for Archive
4. **In the project editor** (click the package in the navigator):
   - Signing & Capabilities → Team: select your team → enable "Automatically manage signing"
   - Signing & Capabilities → + Capability → "App Sandbox" → enable "User Selected File (Read Only)"
   - Signing & Capabilities → + Capability → "Hardened Runtime"
   - Set Code Signing Entitlements to `MacDjView.entitlements`
5. **General tab**:
   - Bundle Identifier: `net.babanin.MacDjView`
   - Version: `1.0.0`
   - Build: `1`
   - App Category: Productivity
   - Deployment Target: macOS 14.0

> **Note**: If Xcode doesn't let you configure signing for a pure SPM executable target, create a thin Xcode project wrapper:
> 1. File → New → Project → macOS → App → name it `MacDjView`
> 2. Delete generated boilerplate source files
> 3. File → Add Package Dependencies → Add Local → select repo root
> 4. In target's Frameworks, add `MacDjView` from the local package
> 5. Configure signing on this wrapper target

## Info.plist Configuration

In Xcode's Info tab (or a custom Info.plist), add:

| Key | Value |
|-----|-------|
| `LSApplicationCategoryType` | `public.app-category.productivity` |
| `NSHumanReadableCopyright` | `Copyright © 2024-2026 MacDjView. All rights reserved.` |

**Document Types** (in Xcode target → Info → Document Types):

| Field | Value |
|-------|-------|
| Name | DjVu Document |
| Role | Viewer |
| Content Type Identifier | `org.djvu.djvu` |

**Imported UTIs** (in Xcode target → Info → Imported Type Identifiers):

| Field | Value |
|-------|-------|
| Description | DjVu Document |
| Identifier | `org.djvu.djvu` |
| Conforms To | `public.data` |
| Extensions | `djvu`, `djv` |
| MIME Types | `image/vnd.djvu` |

## App Store Connect Setup

1. Go to https://appstoreconnect.apple.com → My Apps → "+" → New App
2. Platform: **macOS**, Name: **MacDjView**, Bundle ID: `net.babanin.MacDjView`, SKU: `macdjview`
3. Fill in:
   - Description and keywords
   - Category: Productivity
   - Screenshots (at least one at 1280×800 or 1440×900)
4. Set pricing (Free or paid)
5. Add a privacy policy URL (required even if you collect nothing — a simple GitHub Pages or gist works)

## Archive & Submit

1. In Xcode: **Product → Archive**
2. In Organizer: select archive → **Distribute App → App Store Connect → Upload**
3. Xcode validates signing, entitlements, privacy manifest, and icons
4. In App Store Connect: select the uploaded build → **Submit for Review**

> **Review notes tip**: DjVu is niche — include a test `.djvu` file URL or note in review notes so Apple reviewers can test the app.
