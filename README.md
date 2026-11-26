# jGlancer (macOS)

A fast, light media browser, viewer and player for photos, video and music. Native Mac app (Swift 6, SwiftUI and AppKit,
SQLite through GRDB, Apple's media frameworks). Also for Windows:
[jGlancer-Windows](https://github.com/volodya88i/jGlancer-Windows).

## Features

- A library of your folders as a fast, virtualized grid of thumbnails or a Finder-style list; albums, flags, search,
  duplicates, split view, and a size map of a folder (nested rectangles by size).
- A sidebar that folds into a strip of icons, with your own symbol, emoji or photo for each library folder.
- Photo viewer with zoom, filmstrip and side-by-side compare; image sequences fold into one stack.
- Video and audio players: waveform, segment selection and export, MKV playback, frame capture, speed with kept pitch.
- Quick Preview with Space, also from Finder's Services; a mini player for music with media keys.
- Split songs into stems on your own Mac: the vocals and the instrumental, or 4 or 6 stems (Demucs, and Mel-Band
  RoFormer at High Quality, on Core ML; a model is downloaded only when you ask for it).
- Dark, Black and Light themes with an accent color of your choice; English and Russian.

## Install

Download `jGlancer-<version>.dmg` from [Releases](https://github.com/volodya88i/jGlancer-MacOS/releases), open it and drag
jGlancer to Applications. macOS 14 or later.

The app is not notarized by Apple (that needs a paid developer account), so macOS refuses to open it at first. After
checking you trust the download, either open **System Settings → Privacy & Security** and press **Open Anyway** after a
first try, or run:

```bash
xattr -dr com.apple.quarantine /Applications/jGlancer.app
```

## Your data and the network

jGlancer has no telemetry and never changes your media except through the file actions you choose. It uses the network
in two cases only:

- **Update check.** At most once a day it asks the GitHub API for the latest release; GitHub sees your IP address and the
  app's version, nothing about your files or library. It only offers to open the release page. Turn it off in Settings →
  General.
- **Stem models.** Downloaded from GitHub when you press Download, once for each model.

## Build from source

You need Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`; `xcbeautify`, `swiftformat`
and `swiftlint` are optional). From the repository root:

```bash
scripts/build.sh
scripts/test.sh
scripts/make_dmg.sh
```

Tests touch temporary folders only; `swift scripts/make_test_media.swift` generates test media in `TestMedia/generated`.
`scripts/make_dmg.sh` signs ad hoc; `docs/RELEASE.md` describes signing and notarization. The models come from
`scripts/stems/convert_demucs_coreml.py` and `scripts/stems/convert_roformer_coreml.py`. Code comments mention internal
decision numbers such as `D-85` and internal documents, which are not published.

## Licence

GNU General Public License 3.0: see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
