// RENDER Suite Installer
// Soft lavender + white card + dark navy aesthetic
// © ENSAMBLE AS — victoria@ensamble.no

import SwiftUI
import WebKit

// ─── COLORS (matcher RENDER-pluginen) ────────────────────────────────────────
extension Color {
    static let canvas      = Color(red: 0.055, green: 0.055, blue: 0.063)  // #0E0E10
    static let card        = Color(red: 0.090, green: 0.090, blue: 0.102)  // #17171A surface
    static let cardBehind  = Color(red: 0.122, green: 0.122, blue: 0.141)  // #1F1F24 raised
    static let ink         = Color(red: 0.937, green: 0.937, blue: 0.937)  // #EFEFEF text
    static let inkSoft     = Color(red: 0.600, green: 0.600, blue: 0.600)  // #999
    static let inkFaded    = Color(red: 0.400, green: 0.400, blue: 0.400)  // #666
    static let line        = Color(red: 0.165, green: 0.165, blue: 0.196)  // #2A2A32 border
    static let surfaceMute = Color(red: 0.075, green: 0.075, blue: 0.082)  // #131316
    static let accent      = Color(red: 0.859, green: 0.102, blue: 0.102)  // #DB1A1A red
    static let accentDim   = Color(red: 0.859, green: 0.102, blue: 0.102).opacity(0.12)
}

// ─── APP ENTRY ───────────────────────────────────────────────────────────────
@main
struct InstallerApp: App {
    var body: some Scene {
        WindowGroup("RENDER Suite Installer") {
            InstallerView()
                .frame(width: 680, height: 540)
        }
        .windowResizability(.contentSize)
    }
}

// ─── STATE ───────────────────────────────────────────────────────────────────
enum Step: Int, CaseIterable {
    case welcome, components, installing, done
}

enum InstallTaskState {
    case pending, running, success, failed(String)
}

struct InstallTask: Identifiable {
    let id = UUID()
    let label: String
    var state: InstallTaskState = .pending
}

@MainActor
class InstallerState: ObservableObject {
    @Published var step: Step = .welcome
    @Published var installPlugin: Bool = true
    @Published var installApp: Bool = true
    @Published var installTesseract: Bool = true
    @Published var tasks: [InstallTask] = []
    @Published var allDone: Bool = false
    @Published var anyFailed: Bool = false
}

// ─── ROOT VIEW ───────────────────────────────────────────────────────────────
struct InstallerView: View {
    @StateObject private var state = InstallerState()

    var body: some View {
        ZStack {
            Color.canvas.ignoresSafeArea()

            // Layered card effect — dark navy peeking behind white card
            CardStack {
                Group {
                    switch state.step {
                    case .welcome:    WelcomeScreen(state: state)
                    case .components: ComponentsScreen(state: state)
                    case .installing: InstallingScreen(state: state)
                    case .done:       DoneScreen(state: state)
                    }
                }
            }
        }
    }
}

// ─── CARD STACK (layered visual frame) ───────────────────────────────────────
struct CardStack<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ZStack {
            // Behind card (dark navy, offset)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.cardBehind)
                .frame(width: 480, height: 440)
                .offset(x: -34, y: -22)
                .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 14)

            // Front card (white, slightly offset opposite)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.card)
                .frame(width: 520, height: 460)
                .offset(x: 18, y: 12)
                .shadow(color: .black.opacity(0.10), radius: 30, x: 0, y: 18)
                .overlay(
                    content()
                        .frame(width: 520, height: 460)
                        .offset(x: 18, y: 12)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                )
        }
    }
}

// ─── WELCOME ─────────────────────────────────────────────────────────────────
struct WelcomeScreen: View {
    @ObservedObject var state: InstallerState
    @State private var showInfo = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                Spacer().frame(height: 32)

