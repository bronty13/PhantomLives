import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Assistant

/// Local-LLM assistant configuration. Wraps the existing
/// AssistantSetupSection so the work that already lives there doesn't
/// get reimplemented.
struct AssistantSetup: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                AssistantSetupSection(settings: settings)
            }
            .padding()
        }
    }
}

