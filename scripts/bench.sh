#!/usr/bin/env bash
# Performance benchmark (docs/ARCHITECTURE.md §19) on synthetic libraries in the temp directory. Informational:
# budgets are targets, not gates (DECISIONS D-42); every number is marked ok / near (within 1.5×) / over.
# Indexing and queries (jgscan), thumbnail throughput on 12-MP photos, then the Release app twice on a separate
# data directory: first run (index + scroll with uncached thumbnails), second run (launch from cache + scroll),
# then the photo viewer on the 12-MP photos (open, next photo, rapid flipping, a file outside the library), and the
# player on a 1080p clip and a 5-minute song (start, CPU, 2× speed, waveform; muted).
# Results: build/bench/*.txt and *.json. The app window appears for about 20 s per run; do not touch it.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/_common.sh

COUNT="${COUNT:-100000}"
LIBRARY="${TMPDIR}jGlancer-synthetic-$COUNT"
PHOTOS="${TMPDIR}jGlancer-synthetic-12mp-bench"
PLAYBACK="${TMPDIR}jGlancer-playback-bench"
OUT=build/bench
DATA="$OUT/data"
VIEWER_DATA="$OUT/data-viewer"
OUTSIDE="$OUT/outside"
mkdir -p "$OUT" "$OUTSIDE"
rm -rf "$DATA" "$VIEWER_DATA" "$OUT/data-playback"

[ -d "$LIBRARY" ] || scripts/make_synthetic_library.swift "$COUNT" --out "$LIBRARY"
[ -d "$PHOTOS" ] || scripts/make_synthetic_library.swift 3000 --photo-size 12mp --out "$PHOTOS"
[ -f "$PLAYBACK/song-5min.m4a" ] || scripts/make_playback_media.swift "$PLAYBACK"

echo "== Building (Release)"
CONFIG=Release scripts/build.sh > "$OUT/build.log" 2>&1 || { tail -20 "$OUT/build.log"; exit 1; }
swift build -c release --package-path Packages/JGCore --product jgscan > /dev/null
JGSCAN="$(swift build -c release --package-path Packages/JGCore --show-bin-path)/jgscan"
APP="build/DerivedData/Build/Products/Release/$APP_NAME.app/Contents/MacOS/$APP_NAME"

echo "== Indexing $COUNT files (targets: stage 1 ≤ 60 s, ≤ 1 KB/asset)"
"$JGSCAN" "$LIBRARY" --db "$OUT/jgscan.sqlite" --metadata | grep -E "stage|rescan|database:|refs|peak"
rm -f "$OUT"/jgscan.sqlite*

echo "== Thumbnails, 12-MP photos (target: ≥ 200/s uncached JPEG)"
"$JGSCAN" "$PHOTOS" --db "$OUT/jgscan-photos.sqlite" --thumbnails 1000 | grep -E "thumbnails public|cache.sqlite"
rm -f "$OUT"/jgscan-photos.sqlite*

for run in first second; do
  echo "== App, $run run"
  "$APP" -JGDataDirectory "$DATA" -JGAddFolder "$LIBRARY" -JGBenchmark "$OUT/$run.json" > "$OUT/$run.log" 2>&1
  cat "$OUT/$run.txt"
done

echo "== Viewer, 12-MP photos (targets: next photo ≤ 50 ms, open from Finder (warm) ≤ 150 ms)"
FIRST_PHOTO="$(find "$PHOTOS" -path '*/.seeds' -prune -o -name '*.JPG' -print | sort | sed -n 1p)"
cp "$PHOTOS/.seeds/photo.jpg" "$OUTSIDE/outside-12mp.jpg"
"$APP" -JGDataDirectory "$VIEWER_DATA" -JGAddFolder "$PHOTOS" -JGOpen "$FIRST_PHOTO" \
  -JGOutsideFile "$OUTSIDE/outside-12mp.jpg" -JGViewerBenchmark "$OUT/viewer.json" > "$OUT/viewer.log" 2>&1
cat "$OUT/viewer.txt"

echo "== Player, 1080p clip and 5-minute song (target: idle CPU after closing < 1 %)"
"$APP" -JGDataDirectory "$OUT/data-playback" -JGMute YES -JGOpen "$PLAYBACK/clip-1080p.mp4" \
  -JGAudioFile "$PLAYBACK/song-5min.m4a" -JGPlaybackBenchmark "$OUT/playback.json" > "$OUT/playback.log" 2>&1
cat "$OUT/playback.txt"
