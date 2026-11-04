import JGDesign
import JGModel
import JGScanner
import SwiftUI

/// The extended facts of a file (`MediaDetails`) as label / value rows, in the units of the app's language.
enum MediaDetailsRows {
    struct Row: Hashable {
        let label: String
        let value: String
    }

    static func rows(_ details: MediaDetails) -> [Row] {
        var rows = photoRows(details)
        rows += videoRows(details)
        rows += audioRows(details)
        return rows
    }

    private static func photoRows(_ details: MediaDetails) -> [Row] {
        var rows: [Row] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty {
                rows.append(Row(label: label, value: value))
            }
        }
        add(String(localized: "Camera", comment: "Get Info label"), details.camera)
        add(String(localized: "Lens", comment: "Get Info label"), details.lens)
        add(String(localized: "Focal Length", comment: "Get Info label"), details.focalLength.map {
            String(localized: "\(number($0, digits: 1)) mm", comment: "Focal length in millimeters")
        })
        add(String(localized: "Aperture", comment: "Get Info label"), details.aperture.map { "ƒ/" + number($0, digits: 1) })
        add(String(localized: "Exposure", comment: "Get Info label"), details.exposureTime.map(exposure))
        add(String(localized: "ISO", comment: "Get Info label"), details.iso.map { "\($0)" })
        if let latitude = details.latitude, let longitude = details.longitude {
            add(String(localized: "Location", comment: "Get Info label: GPS coordinates"),
                String(format: "%.5f, %.5f", latitude, longitude))
        }
        add(String(localized: "Altitude", comment: "Get Info label"), details.altitude.map {
            String(localized: "\(number($0, digits: 0)) m", comment: "Altitude in meters")
        })
        add(String(localized: "Color Profile", comment: "Get Info label"), details.colorProfile)
        if details.videoCodec == nil, details.audioCodec == nil {
            add(String(localized: "Bit Depth", comment: "Get Info label"), details.bitDepth.map {
                String(localized: "\($0) bit", comment: "Bits per channel")
            })
        }
        return rows
    }

    private static func videoRows(_ details: MediaDetails) -> [Row] {
        var rows: [Row] = []
        if let codec = details.videoCodec {
            rows.append(Row(label: String(localized: "Video", comment: "Get Info label: video codec"), value: codec))
        }
        if let rate = details.frameRate {
            rows.append(Row(
                label: String(localized: "Frame Rate", comment: "Get Info label"),
                value: String(localized: "\(number(rate, digits: 2)) fps", comment: "Frames per second")
            ))
        }
        if let bitrate = details.videoBitrate {
            rows.append(Row(label: String(localized: "Video Bitrate", comment: "Get Info label"), value: bitrateText(bitrate)))
        }
        return rows
    }

    private static func audioRows(_ details: MediaDetails) -> [Row] {
        var rows: [Row] = []
        if let codec = details.audioCodec {
            rows.append(Row(label: String(localized: "Audio", comment: "Get Info label: audio codec"), value: codec))
        }
        if let bitrate = details.audioBitrate {
            rows.append(Row(label: String(localized: "Audio Bitrate", comment: "Get Info label"), value: bitrateText(bitrate)))
        }
        if let rate = details.sampleRate {
            rows.append(Row(
                label: String(localized: "Sample Rate", comment: "Get Info label"),
                value: String(localized: "\(number(rate / 1000, digits: 1)) kHz", comment: "Sample rate in kilohertz")
            ))
        }
        if let channels = details.channels {
            let value = switch channels {
            case 1: String(localized: "Mono", comment: "Audio channels")
            case 2: String(localized: "Stereo", comment: "Audio channels")
            default: String(localized: "\(channels) channels", comment: "Audio channels")
            }
            rows.append(Row(label: String(localized: "Channels", comment: "Get Info label"), value: value))
        }
        if details.audioCodec != nil, let depth = details.bitDepth {
            rows.append(Row(
                label: String(localized: "Bit Depth", comment: "Get Info label"),
                value: String(localized: "\(depth) bit", comment: "Bits per channel")
            ))
        }
        return rows
    }

    private static func exposure(_ seconds: Double) -> String {
        if seconds > 0, seconds < 1 {
            return String(localized: "1/\(Int((1 / seconds).rounded())) s", comment: "Exposure time as a fraction of a second")
        }
        return String(localized: "\(number(seconds, digits: 1)) s", comment: "Exposure time in seconds")
    }

    private static func bitrateText(_ bitsPerSecond: Double) -> String {
        if bitsPerSecond >= 1_000_000 {
            return String(localized: "\(number(bitsPerSecond / 1_000_000, digits: 1)) Mbit/s", comment: "Bitrate in megabits per second")
        }
        return String(localized: "\(number(bitsPerSecond / 1000, digits: 0)) kbit/s", comment: "Bitrate in kilobits per second")
    }

    private static func number(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(0 ... digits)))
    }
}

/// The rows of `MediaDetails` in two columns: labels in the label style, values in mono (docs/DESIGN.md §4).
struct MediaDetailsGrid: View {
    let rows: [MediaDetailsRows.Row]
    /// A song: its key and tempo as the last row (D-122).
    var songURL: URL?

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: JGSpacing.s, verticalSpacing: JGSpacing.xxs) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    Text(verbatim: row.label)
                        .jgTextStyle(.label)
                        .foregroundStyle(JGColor.textTertiary)
                        .gridColumnAlignment(.leading)
                    Text(verbatim: row.value)
                        .jgTextStyle(.mono)
                        .foregroundStyle(JGColor.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let songURL {
                GridRow {
                    Text("Key · BPM", comment: "Audio player: button for the song's key and tempo")
                        .jgTextStyle(.label)
                        .foregroundStyle(JGColor.textTertiary)
                    MusicFactsRow(url: songURL)
                }
            }
        }
    }
}

/// Loads and shows the extended facts of one file; nothing while loading or when there are none.
struct MediaDetailsSection: View {
    let url: URL
    let kind: MediaKind
    @State private var rows: [MediaDetailsRows.Row] = []

    var body: some View {
        // A placeholder while loading: a view with no content would never start its task.
        Group {
            if rows.isEmpty {
                Color.clear.frame(width: 0, height: 0)
            } else {
                MediaDetailsGrid(rows: rows, songURL: kind == .audio ? url : nil)
            }
        }
        .task(id: url) {
            rows = await MediaDetailsRows.rows(MediaDetails.read(url, kind: kind))
        }
    }
}
