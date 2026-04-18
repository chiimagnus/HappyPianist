import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    @State private var isImporterPresented = false
    @State private var isARGuideSheetPresented = false

    private let importService: MusicXMLImportServiceProtocol = MusicXMLImportService()
    private let parser: MusicXMLParserProtocol = MusicXMLParser()
    private let stepBuilder: PracticeStepBuilderProtocol = PracticeStepBuilder()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("孤独钢琴家")
                .font(.largeTitle)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 10) {
                Text("AR 引导")
                    .font(.headline)

                HStack(spacing: 12) {
                    ToggleImmersiveSpaceButton()

                    Text(appModel.immersiveSpaceState == .open ? "运行中" : "已停止")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(appModel.calibration == nil ? "校准：未设置" : "校准：已加载")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(nextActionHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let calibrationStatusMessage = appModel.calibrationStatusMessage {
                    Text(calibrationStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text("谱子")
                    .font(.headline)

                HStack(spacing: 12) {
                    Button("导入 MusicXML…") {
                        isImporterPresented = true
                    }

                    if let importedFile = appModel.importedFile {
                        Text(importedFile.fileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("未导入谱子")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let importErrorMessage = appModel.importErrorMessage {
                    Text(importErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if appModel.importedSteps.isEmpty == false {
                    Text("步骤数：\(appModel.importedSteps.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text("练习")
                    .font(.headline)

                Text(practiceStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if appModel.importedSteps.isEmpty == false {
                    HStack(spacing: 12) {
                        Button("跳过") { appModel.practiceSessionViewModel.skip() }
                            .disabled(appModel.immersiveSpaceState != .open)

                        Button("标记为正确") { appModel.practiceSessionViewModel.markCorrect() }
                            .disabled(appModel.immersiveSpaceState != .open)
                    }
                } else {
                    Text("请先导入谱子以启用步骤控制。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Spacer()
        }
        .padding(24)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.xml, .musicXML],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .sheet(isPresented: $isARGuideSheetPresented) {
            ARGuideSheetView()
                .environment(appModel)
        }
        .onChange(of: appModel.immersiveSpaceState) { oldValue, newValue in
            if oldValue == .closed, newValue == .inTransition {
                isARGuideSheetPresented = true
                return
            }
            if oldValue == .open, newValue == .inTransition {
                isARGuideSheetPresented = false
                return
            }
            if newValue == .closed {
                isARGuideSheetPresented = false
                return
            }
            if newValue == .open {
                isARGuideSheetPresented = true
            }
        }
        .onAppear {
            appModel.loadStoredCalibrationIfPossible()
        }
    }

    private var nextActionHint: String {
        if appModel.calibration == nil {
            return "下一步：进入 AR 引导，然后依次点：设置 A0 → 设置 C8 → 保存。"
        }
        if appModel.importedSteps.isEmpty {
            return "下一步：在此窗口导入 MusicXML。"
        }
        return "下一步：进入 AR 引导，查看键位高亮并开始练习。"
    }

    private var practiceStatusText: String {
        switch appModel.practiceSessionViewModel.state {
        case .idle:
            return "空闲"
        case .ready:
            return "就绪（进入 AR 引导）"
        case .guiding(let index):
            return "引导中（第 \(index + 1) 步）"
        case .completed:
            return "已完成"
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        do {
            guard let selectedURL = try result.get().first else {
                return
            }
            let importedFile = try importService.importFile(from: selectedURL)
            let score = try parser.parse(fileURL: importedFile.storedURL)
            let buildResult = stepBuilder.buildSteps(from: score)
            if buildResult.unsupportedNoteCount > 0 {
                appModel.importErrorMessage = "已导入（忽略了 \(buildResult.unsupportedNoteCount) 个不支持的音符）。"
            }
            appModel.setImportedSteps(buildResult.steps, file: importedFile)
        } catch {
            appModel.importErrorMessage = "导入失败：\(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}

private struct ARGuideSheetView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text("AR 引导")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("停止") {
                    Task { @MainActor in
                        await dismissImmersiveSpace()
                    }
                }
                .fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(handTrackingStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(practiceStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if appModel.calibration == nil {
                calibrationControls
            } else if appModel.importedSteps.isEmpty {
                Text("请在主窗口导入 MusicXML 以开始引导。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                practiceControls
            }

            if let message = appModel.calibrationStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(20)
        .presentationDetents([.medium, .large])
    }

    private var calibrationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("校准")
                .font(.headline)

            Text(appModel.pendingCalibrationCaptureAnchor == nil ? "轻点空间预览准星。" : "轻点空间捕获所选锚点。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("设置 A0") { appModel.pendingCalibrationCaptureAnchor = .a0 }
                Button("设置 C8") { appModel.pendingCalibrationCaptureAnchor = .c8 }
                Button("保存") { appModel.saveCalibrationIfPossible() }
                    .fontWeight(.semibold)
            }

            Button("手动微调") {
                appModel.calibrationCaptureService.updateReticleEstimate(nil)
            }

            if appModel.calibrationCaptureService.mode == .manualFallback {
                HStack(spacing: 8) {
                    Button("A0 左移") {
                        appModel.calibrationCaptureService.adjust(anchor: .a0, delta: SIMD3<Float>(-0.01, 0, 0))
                    }
                    Button("A0 右移") {
                        appModel.calibrationCaptureService.adjust(anchor: .a0, delta: SIMD3<Float>(0.01, 0, 0))
                    }
                    Button("C8 左移") {
                        appModel.calibrationCaptureService.adjust(anchor: .c8, delta: SIMD3<Float>(-0.01, 0, 0))
                    }
                    Button("C8 右移") {
                        appModel.calibrationCaptureService.adjust(anchor: .c8, delta: SIMD3<Float>(0.01, 0, 0))
                    }
                }
            }
        }
    }

    private var practiceControls: some View {
        HStack(spacing: 12) {
            Button("跳过") { appModel.practiceSessionViewModel.skip() }
            Button("标记为正确") { appModel.practiceSessionViewModel.markCorrect() }
        }
    }

    private var handTrackingStatusText: String {
        switch appModel.handTrackingService.state {
        case .idle:
            return "手部：空闲"
        case .running:
            return "手部：运行中（\(appModel.handTrackingService.fingerTipPositions.count) 个点）"
        case .unavailable(let reason):
            return "手部：不可用（\(reason)）"
        }
    }

    private var practiceStatusText: String {
        switch appModel.practiceSessionViewModel.state {
        case .idle:
            return "练习：空闲"
        case .ready:
            return "练习：就绪"
        case .guiding(let index):
            return "练习：引导中（第 \(index + 1) 步）"
        case .completed:
            return "练习：已完成"
        }
    }
}
