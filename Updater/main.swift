// RENDER Markers Oppdaterer — Patch 1 (auto-run update app)
// © ENSAMBLE AS — victoria@ensamble.no

import SwiftUI
import AppKit
import WebKit

let patchLabel = "v1.23"

extension Color {
    static let canvas      = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let card        = Color.white
    static let cardBehind  = Color(red: 0.18, green: 0.18, blue: 0.20)
    static let ink         = Color(red: 0.04, green: 0.04, blue: 0.04)
    static let inkSoft     = Color(red: 0.36, green: 0.36, blue: 0.39)
    static let inkOnDark   = Color.white
    static let inkOnDarkSoft = Color(red: 0.65, green: 0.65, blue: 0.70)
    static let inkOnDarkFaded = Color(red: 0.45, green: 0.45, blue: 0.50)
    static let accent      = Color(red: 0.859, green: 0.102, blue: 0.102)
}

@main
struct UpdaterApp: App {
    var body: some Scene {
        WindowGroup("Oppdaterer") {
            UpdaterView()
                .frame(width: 460, height: 340)
        }
        .windowResizability(.contentSize)
    }
}

enum StepStatus {
    case pending, running, success, failed(String)
}

struct UpdateStep: Identifiable {
    let id = UUID()
    let label: String
    var status: StepStatus = .pending
}

@MainActor
class UpdaterState: ObservableObject {
    @Published var steps: [UpdateStep] = [
        UpdateStep(label: "Fjerner gammel versjon"),
        UpdateStep(label: "Installerer Premiere-plugin"),
        UpdateStep(label: "Installerer TeamsToCSV-app"),
        UpdateStep(label: "Verifiserer oppdatering")
    ]
    @Published var done = false
    @Published var anyFailed = false
    @Published var autoCloseIn: Int = 3
}

struct UpdaterView: View {
    @StateObject private var state = UpdaterState()

    var body: some View {
        ZStack {
            Color.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Circle().fill(Color.accent).frame(width: 7, height: 7)
                    Text("RENDER MARKERS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2.2)
                        .foregroundColor(.inkOnDarkSoft)
                    Spacer()
                    Text(patchLabel)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(0.6)
                        .foregroundColor(.inkOnDarkFaded)
                }
                .padding(20)

                Spacer().frame(height: 6)

                // Tittel
                Text(state.done
                     ? (state.anyFailed ? "Noe gikk galt" : "Ferdig oppdatert")
                     : "Oppdaterer…")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.inkOnDark)
                    .tracking(-0.3)

                Spacer().frame(height: 18)

                // Steg-liste
                VStack(spacing: 8) {
                    ForEach(state.steps) { step in
                        StepRow(step: step)
                    }
                }
                .padding(.horizontal, 32)

                Spacer()

                // Footer-tekst
                if state.done && !state.anyFailed {
                    Text("Lukkes automatisk om \(state.autoCloseIn) sek")
                        .font(.system(size: 11))
                        .foregroundColor(.inkOnDarkSoft)
                        .padding(.bottom, 18)
                } else if state.done && state.anyFailed {
                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Text("Lukk")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(Capsule().fill(Color.accent))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 60)
                    .padding(.bottom, 18)
                } else {
                    Text("ENSAMBLE AS  ·  victoria@ensamble.no")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(1.0)
                        .foregroundColor(.inkOnDarkFaded)
                        .padding(.bottom, 18)
                }
            }
        }
        .task {
            await runUpdate(state: state)
        }
    }
}

struct StepRow: View {
    let step: UpdateStep

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
            Text(step.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.inkOnDark)
            Spacer()
            if case .failed(let msg) = step.status {
                Text(msg)
                    .font(.system(size: 9))
                    .foregroundColor(.accent)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch step.status {
        case .pending:
            Circle().strokeBorder(Color.inkOnDarkFaded.opacity(0.5), lineWidth: 1.5)
                .frame(width: 13, height: 13)
        case .running:
            ProgressView().controlSize(.small).scaleEffect(0.55)
                .frame(width: 13, height: 13)
        case .success:
            ZStack {
                Circle().fill(Color.accent).frame(width: 13, height: 13)
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white)
            }
        case .failed:
            ZStack {
                Circle().fill(Color.accent).frame(width: 13, height: 13)
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }
}

// ─── UPDATE LOGIC ────────────────────────────────────────────────────────────
@MainActor
private func setStep(_ state: UpdaterState, _ idx: Int, _ s: StepStatus) {
    if idx < state.steps.count { state.steps[idx].status = s }
}

func runUpdate(state: UpdaterState) async {
    // Steg 1: fjern gammel
    await MainActor.run { setStep(state, 0, .running) }
    try? await Task.sleep(nanoseconds: 500_000_000)
    await Task.detached(priority: .userInitiated) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let extDir = home.appendingPathComponent("Library/Application Support/Adobe/CEP/extensions/com.render.teamsmc2")
        try? FileManager.default.removeItem(at: extDir)
        try? FileManager.default.removeItem(atPath: "/Applications/TeamsToCSV.app")
    }.value
    await MainActor.run { setStep(state, 0, .success) }

