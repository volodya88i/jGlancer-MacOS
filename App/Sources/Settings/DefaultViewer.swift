import AppKit
import JGDesign
import SwiftUI
import UniformTypeIdentifiers

/// Settings → General → Default viewer: one button per kind makes the app open those files from Finder. macOS
/// confirms each format, so each kind lists only its everyday formats (RAW stays with the user's raw developer).
struct DefaultViewerSettings: View {
    enum Kind: CaseIterable {
        case photos, videos, audio

        var types: [UTType] {
            let identifiers: [String] = switch self {
            case .photos:
                ["public.jpeg", "public.heic", "public.heif", "public.png", "com.compuserve.gif", "org.webmproject.webp",
                 "public.tiff", "com.microsoft.bmp", "public.avif", "public.jpeg-xl"]
            case .videos:
                ["com.apple.quicktime-movie", "public.mpeg-4", "com.apple.m4v-video", "public.avi", "public.mpeg",
                 "public.mpeg-2-transport-stream", "public.3gpp", "org.matroska.mkv"]
            case .audio:
                ["public.mp3", "public.mpeg-4-audio", "com.microsoft.waveform-audio", "public.aiff-audio", "org.xiph.flac",
                 "public.aac-audio", "com.apple.coreaudio-format", "org.xiph.ogg-audio", "org.matroska.mka"]
            }
            return identifiers.compactMap { UTType($0) }
        }

        var title: Text {
            switch self {
            case .photos: Text("Photos", comment: "Settings: default viewer for photos")
            case .videos: Text("Videos", comment: "Settings: default viewer for videos")
            case .audio: Text("Audio", comment: "Settings: default viewer for audio")
            }
        }
    }

    @State private var handled: [Kind: Int] = [:]
    @State private var working: Kind?

    var body: some View {
        SettingsGroup(title: Text("Default Viewer", comment: "Settings group; shown in capitals")) {
            Text(
                "Open these files from Finder in \(AppIdentity.name):",
                comment: "Settings: default viewer; the argument is the app's name"
            )
            .jgTextStyle(.body)
            .foregroundStyle(JGColor.textSecondary)
            HStack(spacing: JGSpacing.s) {
                ForEach(Kind.allCases, id: \.self) { kind in
                    VStack(alignment: .leading, spacing: JGSpacing.xxs) {
                        Button {
                            Task { await makeDefault(kind) }
                        } label: {
                            kind.title
                        }
                        .buttonStyle(.jg(.secondary))
                        .disabled(working != nil)
                        Text("\(handled[kind] ?? 0) of \(kind.types.count)", comment: "Settings: formats that already open in the app")
                            .jgTextStyle(.mono)
                            .foregroundStyle(JGColor.textTertiary)
                    }
                }
            }
            Text("macOS asks once per format.", comment: "Settings: default viewer note")
                .jgTextStyle(.body)
                .foregroundStyle(JGColor.textTertiary)
        }
        .onAppear(perform: count)
    }

    private func count() {
        let app = Bundle.main.bundleURL.standardizedFileURL
        for kind in Kind.allCases {
            handled[kind] = kind.types.filter { NSWorkspace.shared.urlForApplication(toOpen: $0)?.standardizedFileURL == app }.count
        }
    }

    private func makeDefault(_ kind: Kind) async {
        working = kind
        for type in kind.types {
            try? await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type)
        }
        working = nil
        count()
    }
}
