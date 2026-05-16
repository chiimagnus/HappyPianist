import SwiftUI
import os

private let step3WindowGeometryLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP",
    category: "Step3WindowGeometry"
)

struct Step3WindowGeometryHint: UIViewControllerRepresentable {
    func makeUIViewController(context _: Context) -> UIViewController {
        WindowGeometryHintViewController()
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}
}

final class WindowGeometryHintViewController: UIViewController {
    private var hasRequestedGeometryUpdate = false
    private var hasRequestedRestoreGeometryUpdate = false
    private var previousWindowSize: CGSize?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        capturePreviousWindowSizeIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        requestGeometryUpdateIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        requestRestoreGeometryUpdateIfNeeded()
    }

    private func requestGeometryUpdateIfNeeded() {
        guard hasRequestedGeometryUpdate == false else { return }
        guard let windowScene = view.window?.windowScene else { return }

        hasRequestedGeometryUpdate = true
        capturePreviousWindowSizeIfNeeded()

        let preferences = UIWindowScene.GeometryPreferences.Vision(
            size: CGSize(width: 1600, height: 620),
            minimumSize: CGSize(width: 1200, height: 520),
            maximumSize: nil,
            resizingRestrictions: nil
        )

        windowScene.requestGeometryUpdate(preferences) { error in
            step3WindowGeometryLogger.error(
                "Step 3 requestGeometryUpdate failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func requestRestoreGeometryUpdateIfNeeded() {
        guard hasRequestedRestoreGeometryUpdate == false else { return }
        guard let windowScene = view.window?.windowScene else { return }

        hasRequestedRestoreGeometryUpdate = true
        let restoreSize = previousWindowSize ?? CGSize(width: 700, height: 700)

        let preferences = UIWindowScene.GeometryPreferences.Vision(
            size: restoreSize,
            minimumSize: CGSize(width: 560, height: 560),
            maximumSize: nil,
            resizingRestrictions: nil
        )

        windowScene.requestGeometryUpdate(preferences) { error in
            step3WindowGeometryLogger.error(
                "Step 3 restore requestGeometryUpdate failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func capturePreviousWindowSizeIfNeeded() {
        guard previousWindowSize == nil else { return }
        guard let window = view.window else { return }
        let size = window.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        previousWindowSize = size
    }
}