                // Brand mark
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.accent)
                        .frame(width: 6, height: 6)
                    Text("RENDER")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2.4)
                        .foregroundColor(.inkSoft)
                }

                Spacer().frame(height: 18)

                // Animation
                AnimationView(htmlName: "clapper")
                    .frame(width: 220, height: 180)

                Spacer().frame(height: 24)

                Text("Premiere multicam markers fra Teams-chats.\nKlar på under ett minutt.")
                    .font(.system(size: 14))
                    .foregroundColor(.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)

                Spacer()

                // Primary action — pill
                PillButton("Kom i gang", style: .primary) {
                    state.step = .components
                }
                .padding(.horizontal, 60)
                .padding(.bottom, 22)

                FooterText().padding(.bottom, 16)
            }

            // Info button — top right
            Button {
                showInfo.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundColor(.inkSoft)
            }
            .buttonStyle(.plain)
            .padding(14)
            .popover(isPresented: $showInfo, arrowEdge: .top) {
                AboutPopover()
            }
        }
    }
}

// ─── ABOUT POPOVER ───────────────────────────────────────────────────────────
let appVersion = "1.0 BETA"

struct AboutPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(Color.accent).frame(width: 6, height: 6)
                Text("RENDER")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.inkSoft)
                Spacer()
                Text("v\(appVersion)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.inkFaded)
            }

            Text("RENDER Suite")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.ink)

            Text("Multicam Markers (Premiere-plugin) og TeamsToCSV (Mac-app). Lager markers på multicam-klipp basert på timecodes fra Teams-meldinger.")
                .font(.system(size: 11))
                .foregroundColor(.inkSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Divider().background(Color.line)

            InfoRow(icon: "lock.shield", title: "Personvern",
                    detail: "Alt kjøres lokalt. Ingen data sendes til skyen, ingen telemetri.")
            InfoRow(icon: "checkmark.shield", title: "Signert og notarisert",
                    detail: "Godkjent av Apple. Trygt å installere.")
            InfoRow(icon: "envelope", title: "Hjelp og kontakt",
                    detail: "victoria@ensamble.no")

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                Text("© ENSAMBLE AS")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.inkFaded)
                Spacer()
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(Color.card)
    }
}

// ─── COMPONENTS ──────────────────────────────────────────────────────────────
struct ComponentsScreen: View {
    @ObservedObject var state: InstallerState
    @State private var showTesseractInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 36)

            // Title
            Text("Velg det du trenger.")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.ink)
                .tracking(-0.4)
                .padding(.horizontal, 36)

            Text("Du kan alltid endre dette senere.")
                .font(.system(size: 12))
                .foregroundColor(.inkSoft)
                .padding(.horizontal, 36)
                .padding(.top, 4)

            Spacer().frame(height: 22)

            VStack(spacing: 8) {
                ComponentRow(
                    isOn: $state.installPlugin,
                    title: "Multicam Markers",
                    detail: "Premiere Pro-plugin",
                    required: true
                )
                ComponentRow(
                    isOn: $state.installApp,
                    title: "TeamsToCSV",
                    detail: "Konverterer Teams-screenshots til CSV"
                )
            }
            .padding(.horizontal, 32)

            // Subtle note about auto-installed dependencies
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                Text("Tesseract OCR installeres automatisk for best resultat.")
                    .font(.system(size: 11))
                Button {
                    showTesseractInfo.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showTesseractInfo, arrowEdge: .top) {
                    TesseractInfoPopover()
                }
            }
            .foregroundColor(.inkFaded)
            .padding(.horizontal, 36)
            .padding(.top, 14)

            Spacer()

            HStack(spacing: 10) {
                PillButton("← Tilbake", style: .ghost) { state.step = .welcome }
                Spacer()
                PillButton("Installer →", style: .primary) {
                    state.tasks = buildTaskList(state: state)
                    state.step = .installing
                    Task { await runInstall(state: state) }
                }
                .disabled(!state.installPlugin && !state.installApp)
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 22)

            FooterText().padding(.bottom, 16)
        }
    }
}

