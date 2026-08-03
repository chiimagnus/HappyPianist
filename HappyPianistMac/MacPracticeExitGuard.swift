import AppKit
import SwiftUI

@MainActor
final class MacApplicationTerminationDelegate: NSObject, NSApplicationDelegate {
    var finishPractice: (@MainActor () async -> Bool)?
    private var isAwaitingTerminationReply = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard isAwaitingTerminationReply == false else { return .terminateLater }
        isAwaitingTerminationReply = true

        Task { @MainActor [weak self, weak sender] in
            guard let self, let sender else { return }
            let permitsTermination = await finishPracticeBeforeTermination()
            sender.reply(toApplicationShouldTerminate: permitsTermination)
            isAwaitingTerminationReply = false
        }
        return .terminateLater
    }

    func finishPracticeBeforeTermination() async -> Bool {
        await finishPractice?() ?? true
    }
}

struct MacPracticeWindowCloseGuard: NSViewRepresentable {
    let finishPractice: @MainActor () async -> Bool

    func makeCoordinator() -> MacPracticeWindowCloseCoordinator {
        MacPracticeWindowCloseCoordinator(finishPractice: finishPractice)
    }

    func makeNSView(context: Context) -> MacWindowAttachmentView {
        let view = MacWindowAttachmentView()
        view.onWindowChanged = { [weak coordinator = context.coordinator] window in
            coordinator?.install(on: window)
        }
        return view
    }

    func updateNSView(_ nsView: MacWindowAttachmentView, context: Context) {
        context.coordinator.update(finishPractice: finishPractice)
        context.coordinator.install(on: nsView.window)
    }
}

final class MacPracticeWindowCloseCoordinator: NSObject, NSWindowDelegate {
    private let state: MacPracticeWindowCloseState
    private let forwarding = MacWindowDelegateForwarder()

    @MainActor
    init(finishPractice: @escaping @MainActor () async -> Bool) {
        state = MacPracticeWindowCloseState(finishPractice: finishPractice)
    }

    @MainActor
    func update(finishPractice: @escaping @MainActor () async -> Bool) {
        state.update(finishPractice: finishPractice)
    }

    @MainActor
    func install(on window: NSWindow?) {
        guard let window, window.delegate !== self else { return }
        forwarding.delegate = window.delegate
        window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if MainActor.assumeIsolated({ state.isCompletingClose }) {
            return forwarding.delegate?.windowShouldClose?(sender) ?? true
        }
        let forwardedDelegateAllowsClose = forwarding.delegate?.windowShouldClose?(sender) ?? true
        return MainActor.assumeIsolated {
            state.beginClose(
                window: sender,
                forwardedDelegateAllowsClose: forwardedDelegateAllowsClose
            )
        }
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || forwarding.delegate?.responds(to: aSelector) == true
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        guard aSelector != #selector(windowShouldClose(_:)),
              forwarding.delegate?.responds(to: aSelector) == true
        else {
            return super.forwardingTarget(for: aSelector)
        }
        return forwarding.delegate
    }
}

private final class MacWindowDelegateForwarder: NSObject {
    weak var delegate: (any NSWindowDelegate)?
}

@MainActor
private final class MacPracticeWindowCloseState {
    private var finishPractice: @MainActor () async -> Bool
    private var isFinishing = false
    var isCompletingClose = false

    init(finishPractice: @escaping @MainActor () async -> Bool) {
        self.finishPractice = finishPractice
    }

    func update(finishPractice: @escaping @MainActor () async -> Bool) {
        self.finishPractice = finishPractice
    }

    func beginClose(
        window: NSWindow,
        forwardedDelegateAllowsClose: Bool
    ) -> Bool {
        guard forwardedDelegateAllowsClose, isFinishing == false else { return false }
        isFinishing = true

        Task { @MainActor [weak self, weak window] in
            guard let self else { return }
            defer { isFinishing = false }
            guard await finishPractice(), let window else { return }
            isCompletingClose = true
            window.performClose(nil)
            isCompletingClose = false
        }
        return false
    }
}

@MainActor
final class MacWindowAttachmentView: NSView {
    var onWindowChanged: (@MainActor (NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChanged?(window)
    }
}
