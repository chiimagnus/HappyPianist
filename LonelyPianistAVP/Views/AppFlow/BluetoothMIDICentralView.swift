import CoreAudioKit
import SwiftUI
import UIKit

struct BluetoothMIDICentralEmbeddedView: UIViewControllerRepresentable {
    func makeUIViewController(context _: Context) -> UINavigationController {
        let controller = CABTMIDICentralViewController()
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_: UINavigationController, context _: Context) {}
}