struct ComponentRow: View {
    @Binding var isOn: Bool
    let title: String
    let detail: String
    var required: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Title block (left)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.ink)
                    if required {
                        Text("ALLTID AKTIV")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(0.6)
                            .foregroundColor(.inkFaded)
                    }
                }
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(.inkSoft)
                    .lineLimit(1)
            }
            Spacer()

            // Right: toggle or "Always active" indicator
            if required {
                ZStack {
                    Capsule()
                        .fill(Color.accent)
                        .frame(width: 36, height: 20)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                        .offset(x: 8)
                }
            } else {
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(SoftSwitchStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.surfaceMute)
        )
        .contentShape(Rectangle())
        .onTapGesture { if !required { isOn.toggle() } }
    }
}

// Custom subtle toggle — fits the navy/white aesthetic
struct SoftSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Capsule()
                .fill(configuration.isOn ? Color.accent : Color.line)
                .frame(width: 36, height: 20)
            Circle()
                .fill(Color.white)
                .frame(width: 14, height: 14)
                .offset(x: configuration.isOn ? 8 : -8)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isOn)
        .onTapGesture { configuration.isOn.toggle() }
    }
}

// ─── INSTALLING ──────────────────────────────────────────────────────────────
struct InstallingScreen: View {
    @ObservedObject var state: InstallerState

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 28)

            AnimationView(htmlName: "timeline")
                .frame(width: 200, height: 110)

            Text("Installerer...")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.ink)
                .padding(.top, 8)

            Text("Ett øyeblikk.")
                .font(.system(size: 12))
                .foregroundColor(.inkSoft)
                .padding(.top, 2)

            Spacer().frame(height: 22)

            ScrollView {
                VStack(spacing: 3) {
                    ForEach(state.tasks) { task in
                        TaskRow(task: task)
                    }
                }
                .padding(.horizontal, 36)
            }

            Spacer()

            if state.allDone {
                PillButton(state.anyFailed ? "Fortsett" : "Fortsett →", style: .primary) {
                    state.step = .done
                }
                .padding(.horizontal, 60)
                .padding(.bottom, 22)
            }

            FooterText().padding(.bottom, 16)
        }
    }
}

struct TaskRow: View {
    let task: InstallTask

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
            Text(task.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.ink)
            Spacer()
            if case .failed(let msg) = task.state {
                Text(msg)
                    .font(.system(size: 9))
                    .foregroundColor(.accent)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.surfaceMute)
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch task.state {
        case .pending:
            Circle()
                .strokeBorder(Color.inkFaded.opacity(0.4), lineWidth: 1.5)
                .frame(width: 12, height: 12)
        case .running:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.55)
                .frame(width: 12, height: 12)
        case .success:
            ZStack {
                Circle()
                    .fill(Color.accent)
                    .frame(width: 12, height: 12)
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white)
            }
        case .failed:
            ZStack {
                Circle()
                    .fill(Color.accent)
                    .frame(width: 12, height: 12)
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }
}

// ─── DONE ────────────────────────────────────────────────────────────────────
struct DoneScreen: View {
    @ObservedObject var state: InstallerState

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 56)

            // Big iconic checkmark
            ZStack {
                Circle()
                    .fill(Color.accent)
                    .frame(width: 76, height: 76)
                Image(systemName: state.anyFailed ? "exclamationmark" : "checkmark")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
            }

            Spacer().frame(height: 28)

            Text(state.anyFailed ? "Ferdig med advarsler." : "Klar til bruk.")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.ink)
                .tracking(-0.4)

            Spacer().frame(height: 12)

            Text(nextStepsText)
                .font(.system(size: 13))
                .foregroundColor(.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 50)

            Spacer()

            PillButton("Lukk", style: .primary) {
                NSApplication.shared.terminate(nil)
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 22)

            FooterText().padding(.bottom, 16)
        }
    }

    private var nextStepsText: String {
        if state.anyFailed {
            return "Noen komponenter ble ikke installert.\nSe FAQ.txt eller kontakt victoria@ensamble.no."
        }
        return "Start Premiere Pro på nytt for å aktivere pluginen.\nÅpne Window → Extensions → RENDER – Multicam Markers."
    }
}

