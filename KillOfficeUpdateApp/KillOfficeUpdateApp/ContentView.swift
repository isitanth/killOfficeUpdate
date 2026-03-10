import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()

    var body: some View {
        VStack(spacing: 20) {
            statusHeader
            actionButtons
            logViewer
            cleanUpButton
            notificationsToggle
            statusBar
        }
        .padding()
        .frame(width: 400, height: 580)
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        VStack(spacing: 4) {
            Image(systemName: viewModel.isRunning ? "checkmark.shield.fill" : "xmark.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(viewModel.isRunning ? .green : .red)
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))

            Text("Microsoft Update Blocker")
                .font(.headline)

            Text(viewModel.isRunning ? "Active" : "Inactive")
                .font(.subheadline)
                .foregroundStyle(viewModel.isRunning ? .green : .secondary)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                actionButton(
                    title: "Install", icon: "arrow.down.circle",
                    action: { viewModel.install() },
                    disabled: viewModel.isInstalled || viewModel.isBusy
                )
                actionButton(
                    title: "Uninstall", icon: "trash.circle",
                    action: { viewModel.uninstall() },
                    disabled: !viewModel.isInstalled || viewModel.isBusy
                )
            }

            GridRow {
                actionButton(
                    title: "Enable", icon: "play.circle",
                    action: { viewModel.enable() },
                    disabled: !viewModel.isInstalled || viewModel.isEnabled || viewModel.isBusy
                )
                actionButton(
                    title: "Disable", icon: "pause.circle",
                    action: { viewModel.disable() },
                    disabled: !viewModel.isInstalled || !viewModel.isEnabled || viewModel.isBusy
                )
            }
        }
        .padding()
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
    }

    // MARK: - Log Viewer

    private var logViewer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Recent Activity", systemImage: "doc.text")
                    .font(.subheadline.bold())

                Spacer()

                Button {
                    viewModel.loadLogEntries()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .controlSize(.small)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if viewModel.logEntries.isEmpty {
                        Text("No log entries yet")
                            .foregroundStyle(.secondary)
                            .font(.system(.caption, design: .monospaced))
                    } else {
                        ForEach(viewModel.logEntries, id: \.self) { entry in
                            Text(entry)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 160)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    // MARK: - Clean Up Button

    private var cleanUpButton: some View {
        HStack {
            Spacer()
            Button {
                viewModel.cleanUp()
            } label: {
                Label("Clean Up", systemImage: "eraser.line.dashed")
                    .font(.caption)
            }
            .controlSize(.small)
            .disabled(!viewModel.isInstalled || viewModel.isBusy)
        }
    }

    // MARK: - Notifications Toggle

    private var notificationsToggle: some View {
        Toggle(isOn: Binding(
            get: { viewModel.isNotifyEnabled },
            set: { _ in viewModel.toggleNotifications() }
        )) {
            Label("Kill Notifications", systemImage: "bell.badge")
                .font(.caption)
        }
        .controlSize(.small)
        .toggleStyle(.switch)
        .disabled(!viewModel.isInstalled || viewModel.isBusy)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        Text(viewModel.statusMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private func actionButton(
        title: String,
        icon: String,
        action: @escaping () -> Void,
        disabled: Bool
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .disabled(disabled)
    }
}

#Preview {
    ContentView()
}
