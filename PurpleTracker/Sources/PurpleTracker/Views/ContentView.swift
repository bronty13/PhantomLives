import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            RunningTimerBanner()
            NavigationSplitView {
                SidebarView()
                    .frame(minWidth: 220)
            } content: {
                switch app.sidebarSection {
                case .weeklyTimesheet, .today, .timeDashboard, .analytics, .capacity:
                    // Tools / dashboards take over both columns; the middle
                    // column collapses to nothing so they get full width.
                    Color.clear.frame(width: 0)
                case .trash:
                    TrashListView()
                        .frame(minWidth: 320)
                default:
                    MatterListView()
                        .frame(minWidth: 320)
                }
            } detail: {
                switch app.sidebarSection {
                case .weeklyTimesheet:
                    WeeklyTimesheetView()
                case .today:
                    TodayDashboardView()
                case .timeDashboard:
                    TimeDashboardView()
                case .analytics:
                    AnalyticsDashboardView()
                case .capacity:
                    CapacityDashboardView()
                case .trash:
                    TrashView()
                default:
                    if let m = app.selectedMatter {
                        MatterDetailView(matter: m)
                    } else {
                        ContentUnavailableView(
                            "No Matter Selected",
                            systemImage: "doc.text",
                            description: Text("Choose a Matter from the list, or press ⌘N to create one.")
                        )
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: app.timer.activeMatterId)
        .alert("Error",
               isPresented: Binding(
                get: { app.errorMessage != nil },
                set: { if !$0 { app.errorMessage = nil } }
               )) {
            Button("OK", role: .cancel) { app.errorMessage = nil }
        } message: {
            Text(app.errorMessage ?? "")
        }
    }
}