// ─── PILL BUTTON ─────────────────────────────────────────────────────────────
enum PillButtonStyle { case primary, ghost }

struct PillButton: View {
    let label: String
    let style: PillButtonStyle
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    init(_ label: String, style: PillButtonStyle = .primary, action: @escaping () -> Void) {
        self.label = label
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(textColor)
                .frame(maxWidth: style == .primary ? .infinity : nil)
                .padding(.horizontal, style == .primary ? 0 : 18)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(backgroundColor)
                )
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: return isEnabled ? Color.accent : Color.line
        case .ghost:   return Color.clear
        }
    }
    private var textColor: Color {
        switch style {
        case .primary: return .white
        case .ghost:   return .ink
        }
    }
}

// ─── TESSERACT INFO POPOVER ──────────────────────────────────────────────────
struct TesseractInfoPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.viewfinder")
                    .foregroundColor(.accent)
                Text("Hva er Tesseract?")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.ink)
            }

            Text("Tesseract er en åpen kildekode OCR-motor (Optical Character Recognition) som leser tekst fra bilder.")
                .font(.system(size: 11))
                .foregroundColor(.inkSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Divider().background(Color.line)

            InfoRow(icon: "lock.shield", title: "100% lokalt",
                    detail: "Ingenting sendes ut av Macen din. Ingen API-er, ingen telemetri.")
            InfoRow(icon: "globe.europe.africa", title: "Norsk språkpakke",
                    detail: "Mye bedre på æ/ø/å enn macOS sin innebygde Apple Vision.")
            InfoRow(icon: "shippingbox", title: "Installeres via Homebrew",
                    detail: "Standard pakkebehandler for Mac (brew.sh). Kan kreve Mac-passord ved første gangs install.")
        }
        .padding(16)
        .frame(width: 320)
        .background(Color.card)
    }
}

struct InfoRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.accent)
                .frame(width: 14, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.ink)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(.inkSoft)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// ─── FOOTER ──────────────────────────────────────────────────────────────────
struct FooterText: View {
    var body: some View {
        Text("ENSAMBLE AS  ·  victoria@ensamble.no")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(1.0)
            .foregroundColor(.inkFaded)
    }
}

// ─── HTML ANIMATION VIA WKWEBVIEW ────────────────────────────────────────────
struct AnimationView: NSViewRepresentable {
    let htmlName: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webview = WKWebView(frame: .zero, configuration: config)
        webview.setValue(false, forKey: "drawsBackground")
        webview.layer?.backgroundColor = NSColor.clear.cgColor

