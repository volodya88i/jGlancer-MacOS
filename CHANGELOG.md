# Changelog

One short entry per published build of the macOS app. Versions are `major.minor.patch`: small features and fixes
bump the patch number, a release with new features bumps the minor number (DECISIONS D-76). The Windows version
keeps its own changelog in its repository.

## 0.5.0 — 2026-11-02
The first public version, free software under the GNU GPL 3.0.

- jGlancer looks for a newer version on GitHub once a day and offers its release page: its notes, Later, Skip This
  Version. Settings → General turns this off and has Check Now.
- About names the licence and links to GitHub and the source code.
- Help: jGlancer ▸ About jGlancer shows the version and the licences of third-party software (GRDB).
- This changelog.
- Rulers: a drag sets any value, the wheel moves finely, ⇧ snaps to the ticks; no focus ring.
- Players: the playhead moves smoothly; dragging it or the start bracket mutes until release; brackets move the
  playhead (⌥ keeps it); S toggles segment selection, M mutes; buttons never take Space or Return.
- Setting: the mouse wheel alone zooms a segment's timeline.
- Library: the sidebar hides subfolders without media and its edge drags; viewers page through what the grid shows.
- Lighter filmstrip, centred player controls, Get Info in Quick Preview; closing the window stops every player.
- Audio: waveform styles (Full, Narrow — default, Timeline), a morphing waveform entrance, steadier swipes between
  songs with tags read up front and a blurred backdrop that blends with the swipe.
- Video: wheel or pinch zoom up to 8× with panning, ⌘0 to fit, drags page between videos at fit; P saves the frame
  as a PNG next to the video, ⇧P copies it.
- Grid: thumbnails load where a fast scroll is heading, tiles that fly past wait in a slow background queue, and
  generation uses at most half the CPUs — about a third less CPU and less memory while scrolling fast.
- Grid: tiles glide to new places (Beauty), image sequences (render_001…090) fold into one tile, the first photo of
  the viewer shows at once.
- Adding a folder shows its progress with Stop; a whole drive asks first.
- Sidebar: New Folder…, Show in Finder and Move to Trash on folders; pinned folders.
- Mini player at the bottom of the window (Play in Mini Player, ⌥-double-click); it pauses for other players.
- Split view: two library panes side by side or stacked (View ▸ Split View, ⌃⌘S), each with its own folder,
  filters and selection; drag a sidebar folder onto a pane to show it there.
- Compare: two selected photos side by side (⌃⌘C) with linked zoom and pan, swap and 100 %.
- Edit ▸ Find Duplicates…: copies of the same file, the oldest kept; ticked copies are checked byte for byte
  before they go to the Trash (undoable).
- Mini player below the status bar; ⌥‹ Library or Play in Mini Player hands the viewer's song to it; media keys
  (play/pause, next, previous) work.
- Fix: the grid animation setting works from launch.
- Grid: changing the tile size is smooth — tiles grow continuously and fit the rows once you stop.
- Quick Preview stays on top of all windows and has Open in Viewer; files dropped on a viewer open.
- Image sequences: the badge has an arrow (› unfold, ‹ fold); the previews play a folded sequence on a frame
  timeline (drag through it or play at 24 frames a second).
- New icon: a glowing sound wave on a dark tile.
- Settings → Appearance: Accent Color (eight colors, a hex field, the system's color panel; lavender by default) and a
  Black theme. Switches, segments and check boxes follow the accent.
- New About window with GitHub and Source Code buttons and the third-party notices.
- Settings → Library → Stem Splitting: Compact or Full models.
- Calmer design: plain sliders instead of rulers, quiet kind filters, smaller headings, no glow on the playhead.
- Mini player: blurred cover behind it; its folder link also shows a file the kind filter hid.
- Audio player: Waveform or Timeline; the top bar is lighter and hides when the pointer rests.
- Fix: the grid could look empty after returning from a viewer with the automatic filmstrip.
- Split into Stems: a song's menu splits it into vocals, drums, bass and the rest (or 6 stems: also guitar and
  piano) as 24-bit WAV files, on this Mac with the Demucs model (a 3-minute song in about 10 seconds); the model is
  downloaded once, only when you agree. Your music never leaves the Mac.

## 0.1.0 — 2026-10-12
First build shared as a DMG: library with folders, albums, flags and search; photo, video and audio viewers with
filmstrip, speed and Keep Pitch; preview pane and Quick Preview (also from Finder's Services menu); file operations
with undo and batch rename; appearance presets; Settings; default-viewer buttons. Later the same day: MKV
(H.264/HEVC) playback, segment selection and export in the players, Play Next, volume in Quick Preview, one new
extension for a batch rename.
