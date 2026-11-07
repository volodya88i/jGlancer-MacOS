import Accessibility
import AppKit
import ImageIO

/// Plays an animated GIF or PNG (D-124) with ImageIO's own frame timing and loop count: each frame arrives on the main
/// thread and goes to the `onFrame` of `play`. Nothing runs while nothing plays. Stays still when the system's
/// Accessibility → Display → Auto-play animated images is off.
@MainActor
final class AnimatedImagePlayer {
    /// One playback; ImageIO's callback asks it whether to go on (it can only be stopped from inside the callback).
    @MainActor
    private final class Run {
        var isStopped = false
    }

    private var run: Run?
    /// The file playing (or played to its last loop).
    private(set) var url: URL?

    /// Plays `url`, unless it already plays; another file playing stops first.
    func play(_ url: URL, onFrame: @escaping @MainActor (CGImage) -> Void) {
        guard url != self.url else { return }
        stop()
        guard Self.autoplays else { return }
        let run = Run()
        let status = CGAnimateImageAtURLWithBlock(url as CFURL, nil) { _, image, stop in
            MainActor.assumeIsolated {
                if run.isStopped {
                    stop.pointee = true
                } else {
                    onFrame(image)
                }
            }
        }
        guard status == noErr else { return }
        self.run = run
        self.url = url
    }

    func stop() {
        run?.isStopped = true
        run = nil
        url = nil
    }

    /// The system's Auto-play animated images (Accessibility → Display).
    static var autoplays: Bool {
        if #available(macOS 15, *) {
            AccessibilitySettings.animatedImagesEnabled
        } else {
            AXAnimatedImagesEnabled()
        }
    }
}
