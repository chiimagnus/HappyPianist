import AppKit
@testable import HappyPianistMac
import Testing

@MainActor
struct MacPracticeExitGuardTests {
    @Test func windowCloseWaitsForFinishAndKeepsTheWindowOpenOnFailure() async {
        let probe = ExitProbe(result: false)
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.orderFront(nil)
        defer { window.close() }
        let coordinator = MacPracticeWindowCloseCoordinator {
            probe.calls += 1
            return probe.result
        }
        coordinator.install(on: window)

        #expect(coordinator.windowShouldClose(window) == false)
        #expect(await settles { probe.calls == 1 })
        #expect(window.isVisible)
    }

    @Test func windowCloseForwardsPermissionOnlyOnceBeforeFinishing() async {
        let probe = ExitProbe(result: true)
        let forwardedDelegate = CountingWindowDelegate()
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.delegate = forwardedDelegate
        window.orderFront(nil)
        defer { window.close() }
        let coordinator = MacPracticeWindowCloseCoordinator {
            probe.calls += 1
            return probe.result
        }
        coordinator.install(on: window)

        #expect(coordinator.windowShouldClose(window) == false)
        #expect(await settles { probe.calls == 1 && forwardedDelegate.shouldCloseCalls == 1 })
    }

    @Test func applicationTerminationUsesTheSameAsyncFinishGate() async {
        let delegate = MacApplicationTerminationDelegate()
        var calls = 0
        delegate.finishPractice = {
            calls += 1
            return false
        }

        #expect(await delegate.finishPracticeBeforeTermination() == false)
        #expect(calls == 1)
    }
}

@MainActor
private final class ExitProbe {
    var calls = 0
    let result: Bool

    init(result: Bool) {
        self.result = result
    }
}

@MainActor
private final class CountingWindowDelegate: NSObject, NSWindowDelegate {
    var shouldCloseCalls = 0

    func windowShouldClose(_: NSWindow) -> Bool {
        shouldCloseCalls += 1
        return true
    }
}

@MainActor
private func settles(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0 ..< 100 {
        if condition() { return true }
        await Task.yield()
    }
    return condition()
}