        if let url = Bundle.main.url(forResource: htmlName, withExtension: "html") {
            webview.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webview.loadHTMLString("<html><body style='background:transparent'></body></html>", baseURL: nil)
        }
        return webview
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// ─── INSTALL LOGIC (placeholders for now) ────────────────────────────────────
@MainActor
func buildTaskList(state: InstallerState) -> [InstallTask] {
    var tasks: [InstallTask] = []
    if state.installPlugin {
        tasks.append(InstallTask(label: "Aktiver PlayerDebugMode i Premiere"))
        tasks.append(InstallTask(label: "Installer Multicam Markers-plugin"))
    }
    if state.installApp {
        tasks.append(InstallTask(label: "Installer TeamsToCSV.app"))
    }
    if state.installTesseract {
        tasks.append(InstallTask(label: "Sjekk Homebrew"))
        tasks.append(InstallTask(label: "Installer Tesseract"))
    }
    // Verification (alltid på slutten)
    tasks.append(InstallTask(label: "Verifiser installasjon"))
    return tasks
}

@MainActor
private func setTask(_ state: InstallerState, _ idx: Int, _ s: InstallTaskState) {
    if idx < state.tasks.count { state.tasks[idx].state = s }
}

func runInstall(state: InstallerState) async {
    let plugin = await MainActor.run { state.installPlugin }
    let app    = await MainActor.run { state.installApp }
    let tess   = await MainActor.run { state.installTesseract }

    var i = 0
    var brewPath: String? = findBrewBinary()

    // ── Plugin ──
    if plugin {
        // 1. PlayerDebugMode
        let idx1 = i
        await MainActor.run { setTask(state, idx1, .running) }
        let dbgOK = await activatePlayerDebugMode()
        await MainActor.run {
            setTask(state, idx1, dbgOK ? .success : .failed("defaults write feilet"))
        }
        i += 1

        // 2. Plugin-filer
        let idx2 = i
        await MainActor.run { setTask(state, idx2, .running) }
        let pluginResult = await installPluginFiles()
        await MainActor.run {
            switch pluginResult {
            case .success:           setTask(state, idx2, .success)
            case .failure(let msg):  setTask(state, idx2, .failed(msg))
            }
        }
        i += 1
    }

    // ── TeamsToCSV.app ──
    if app {
        let idx = i
        await MainActor.run { setTask(state, idx, .running) }
        let appResult = await installTeamsToCSV()
        await MainActor.run {
            switch appResult {
            case .success:           setTask(state, idx, .success)
            case .failure(let msg):  setTask(state, idx, .failed(msg))
            }
        }
        i += 1
    }

    // ── Tesseract ──
    if tess {
        // Sjekk/installer Brew
        let idxBrew = i
        await MainActor.run { setTask(state, idxBrew, .running) }
        if brewPath == nil {
            let installedBrew = await installHomebrew()
            if installedBrew { brewPath = findBrewBinary() }
        }
        let brewFound = brewPath != nil
        await MainActor.run {
            setTask(state, idxBrew, brewFound ? .success : .failed("Homebrew ikke tilgjengelig"))
        }
        i += 1

        // Tesseract via brew
        let idxTess = i
        await MainActor.run { setTask(state, idxTess, .running) }
        if let brew = brewPath {
            let tessResult = await installTesseract(brewPath: brew)
            await MainActor.run {
                switch tessResult {
                case .success:           setTask(state, idxTess, .success)
                case .failure(let msg):  setTask(state, idxTess, .failed(msg))
                }
            }
        } else {
            await MainActor.run { setTask(state, idxTess, .failed("Hopper over — brew mangler")) }
        }
        i += 1
    }

    // ── Verifisering ──
    let idxVerify = i
    await MainActor.run { setTask(state, idxVerify, .running) }
    let result = await runVerification(state: state)
    await MainActor.run {
        setTask(state, idxVerify, result.allOK ? .success : .failed(result.summary))
    }

    // ── Ferdig ──
    await MainActor.run {
        state.allDone = true
        state.anyFailed = state.tasks.contains { t in
            if case .failed = t.state { return true }
            return false
        }
    }
}

// ─── REAL INSTALL HELPERS ────────────────────────────────────────────────────
enum InstallResult {
    case success
    case failure(String)
}

func findBrewBinary() -> String? {
    let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}

func runShell(_ executablePath: String, _ args: [String]) -> (status: Int32, stdout: String, stderr: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: executablePath)
    p.arguments = args
    let outPipe = Pipe()
    let errPipe = Pipe()
    p.standardOutput = outPipe
    p.standardError = errPipe
    do {
        try p.run()
        p.waitUntilExit()
        let out = (try? outPipe.fileHandleForReading.readToEnd()).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let err = (try? errPipe.fileHandleForReading.readToEnd()).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return (p.terminationStatus, out, err)
    } catch {
        return (-1, "", String(describing: error))
    }
}