    // Steg 2: plugin
    await MainActor.run { setStep(state, 1, .running) }
    try? await Task.sleep(nanoseconds: 400_000_000)
    let pluginResult = await installPlugin()
    await MainActor.run {
        switch pluginResult {
        case .success:           setStep(state, 1, .success)
        case .failure(let msg):  setStep(state, 1, .failed(msg))
        }
    }

    // Steg 3: app
    await MainActor.run { setStep(state, 2, .running) }
    try? await Task.sleep(nanoseconds: 400_000_000)
    let appResult = await installApp()
    await MainActor.run {
        switch appResult {
        case .success:           setStep(state, 2, .success)
        case .failure(let msg):  setStep(state, 2, .failed(msg))
        }
    }

    // Steg 4: verify
    await MainActor.run { setStep(state, 3, .running) }
    try? await Task.sleep(nanoseconds: 300_000_000)
    let verifyOK = await verify()
    await MainActor.run {
        setStep(state, 3, verifyOK ? .success : .failed("Noen filer mangler"))
    }

    // Ferdig
    await MainActor.run {
        state.done = true
        state.anyFailed = state.steps.contains { s in
            if case .failed = s.status { return true } else { return false }
        }
    }

    // Auto-lukk hvis alt OK
    if !(await state.anyFailed) {
        for sec in stride(from: 3, through: 1, by: -1) {
            await MainActor.run { state.autoCloseIn = sec }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        await MainActor.run { NSApplication.shared.terminate(nil) }
    }
}

enum UpdateResult {
    case success
    case failure(String)
}

func installPlugin() async -> UpdateResult {
    return await Task.detached(priority: .userInitiated) {
        guard let resURL = Bundle.main.resourceURL else {
            return UpdateResult.failure("Mangler bundle")
        }
        let srcDir = resURL.appendingPathComponent("extension/com.render.teamsmc2")
        let home   = FileManager.default.homeDirectoryForCurrentUser
        let cepDir = home.appendingPathComponent("Library/Application Support/Adobe/CEP/extensions")
        let dstDir = cepDir.appendingPathComponent("com.render.teamsmc2")
        do {
            try FileManager.default.createDirectory(at: cepDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dstDir.path) {
                try FileManager.default.removeItem(at: dstDir)
            }
            try FileManager.default.copyItem(at: srcDir, to: dstDir)
        } catch {
            return .failure("Kopiering feilet")
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        p.arguments = ["-cr", dstDir.path]
        try? p.run(); p.waitUntilExit()
        return .success
    }.value
}

func installApp() async -> UpdateResult {
    return await Task.detached(priority: .userInitiated) {
        guard let resURL = Bundle.main.resourceURL else {
            return UpdateResult.failure("Mangler bundle")
        }
        let srcApp = resURL.appendingPathComponent("TeamsToCSV.app")
        let dstPath = "/Applications/TeamsToCSV.app"

        if FileManager.default.fileExists(atPath: dstPath) {
            try? FileManager.default.removeItem(atPath: dstPath)
        }
        let cp = Process()
        cp.executableURL = URL(fileURLWithPath: "/bin/cp")
        cp.arguments = ["-R", srcApp.path, dstPath]
        cp.standardError = Pipe()
        do {
            try cp.run(); cp.waitUntilExit()
            if cp.terminationStatus != 0 {
                // Fallback til admin via osascript
                let script = "do shell script \"rm -rf '\(dstPath)' && cp -R '\(srcApp.path)' /Applications/\" with administrator privileges"
                let os = Process()
                os.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                os.arguments = ["-e", script]
                os.standardOutput = Pipe()
                os.standardError = Pipe()
                try os.run(); os.waitUntilExit()
                if os.terminationStatus != 0 {
                    return .failure("Admin nektet")
                }
            }
        } catch {
            return .failure("Kunne ikke kopiere")
        }
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", dstPath]
        try? xattr.run(); xattr.waitUntilExit()
        return .success
    }.value
}

func verify() async -> Bool {
    return await Task.detached(priority: .userInitiated) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let extDir = home.appendingPathComponent("Library/Application Support/Adobe/CEP/extensions/com.render.teamsmc2")
        let mustExist = [
            extDir.appendingPathComponent("CSXS/manifest.xml"),
            extDir.appendingPathComponent("client/index.html"),
            extDir.appendingPathComponent("host/host.jsx"),
            URL(fileURLWithPath: "/Applications/TeamsToCSV.app")
        ]
        for u in mustExist {
            if !FileManager.default.fileExists(atPath: u.path) { return false }
        }
        return true
    }.value
}
