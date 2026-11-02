import CoreGraphics

/// The 4-point spacing scale (docs/DESIGN.md §5).
public enum JGSpacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let s: CGFloat = 12
    public static let m: CGFloat = 16
    public static let l: CGFloat = 24
    public static let xl: CGFloat = 32
    public static let xxl: CGFloat = 48

    /// The whole scale, ascending.
    public static let scale: [CGFloat] = [xxs, xs, s, m, l, xl, xxl]
}
