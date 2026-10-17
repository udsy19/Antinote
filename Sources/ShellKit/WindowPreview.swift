import AppKit

/// The main note window built offscreen for rendering (JotterRender); it is never shown. Notes come from
/// `Services.store` (front note first), so the caller seeds the store before asking.
public enum WindowPreview {
    /// The window's whole frame view (traffic lights included). `revealed` shows the hover-only bars.
    @MainActor public static func frameView(revealed: Bool, slot: Int? = nil) -> NSView {
        Shell.shared.prepareForPreview(revealed: revealed, slot: slot)
    }
}
