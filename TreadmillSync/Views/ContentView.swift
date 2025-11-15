import SwiftUI

struct ContentView: View {
    @EnvironmentObject var syncManager: SyncManager
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            WorkoutListView()
                .navigationTitle("Treadmill Sync")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView()
                }
        }
    }
}
