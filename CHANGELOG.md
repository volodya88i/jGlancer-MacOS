# Changelog

One short entry per published build of the macOS app. Versions are `major.minor.patch`: after each public release
the patch number goes up by one for the next one; the minor number goes up for larger releases. The Windows version
keeps its own changelog in its repository.

## 0.6.4 — 2026-11-26
Split a song into just the vocals and the instrumental (a backing track), at standard or high quality.

**New**
- **Split into 2 stems**: Split into Stems… can make just the vocals and the instrumental (the song without its
  vocals, a backing track); added together they give the song back exactly. It uses the 4-stem model, so there is
  nothing new to download.
- **High Quality for 2 stems**: a much cleaner instrumental and vocals with the Mel-Band RoFormer model, an optional
  download (848 MB, or 423 MB compact); it takes about 50 seconds for a 3-minute song.

## 0.6.3 — 2026-11-24
A size map, a sidebar that folds into a strip of icons, folder icons, and photos and videos over the whole Quick
Preview.

**New**
- **Size map** (View ▸ Show Size Map, ⌥⌘T): the folder's photos, videos and songs as rectangles by size, like
  WizTree, under the files or on the right; it swaps places with the preview.
- **Folding sidebar**: the sidebar folds into a narrow strip with the library folders, the albums and the Trash as
  icons (the button at its top, or View ▸ Show Sidebar, ⌥⌘S), and by itself when the window is narrow; resting the
  pointer on the strip opens it over the files. The window can now be narrower.
- **Folder icons**: a library folder can show its own symbol, emoji or photo (right-click the folder ▸ Folder Icon…,
  or a photo ▸ Use as Folder Icon).
- Sidebar → Hide from Library for a subfolder you do not want to see, and Settings → Library → Hide files smaller
  than (icons in Downloads, say); nothing is deleted.
- Quick Preview shows photos and videos over the whole window with translucent bars that fade, a volume slider
  in a small bubble, and a pin to keep it above other windows.

**Improved**
- Photos open sharp instead of first showing their blurry thumbnail.
- Space plays and pauses the open player wherever the keyboard focus is.
- Smaller folder and audio icons in the list; its columns always fit the window.
- The top bars beside the window's buttons leave as much room after them as before them.

**Fixed**
- In a narrow window the files no longer push the preview past the window's edge.

## 0.6.2 — 2026-11-07
A list view, animated GIFs, files kept in the cloud left in the cloud, and fixes from a full review.

**New**
- **List view**: files in Finder-style columns (name with a small preview, date modified, size, kind) with folders
  that unfold; switch in the top bar or with ⌃⌘1 / ⌃⌘2. A double-click on a folder shows that folder.
- Animated GIFs (and animated PNGs) play in the viewer, the preview and Quick Preview.
- Files kept only in iCloud Drive (or Dropbox, OneDrive) show a cloud and are no longer downloaded by browsing;
  opening one downloads it.
- Thumbnails show the full colors of iPhone photos (they are made once again after the update).

**Fixed**
- Moving a folder to another disk checks every file of the copy, and never deletes the copy when the original
  could only be deleted in part; a failed Replace puts the replaced file back.
- A library that cannot be opened (no permission, a full disk) shows an error instead of being replaced by its
  backup.
- A folder on an external disk comes back as soon as the disk is plugged in, and shows Offline as soon as it is
  ejected.
- Selection in the grid shows at once; scrolling over many thumbnails takes less work.
- The counts at the bottom of the grid are readable over any picture.
- Searching one or two letters ignores case in Russian too.
- Notices about file operations fade in and out.
- TypeScript files (.ts) no longer appear as videos; a saved video frame is named "… 2.png" like other copies.

## 0.6.1 — 2026-11-04
- Albums no longer show files that were removed as dimmed tiles that cannot be opened; a file that comes back
  returns to its albums.
- The blurred backdrop no longer blinks when paging between songs, in the audio player and in the previews.
- The mini player shows the cover of the song that plays next by itself, and has Loop and Play Next.
- Get Info and the preview show a song's key and tempo as the last line of the details once the player found them;
  otherwise a small **detect** finds them on a click.
- A new export glyph: a sheet with an arrow leaving it, in the style of the players' other buttons.

## 0.6.0 — 2026-11-04
A large update: the Mac app catches up with jGlancer for Windows 0.5.4 and gets a Finder-like window.

**New**
- Audio player: **Key · BPM** finds a song's tempo and key. Its panel plays the song at a target pitch or tempo by
  speed, for that song only; the speed menu offers target pitches; Get Info shows BPM and Key once found.
- The players' export button is always there: without a segment it saves the whole file (audio at the current speed,
  MP4 and MOV video unchanged).
- Video segments are cut exactly at the brackets, encoded again as H.264 MP4 (Settings → Playback; off copies as
  before).
- Pinch, or ⌘ with two fingers up and down, sizes the thumbnails.
- Settings → Appearance → Effects → **See through the photo viewer**: the desktop shows, blurred, behind photos.
- Settings → Appearance → Decor: the audio and the video player each draw a waveform or a timeline; the video can
  show its sound's waveform.
- View → Show Status Bar.

**Look**
- New icon: a glass photo frame on a dark tile.
- Finder-like window: the window buttons sit on the top bar's line, the files scroll under a frosted top bar, and the
  status became a small frosted bubble at the bottom of the files.
- Frosted glass behind toasts, progress panels and the viewers' top bar (Settings → Appearance → Effects).
- Filters that are on are inverted; lavender is the same in light and dark; the duration badge sits at the bottom
  right of tiles.
- The mini player runs under the whole window; waveforms fill their scrubber and the playhead is as tall as they are.

**Better**
- Volume follows the ear: half the slider sounds about half as loud.
- Flagging files no longer reloads the library: flags appear at once.
- Photos open at their own size straight away.
- Smooth thumbnail sizing, also on fast drags; smooth window resizing with a viewer open; the size ruler never moves
  the window.
- A click on a video plays or pauses it, a double-click goes full screen; looping no longer brings the controls back.
- A double-click on the top bar zooms the window.
- The automatic filmstrip appears only where it lives and fades in place.
- The key and tempo panel fits its contents and stays put; Quick Preview never gets narrower than its controls; a
  narrow window no longer pushes the preview off the edge.
- Sidebar rows mark drops with a fading accent; album drops land beside the nearest tile; song titles show at once in
  the previews.

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
