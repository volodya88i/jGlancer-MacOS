/// The 60 mel bands Mel-Band RoFormer splits the spectrum into (D-131): each band's first bin and number of bins. They
/// are librosa's Slaney mel filters for a 2048-point STFT at 44.1 kHz, a bin taken where its weight is above zero, plus
/// the first and the last bin; neighbouring bands overlap. `scripts/stems/convert_roformer_coreml.py` computes the same
/// table, and the checkpoint's layer sizes confirm the counts.
public enum MelBands {
    public static let bands: [(start: Int, count: Int)] = [
        (0, 7), (4, 6), (7, 6), (10, 6), (13, 6), (16, 6), (19, 6), (22, 6), (25, 6), (28, 6), (31, 6), (34, 6), (37, 6),
        (40, 6), (43, 6), (46, 7), (49, 7), (53, 7), (56, 9), (60, 9), (65, 9), (69, 10), (74, 10), (79, 11), (84, 13),
        (90, 13), (97, 13), (103, 15), (110, 16), (118, 17), (126, 19), (135, 20), (145, 20), (155, 22), (165, 24),
        (177, 26), (189, 28), (203, 29), (217, 31), (232, 33), (248, 36), (265, 39), (284, 41), (304, 44), (325, 47),
        (348, 50), (372, 54), (398, 57), (426, 61), (455, 66), (487, 71), (521, 76), (558, 80), (597, 86), (638, 93),
        (683, 99), (731, 105), (782, 113), (836, 122), (895, 130),
    ]

    /// The bins of all bands, band after band (1979: most bins are in two bands).
    public static let bins: [Int] = bands.flatMap { $0.start ..< $0.start + $0.count }

    /// The network's values per frame, in and out: for each band bin, left then right, real then imaginary.
    public static let features = bins.count * 4

    /// How many bands each of the 1025 bins is in: the masks of overlapping bands are averaged.
    public static let coverage: [Float] = {
        var counts = [Float](repeating: 0, count: BandSpectrogram.bins)
        for bin in bins {
            counts[bin] += 1
        }
        return counts
    }()
}
