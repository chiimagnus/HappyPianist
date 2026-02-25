import MenuBarDockKit
import Observation
import SwiftUI

struct SettingsView: View {
    @State private var appIconDisplayViewModel = AppIconDisplayViewModel()

    var body: some View {
        @Bindable var appIconDisplayViewModel = appIconDisplayViewModel

        Form {
            Picker("Display PianoKey icon", selection: $appIconDisplayViewModel.selectedMode) {
                ForEach(AppIconDisplayMode.allCases) { mode in
                    Text(mode.displayName)
                        .tag(mode)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(16)
    }
}
