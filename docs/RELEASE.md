# Release checklist (macOS)

v1 ships outside the Mac App Store: Developer ID signature, hardened runtime, notarization, a DMG (DECISIONS D-03).
`scripts/make_dmg.sh` does the build, signing, packing and notarization; this page is what has to be true around it.

## Once
1. **Apple Developer Program** membership; a **Developer ID Application** certificate in the login keychain
   (Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates). Its name looks like
   `Developer ID Application: Name (TEAMID)` — `security find-identity -v -p codesigning` lists it.
2. **Bundle id**: `io.github.volodya88i.jglancer` (D-68), defined in `project.yml`. Do not change it again: settings
   and caches live under it.
3. **Notarization credentials** stored once in the keychain:
   `xcrun notarytool store-credentials jglancer-notary --apple-id <email> --team-id <TEAMID> --password <app-specific password>`
   (the app-specific password comes from account.apple.com).
4. **App icon**: the placeholder from `scripts/make_app_icon.swift` is replaced by the final one
   (`App/Resources/Assets.xcassets/AppIcon.appiconset`).

## Every release
1. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in `project.yml`.
2. `/verify` (build, tests, lint) is green; `scripts/bench.sh` numbers are within the budgets (ARCHITECTURE §19).
3. Manual pass on a real Mac: the checklists of the last phases in the reports, light and dark theme,
   Russian and English, a real library, Finder's Open With and Services ▸ jGlancer: Quick Preview.
4. Build, sign, notarize, staple:
   `SIGN_IDENTITY="Developer ID Application: … (TEAMID)" NOTARY_PROFILE=jglancer-notary scripts/make_dmg.sh`
5. Check the result on a second Mac or a fresh user account: the DMG opens without a Gatekeeper warning,
   `spctl --assess --type execute --verbose=2 /Applications/jGlancer.app` says *accepted, source=Notarized Developer ID*.
6. Keep `build/DerivedData/Build/Products/Release/jGlancer.app.dSYM` with the release (symbolicating crash reports).

## What the build already does
- **Hardened runtime** in every Release build (`OTHER_CODE_SIGN_FLAGS: --options=runtime`); no extra entitlements
  are needed (no JIT, no sandbox, no Apple Events).
- **Stripped binary**, symbols in the dSYM: the app is about 11 MB (Apple Silicon and Intel); the DMG about 5 MB.
- **Network**: no telemetry or remote fonts. Only the daily update check (off in Settings) and a stem model when the
  user presses Download.

## Crash safety (D-66)
- `library.sqlite` (albums, flags, the index) is copied once a day to `library-backup.sqlite` next to it
  (`VACUUM INTO`, a consistent copy).
- If the library does not open or fails `PRAGMA quick_check`, it is renamed `library-damaged-<date>.sqlite`
  (never deleted) and the backup takes its place, or a new library starts; a banner says so once.
- If nothing can be opened (an unwritable or missing disk), the window explains it instead of staying empty.
- `cache.sqlite` (thumbnails, waveforms) is disposable: a damaged cache is removed and rebuilt.
- Files are only ever changed through the file operation queue: moves verify before deleting, trashed files go
  to the Trash, every operation can be undone (D-56).
