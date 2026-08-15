# Releasing IO: localhost

This project currently ships **unsigned** (no paid Apple Developer account required).
Users get one extra click the first time they open it. Notarization steps are at the end
for when you're ready to remove that friction.

## 1. Bump the version

In Xcode → target **LocalhostIO** → **General**, set **Version** (`MARKETING_VERSION`) and
**Build** (`CURRENT_PROJECT_VERSION`). Or edit them in `project.pbxproj`.

## 2. Build a Release `.app`

**From Xcode:** Product → Archive → in the Organizer, **Distribute App** →
**Custom** → **Copy App** → export the folder. (For an unsigned/local build you can also just
grab the `.app` from Product → Show Build Folder → `Products/Release/`.)

**From the command line:**
```bash
xcodebuild -project LocalhostIO.xcodeproj -scheme LocalhostIO \
  -configuration Release -derivedDataPath build clean build
# result: build/Build/Products/Release/LocalhostIO.app
```

## 3. Zip it for distribution

Use `ditto` (preserves the bundle correctly — don't use Finder's "Compress" for signed apps):
```bash
ditto -c -k --keepParent "build/Build/Products/Release/LocalhostIO.app" IO-localhost.zip
```

## 4. Publish

Attach `IO-localhost.zip` to a **GitHub Release** (tag e.g. `v1.0.0`) with notes from
`CHANGELOG.md`.

## 5. Tell users how to open an unsigned build

Because the build isn't notarized, macOS quarantines it on download. Include this in the
release notes:

> **First launch:** After moving **IO: localhost** to Applications, open **System Settings →
> Privacy & Security**, scroll to the note about IO: localhost being blocked, and click
> **Open Anyway**. (On older macOS you can instead right-click the app → **Open** → **Open**.)

Power users can clear the quarantine flag directly:
```bash
xattr -dr com.apple.quarantine "/Applications/IO: localhost.app"
```

---

## Later: signing + notarization (removes the warning)

Requires an Apple Developer account ($99/yr) and a **Developer ID Application** certificate.

1. In the target's build settings, set **`ENABLE_HARDENED_RUNTIME = YES`** and select your
   **Developer ID Application** signing identity / team. (The app is unsandboxed and spawns
   child processes; that's allowed under the hardened runtime — no extra entitlements needed.)
2. Archive and **Distribute App → Developer ID → Upload/Export**, or from the CLI:
   ```bash
   # sign
   codesign --force --deep --options runtime \
     --sign "Developer ID Application: <You> (<TEAMID>)" "IO: localhost.app"
   # notarize (store credentials once with: xcrun notarytool store-credentials)
   ditto -c -k --keepParent "IO: localhost.app" IO-localhost.zip
   xcrun notarytool submit IO-localhost.zip --keychain-profile "NOTARY" --wait
   # staple the ticket
   xcrun stapler staple "IO: localhost.app"
   ```
3. Re-zip the stapled `.app` for distribution. Notarized builds open with a normal
   double-click.

## Optional: Homebrew cask

Once notarized, a cask makes install a one-liner. Sketch:
```ruby
cask "io-localhost" do
  version "1.0.0"
  sha256 "…"
  url "https://github.com/<you>/localhostIO/releases/download/v#{version}/IO-localhost.zip"
  name "IO: localhost"
  desc "See and manage your local dev servers"
  homepage "https://github.com/<you>/localhostIO"
  app "IO: localhost.app"
end
```