func runOsascript(_ script: String) -> (status: Int32, output: String) {
    let result = runShell("/usr/bin/osascript", ["-e", script])
    return (result.status, result.stdout + result.stderr)
}

func activatePlayerDebugMode() async -> Bool {
    await Task.detached(priority: .userInitiated) {
        for v in 9...13 {
            let r = runShell("/usr/bin/defaults", ["write", "com.adobe.CSXS.\(v)", "PlayerDebugMode", "1"])
            if r.status != 0 {
                return false
            }
        }
        return true
    }.value
}

func installPluginFiles() async -> InstallResult {
    return await Task.detached(priority: .userInitiated) {
        guard let resURL = Bundle.main.resourceURL else {
            return InstallResult.failure("Mangler bundle-ressurser")
        }
        let extID  = "com.render.teamsmc2"
        let srcDir = resURL.appendingPathComponent("extension/\(extID)")
        guard FileManager.default.fileExists(atPath: srcDir.path) else {
            return .failure("Plugin-filer ikke i app-bundle")
        }
        let home   = FileManager.default.homeDirectoryForCurrentUser
        let cepDir = home.appendingPathComponent("Library/Application Support/Adobe/CEP/extensions")
        let dstDir = cepDir.appendingPathComponent(extID)

        do {
            try FileManager.default.createDirectory(at: cepDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dstDir.path) {
                try FileManager.default.removeItem(at: dstDir)
            }
            try FileManager.default.copyItem(at: srcDir, to: dstDir)
        } catch {
            return .failure("Kopiering feilet: \(error.localizedDescription)")
        }
        // Strip quarantine
        _ = runShell("/usr/bin/xattr", ["-cr", dstDir.path])
        return .success
    }.value
}

func installTeamsToCSV() async -> InstallResult {
    return await Task.detached(priority: .userInitiated) {
        guard let resURL = Bundle.main.resourceURL else {
            return InstallResult.failure("Mangler bundle-ressurser")
        }
        let srcApp = resURL.appendingPathComponent("TeamsToCSV.app")
        guard FileManager.default.fileExists(atPath: srcApp.path) else {
            return .failure("TeamsToCSV.app ikke i bundle")
        }
        let dstPath = "/Applications/TeamsToCSV.app"

        // Forsøk vanlig kopi (uten admin) først
        if FileManager.default.fileExists(atPath: dstPath) {
            let r1 = runShell("/bin/rm", ["-rf", dstPath])
            if r1.status != 0 {
                // Trenger admin — bruk osascript
                let script = "do shell script \"rm -rf '\(dstPath)' && cp -R '\(srcApp.path)' /Applications/\" with administrator privileges"
                let r2 = runOsascript(script)
                if r2.status != 0 {
                    return .failure("Admin-tilgang ble nektet")
                }
                _ = runShell("/usr/bin/xattr", ["-dr", "com.apple.quarantine", dstPath])
                return .success
            }
        }
        let cpRes = runShell("/bin/cp", ["-R", srcApp.path, dstPath])
        if cpRes.status != 0 {
            // Fallback til admin
            let script = "do shell script \"cp -R '\(srcApp.path)' /Applications/\" with administrator privileges"
            let r2 = runOsascript(script)
            if r2.status != 0 {
                return .failure("Kopiering til /Applications feilet")
            }
        }
        _ = runShell("/usr/bin/xattr", ["-dr", "com.apple.quarantine", dstPath])
        return .success
    }.value
}

func installHomebrew() async -> Bool {
    return await Task.detached(priority: .userInitiated) {
        // Brews offisielle install-script. Bruker osascript så vi får native passord-dialog.
        let installCmd = "/bin/bash -c \\\"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\\\""
        let script = "do shell script \"\(installCmd) </dev/null 2>&1\" with administrator privileges"
        let r = runOsascript(script)
        return r.status == 0 && findBrewBinary() != nil
    }.value
}

