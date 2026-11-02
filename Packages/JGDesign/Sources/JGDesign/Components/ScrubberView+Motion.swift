import AppKit

/// Smooth playhead motion of `ScrubberView` (`PlayheadMotion`), running only while playing and on screen.
public extension ScrubberView {
    internal func updateMotion() {
        motion.update(
            rate: playbackRate,
            view: self,
            onScreen: animatesPlayhead && window != nil && !isHiddenOrHasHiddenAncestor,
            selector: #selector(frameTick)
        )
    }

    @objc internal func frameTick() {
        guard !isScrubbing else { return }
        followPlayhead(from: visible.end, to: motion.time)
        placePlayhead()
    }

    /// The waveform's columns for the bounds: morphed in after a change of peaks, otherwise at once.
    internal func layoutWaveform(_ waveform: JGWaveformPeaks, shown: ScrubberWindow?) {
        let target = Self.waveColumns(
            waveform, detail: detail, duration: duration, visible: shown, count: Int(bounds.width.rounded(.down))
        )
        if waveformChanged, animatesWaveform, window != nil {
            morph.morph(to: target, view: self, selector: #selector(morphTick))
        } else {
            morph.jump(to: target)
        }
        waveformChanged = false
        drawWave()
    }

    @objc internal func morphTick() {
        _ = morph.step()
        drawWave()
    }

    private func drawWave() {
        let path = Self.wavePath(morph.shown, height: waveformHeight, in: bounds)
        trackLayer.path = path
        playedLayer.path = path
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMotion()
        if window == nil {
            morph.stop()
        }
    }

    override func viewDidHide() {
        super.viewDidHide()
        updateMotion()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updateMotion()
    }
}
