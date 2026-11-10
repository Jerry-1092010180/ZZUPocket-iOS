import SwiftUI

@main
struct PocketApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: PocketModel
    @StateObject private var background: CampusBackgroundRefresh

    init() {
        let model = PocketModel()
        _model = StateObject(wrappedValue: model)
        _background = StateObject(wrappedValue: CampusBackgroundRefresh(model: model))
    }

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model).environmentObject(background)
                .task { await background.schedule() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active || phase == .background { Task { await background.schedule() } }
                }
                .onChange(of: model.loggedIn) { _, _ in Task { await background.schedule() } }
        }
        .backgroundTask(.appRefresh(CampusBackgroundRefresh.identifier)) {
            await background.run()
        }
    }
}
