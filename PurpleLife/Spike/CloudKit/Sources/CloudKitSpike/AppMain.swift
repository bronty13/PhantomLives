import SwiftUI

@main
struct CloudKitSpikeApp: App {
    @StateObject private var viewModel = SpikeViewModel()

    var body: some Scene {
        WindowGroup("PurpleLife · CloudKit Spike") {
            SpikeView(viewModel: viewModel)
                .frame(minWidth: 560, minHeight: 420)
        }
        .windowResizability(.contentSize)
    }
}
