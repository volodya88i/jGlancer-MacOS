/// Playback rate presets, range and stepping (docs/FEATURES.md §5).
///
/// Range measured on device (DECISIONS D-17): AVFoundation plays local audio exactly at 0.25×–8× with every
/// pitch algorithm and video at 0.25×–4×; the app offers 0.25×–4×.
public enum PlaybackSpeed {
    /// The normal playback rate.
    public static let normal: Float = 1.0
    /// Rates offered in the speed menu, ascending.
    public static let presets: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    /// Increment used by the `[` and `]` shortcuts.
    public static let fineStep: Float = 0.05
    /// Every rate the app sets is inside this range.
    public static let range: ClosedRange<Float> = 0.25 ... 4.0

    /// `rate` inside `range`, rounded to the fine step (so repeated steps never drift).
    public static func clamped(_ rate: Float) -> Float {
        // Rounded in Double, so presets such as 1.25 come out exactly equal.
        let step = Double(fineStep)
        let rounded = Float((Double(rate) / step).rounded() * step)
        return min(max(rounded, range.lowerBound), range.upperBound)
    }

    /// `rate` moved by `steps` fine steps (negative slows down), clamped.
    public static func stepped(_ rate: Float, by steps: Int) -> Float {
        clamped(rate + Float(steps) * fineStep)
    }
}
