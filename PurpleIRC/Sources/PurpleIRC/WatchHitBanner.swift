import SwiftUI

/// A compact banner pinned to the top of the main content area that shows
/// the single most-recent unacknowledged watchlist hit. Dismissing it clears
/// that hit; "Open Watchlist" shows the full recent-hits log.
struct WatchHitBanner: View {
    @EnvironmentObject var model: ChatModel
    @ObservedObject var watchlist: WatchlistService

    var body: some View {
        if let hit = watchlist.recentHits.first {
            HStack(spacing: 12) {
                Image(systemName: "bell.and.waves.left.and.right.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .shadow(radius: 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(hit.nick) is online")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("via \(hit.source) • \(Self.timeFmt.string(from: hit.timestamp))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Button("Open /msg") {
                    model.sendInput("/msg \(hit.nick) ")
                    watchlist.dismissHit(hit.id)
                }
                .buttonStyle(.bordered)
                .tint(.white)
                Button("Watchlist") {
                    model.showWatchlist = true
                }
                .buttonStyle(.bordered)
                .tint(.white)
                Button {
                    watchlist.dismissHit(hit.id)
                } label: {
                    Image(systemName: "xmark").foregroundStyle(.white)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                LinearGradient(colors: [Color.purple, Color.pink],
                               startPoint: .leading, endPoint: .trailing)
            )
            .overlay(Rectangle().frame(height: 1).foregroundStyle(.white.opacity(0.15)), alignment: .bottom)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()
}
