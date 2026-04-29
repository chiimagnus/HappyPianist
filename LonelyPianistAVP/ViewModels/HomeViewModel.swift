import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    private let appState: AppState

    var isImporterPresented = false

    init(appState: AppState) {
        self.appState = appState
    }

    var immersiveSpaceState: AppState.ImmersiveSpaceState {
        appState.immersiveSpaceState
    }

    var calibrationStatusText: String {
        if appState.calibration != nil {
            return "已定位"
        }
        return appState.storedCalibration == nil ? "未设置" : "已保存（待定位）"
    }

    var scoreStatusText: String {
        appState.importedFile?.fileName ?? "未导入"
    }

    var stepCountText: String? {
        guard appState.importedSteps.isEmpty == false else { return nil }
        return "\(appState.importedSteps.count)"
    }

    var nextActionHint: String {
        if appState.storedCalibration == nil {
            return "下一步：进入 Step 1 完成校准（设置 A0 / C8 后保存）。"
        }
        if appState.importedSteps.isEmpty {
            return "下一步：进入 Step 2 选曲页并导入 MusicXML（.musicxml 或 .xml）。"
        }
        if appState.calibration == nil {
            return "下一步：进入 Step 3 完成定位后开始练习。"
        }
        return "下一步：进入 Step 3 开始练习。"
    }

    var importErrorMessage: String? {
        appState.importErrorMessage
    }

    var calibrationStatusMessage: String? {
        appState.calibrationStatusMessage
    }

    func clearImportError() {
        appState.importErrorMessage = nil
    }

    var canImportScore: Bool {
        immersiveSpaceState == .closed
    }

    var canEnterPractice: Bool {
        true
    }

    var practiceEntryHelpText: String? {
        let hasImportedSteps = appState.importedSteps.isEmpty == false
        let hasStoredCalibration = appState.storedCalibration != nil

        if hasImportedSteps == false, hasStoredCalibration == false {
            return "可进入 Step 2 选曲；开始练习前需先完成 Step 1 校准并导入 MusicXML。"
        }
        if hasImportedSteps == false {
            return "可进入 Step 2 选曲；开始练习前需先导入 MusicXML。"
        }
        if hasStoredCalibration == false {
            return "可进入 Step 2 选曲；开始练习前需先完成 Step 1 校准。"
        }
        if appState.calibration == nil {
            return "可进入 Step 2 选曲；进入练习后会先定位钢琴。"
        }
        return nil
    }

    func handleImportResult(_ result: Result<[URL], Error>) {
        do {
            guard let selectedURL = try result.get().first else { return }
            appState.importMusicXML(from: selectedURL)
        } catch {
            appState.importErrorMessage = "导入失败：\(error.localizedDescription)"
        }
    }
}