func installTesseract(brewPath: String) async -> InstallResult {
    return await Task.detached(priority: .userInitiated) {
        // Sjekk om allerede installert
        let check = runShell("/bin/bash", ["-c", "command -v tesseract"])
        if check.status == 0 && !check.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return InstallResult.success
        }
        // brew install tesseract tesseract-lang
        let r = runShell(brewPath, ["install", "tesseract", "tesseract-lang"])
        if r.status == 0 {
            return .success
        }
        let firstLine = r.stderr.split(separator: "\n").first.map(String.init) ?? "ukjent feil"
        return .failure(String(firstLine.prefix(60)))
    }.value
}

// ─── VERIFICATION ────────────────────────────────────────────────────────────
struct VerificationResult {
    let allOK: Bool
    let summary: String
    let details: [String]
}

func runVerification(state: InstallerState) async -> VerificationResult {
    var failures: [String] = []
    var details: [String] = []

    let needsPlugin    = await MainActor.run { state.installPlugin }
    let needsApp       = await MainActor.run { state.installApp }
    let needsTesseract = await MainActor.run { state.installTesseract }

    let home = FileManager.default.homeDirectoryForCurrentUser.path

    // 1. Plugin-files
    if needsPlugin {
        let extDir = "\(home)/Library/Application Support/Adobe/CEP/extensions/com.render.teamsmc2"
        let required = [
            "\(extDir)/CSXS/manifest.xml",
            "\(extDir)/client/index.html",
            "\(extDir)/client/lib/CSInterface.js",
            "\(extDir)/host/host.jsx"
        ]
        for path in required {
            if !FileManager.default.fileExists(atPath: path) {
                failures.append("Plugin mangler: \(URL(fileURLWithPath: path).lastPathComponent)")
            }
        }
        // Verifiser at host.jsx har JSON-polyfill
        if let content = try? String(contentsOfFile: "\(extDir)/host/host.jsx"),
           !content.contains("JSON POLYFILL") {
            failures.append("host.jsx mangler JSON-polyfill (kreves for Premiere 26+)")
        }
        details.append("Plugin: \(failures.isEmpty ? "OK" : "FEIL")")
    }

    // 2. TeamsToCSV.app
    if needsApp {
        let appPath = "/Applications/TeamsToCSV.app"
        if !FileManager.default.fileExists(atPath: appPath) {
            failures.append("TeamsToCSV.app ikke i /Applications")
        } else {
            // Sjekk at binæren er kjørbar
            let bin = "\(appPath)/Contents/MacOS/TeamsToCSV"
            if !FileManager.default.isExecutableFile(atPath: bin) {
                failures.append("TeamsToCSV-binæren er ikke kjørbar")
            }
        }
        details.append("App: \(failures.isEmpty ? "OK" : "FEIL")")
    }

    // 3. Tesseract
    if needsTesseract {
        let candidates = ["/opt/homebrew/bin/tesseract", "/usr/local/bin/tesseract"]
        let found = candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        if found == nil {
            failures.append("Tesseract ikke funnet — appen vil bruke Apple Vision")
        } else {
            // Sjekk at den faktisk svarer på --version
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: found!)
            proc.arguments = ["--version"]
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus != 0 {
                    failures.append("Tesseract installert men svarer ikke korrekt")
                }
            } catch {
                failures.append("Kunne ikke kjøre Tesseract: \(error.localizedDescription)")
            }
        }
        details.append("Tesseract: \(failures.isEmpty ? "OK" : "FEIL")")
    }

    if failures.isEmpty {
        return VerificationResult(allOK: true, summary: "Alt OK", details: details)
    } else {
        let summary = failures.count == 1 ? failures[0] : "\(failures.count) feil"
        return VerificationResult(allOK: false, summary: summary, details: failures)
    }
}
