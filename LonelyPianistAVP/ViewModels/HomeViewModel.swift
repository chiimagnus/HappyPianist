import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class HomeViewModel {
    private let appModel: AppModel

    var isImporterPresented = false

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    var immersiveSpaceState: AppModel.ImmersiveSpaceState {
        appModel.immersiveSpaceState
    }

    var immersiveSpaceID: String {
        appModel.immersiveSpaceID
    }

    var immersiveStatusText: String {
        immersiveSpaceState == .open ? "运行中" : "已停止"
    }

    var calibrationStatusText: String {
        appModel.calibration == nil ? "未设置" : "已加载"
    }

    var scoreStatusText: String {
        appModel.importedFile?.fileName ?? "未导入"
    }

    var stepCountText: String? {
        guard appModel.importedSteps.isEmpty == false else { return nil }
        return "\(appModel.importedSteps.count)"
    }

    var nextActionHint: String {
        if appModel.calibration == nil {
            return "下一步：开始 AR 引导 → 在弹出的表单里依次点“设置 A0 / 设置 C8”并在空间轻点捕获 → 保存。"
        }
        if appModel.importedSteps.isEmpty {
            return "下一步：导入 MusicXML（.musicxml 或 .xml）。"
        }
        return "下一步：开始 AR 引导，在表单里进入“练习”并按高亮键位弹奏。"
    }

    var importErrorMessage: String? {
        appModel.importErrorMessage
    }

    var calibrationStatusMessage: String? {
        appModel.calibrationStatusMessage
    }

    var canImportScore: Bool {
        immersiveSpaceState == .closed
    }

    func handleImportResult(_ result: Result<[URL], Error>) {
        do {
            guard let selectedURL = try result.get().first else { return }
            appModel.importMusicXML(from: selectedURL)
        } catch {
            appModel.importErrorMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    func stopARGuide(using dismissImmersiveSpace: DismissImmersiveSpaceAction) {
        guard immersiveSpaceState == .open else { return }
        Task { @MainActor in
            appModel.immersiveSpaceState = .inTransition
            await dismissImmersiveSpace()
        }
    }

    func beginNewARGuideSession() {
        appModel.beginNewARGuideSession()
    }

    func setImmersiveSpaceState(_ state: AppModel.ImmersiveSpaceState) {
        appModel.immersiveSpaceState = state
    }
}
