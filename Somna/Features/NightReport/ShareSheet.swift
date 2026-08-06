import SwiftUI
import UIKit

/// A file waiting to be handed to the share sheet.
///
/// `sheet(item:)` needs identity, and a `URL` alone does not carry any — two
/// exports of the same night reuse the same path, and SwiftUI would treat the
/// second as the first and not re-present.
struct ExportedFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// The system share sheet.
///
/// SwiftUI's `ShareLink` covers text and values it can represent itself, but a
/// file produced asynchronously — the audio archive is zipped on demand and can
/// take a moment for a full night — has no URL to give a `ShareLink` at the time
/// the label is built. This presents the sheet once the file exists.
struct ShareSheet: UIViewControllerRepresentable {

    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
