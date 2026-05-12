import CoreAudioKit
import SwiftUI
import UIKit

struct BluetoothMIDICentralView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = CABTMIDICentralViewController()
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.presentationController?.delegate = context.coordinator
        return navigationController
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        uiViewController.presentationController?.delegate = context.coordinator
    }
}

extension BluetoothMIDICentralView {
    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        private let isPresented: Binding<Bool>

        init(isPresented: Binding<Bool>) {
            self.isPresented = isPresented
        }

        func presentationControllerDidDismiss(_: UIPresentationController) {
            isPresented.wrappedValue = false
        }
    }
}

