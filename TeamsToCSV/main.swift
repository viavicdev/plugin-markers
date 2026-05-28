// TeamsToCSV — drag-and-drop SwiftUI app for OCR-ing Teams screenshots to CSV.
// READ-ONLY: source PNG is never modified.

import SwiftUI
import Vision
import AppKit
import CoreImage
import UniformTypeIdentifiers
import WebKit
import CryptoKit

// ─── COLORS (soft canvas + svevende kort med skygge) ─────────────────────────
extension Color {
    // GLM-5 cool whites
    static let bgPrimary   = Color(red: 0.973, green: 0.976, blue: 0.988) // #F8F9FC
    static let bgSecondary = Color(red: 0.933, green: 0.945, blue: 0.965) // #EEF1F6
    static let canvas      = Color(red: 0.973, green: 0.976, blue: 0.988) // alias = bgPrimary

    // Glass surfaces
    static let glassBg     = Color.white.opacity(0.72)
    static let glassBgEl   = Color.white.opacity(0.88)
    static let glassBgSub  = Color.white.opacity(0.65)
    static let glassBorder = Color.white.opacity(0.60)
    static let glassBorderSub = Color.white.opacity(0.40)

    // Text
    static let ink         = Color(red: 0.102, green: 0.114, blue: 0.137) // #1A1D23
    static let inkSoft     = Color(red: 0.420, green: 0.447, blue: 0.502) // #6B7280
    static let inkFaded    = Color(red: 0.612, green: 0.639, blue: 0.686) // #9CA3AF
    static let inkMuted    = Color(red: 0.769, green: 0.788, blue: 0.831) // #C4C9D4
    static let divider     = Color(red: 0.580, green: 0.639, blue: 0.722).opacity(0.20)

    // Card
    static let card        = Color.white
    static let cardBehind  = Color(red: 0.93, green: 0.93, blue: 0.94)
    static let line        = Color(red: 0.580, green: 0.639, blue: 0.722).opacity(0.20)
    static let surfaceMute = Color(red: 0.97, green: 0.97, blue: 0.97)

    // Brand (red gradient pair)
    static let brandAccent      = Color(red: 0.859, green: 0.102, blue: 0.102) // #DB1A1A
    static let brandAccentHover = Color(red: 0.725, green: 0.082, blue: 0.082) // #B91515
    static let brandAccentDim   = Color(red: 0.859, green: 0.102, blue: 0.102).opacity(0.08)
    static let brandAccentMed   = Color(red: 0.859, green: 0.102, blue: 0.102).opacity(0.14)
    static let brandAccentGlow  = Color(red: 0.859, green: 0.102, blue: 0.102).opacity(0.15)

    // Indigo (subtle bg accent only)
    static let indigoBgTint = Color(red: 0.388, green: 0.400, blue: 0.945) // #6366F1

    // Warn / Truncated
    static let warnBorder = Color(red: 0.961, green: 0.620, blue: 0.043)   // #F59E0B (Note border)
    static let warnBg     = Color(red: 0.961, green: 0.620, blue: 0.043).opacity(0.08)
    static let dangerRed  = Color(red: 0.863, green: 0.149, blue: 0.149)   // #DC2626 (truncated)
    static let dangerBg   = Color(red: 0.937, green: 0.267, blue: 0.267).opacity(0.10)

    // Aliases for legacy callers
    static let inkOnDark      = Color(red: 0.102, green: 0.114, blue: 0.137)
    static let inkOnDarkSoft  = Color(red: 0.420, green: 0.447, blue: 0.502)
    static let inkOnDarkFaded = Color(red: 0.612, green: 0.639, blue: 0.686)
}

// ─── OCR ENGINE OPTIONS ──────────────────────────────────────────────────────
enum OCREngine: String, CaseIterable, Identifiable {
    case tesseract = "Tesseract (norsk)"
    case vision    = "Apple Vision"
    var id: String { rawValue }
}

let tesseractPath: String? = {
    let candidates = ["/opt/homebrew/bin/tesseract", "/usr/local/bin/tesseract"]
    return candidates.first { FileManager.default.fileExists(atPath: $0) }
}()

// ─── MAIN APP ────────────────────────────────────────────────────────────────
@main
struct TeamsToCSVApp: App {
    @StateObject private var updater = UpdateChecker()

    var body: some Scene {
        WindowGroup("Teams → CSV") {
            ContentView()
                .environmentObject(updater)
                .frame(minWidth: 520, minHeight: 800)
                .task {
                    await updater.checkForUpdate()
                }
        }
        .windowResizability(.contentMinSize)
    }
}

// ─── AUTO-UPDATE ─────────────────────────────────────────────────────────────
struct GitHubRelease: Codable {
    let tag_name: String
    let body: String
    let assets: [Asset]
    struct Asset: Codable {
        let name: String
        let browser_download_url: String
    }
}

@MainActor
class UpdateChecker: ObservableObject {
    @Published var availableVersion: String? = nil
    @Published var downloadURL: String? = nil
    @Published var isChecking: Bool = false
    @Published var isInstalling: Bool = false
    @Published var lastCheckedAt: Date? = nil
    @Published var errorMessage: String? = nil

    // Bytt til ditt GitHub-repo
    let repoOwner = "viavicdev"
    let repoName  = "plugin-markers"

    func checkForUpdate() async {
        isChecking = true
        errorMessage = nil
        defer { isChecking = false; lastCheckedAt = Date() }

        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else { return }
        do {
            var req = URLRequest(url: url)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: req)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

            if compareSemver(release.tag_name, appVersionLabel) > 0 {
                // Finn TeamsToCSV-zip asset
                if let asset = release.assets.first(where: { $0.name.lowercased().contains("teamstocsv") || $0.name.lowercased().contains("teams-to-csv") }) ??
                              release.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }) {
                    availableVersion = release.tag_name
                    downloadURL = asset.browser_download_url
                }
            }
        } catch {
            errorMessage = "Kunne ikke sjekke for oppdatering"
        }
    }

    func installUpdate() async {
        guard let dlString = downloadURL, let url = URL(string: dlString) else { return }
        isInstalling = true
        errorMessage = nil
        defer { isInstalling = false }

        do {
            // Last ned
            let (data, _) = try await URLSession.shared.data(from: url)
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("teamstocsv-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            let zipURL = tmp.appendingPathComponent("update.zip")
            try data.write(to: zipURL)

            // Pakk ut
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-q", zipURL.path, "-d", tmp.path]
            try unzip.run(); unzip.waitUntilExit()

            // Finn TeamsToCSV.app i utpakket
            guard let newApp = findApp(in: tmp, named: "TeamsToCSV.app") else {
                errorMessage = "Fant ikke TeamsToCSV.app i nedlastet zip"
                return
            }

            // Skriv et update-script som venter, swapper, og restarter
            let scriptPath = NSTemporaryDirectory() + "teamstocsv-installer.sh"
            let script = """
            #!/bin/bash
            sleep 1
            rm -rf "/Applications/TeamsToCSV.app"
            cp -R "\(newApp.path)" "/Applications/TeamsToCSV.app"
            xattr -dr com.apple.quarantine "/Applications/TeamsToCSV.app" 2>/dev/null || true
            sleep 1
            open "/Applications/TeamsToCSV.app"
            rm -rf "\(tmp.path)"
            """
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/bash")
            proc.arguments = [scriptPath]
            try proc.run()

            // Quit selv
            NSApplication.shared.terminate(nil)
        } catch {
            errorMessage = "Installasjon feilet: \(error.localizedDescription)"
        }
    }

    private func findApp(in dir: URL, named name: String) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return nil }
        while let url = enumerator.nextObject() as? URL {
            if url.lastPathComponent == name { return url }
        }
        return nil
    }

    // Returner positiv hvis a > b, negativ hvis a < b, 0 hvis like
    func compareSemver(_ a: String, _ b: String) -> Int {
        let aClean = a.replacingOccurrences(of: "v", with: "")
            .components(separatedBy: " ").first ?? a
        let bClean = b.replacingOccurrences(of: "v", with: "")
            .components(separatedBy: " ").first ?? b
        let aParts = aClean.split(separator: ".").compactMap { Int($0) }
        let bParts = bClean.split(separator: ".").compactMap { Int($0) }
        let maxLen = max(aParts.count, bParts.count)
        for i in 0..<maxLen {
            let aVal = i < aParts.count ? aParts[i] : 0
            let bVal = i < bParts.count ? bParts[i] : 0
            if aVal != bVal { return aVal - bVal }
        }
        return 0
    }
}

// ─── HTML ANIMATION VIEW ─────────────────────────────────────────────────────
struct AnimationView: NSViewRepresentable {
    let htmlName: String

    func makeNSView(context: Context) -> WKWebView {
        let webview = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webview.setValue(false, forKey: "drawsBackground")
        webview.layer?.backgroundColor = NSColor.clear.cgColor
        if let url = Bundle.main.url(forResource: htmlName, withExtension: "html") {
            webview.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webview
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// ─── GLM-5 BACKGROUND ────────────────────────────────────────────────────────
// Linear cool-white gradient + subtle red top-left + indigo bottom-right.
struct NoiseBackground: View {
    let baseColor: Color  // ignorert

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.bgPrimary, Color.bgSecondary],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Color.brandAccent.opacity(0.04), Color.clear],
                center: UnitPoint(x: 0.20, y: 0.0),
                startRadius: 0, endRadius: 520
            )
            RadialGradient(
                colors: [Color.indigoBgTint.opacity(0.03), Color.clear],
                center: UnitPoint(x: 0.80, y: 1.0),
                startRadius: 0, endRadius: 480
            )
        }
        .ignoresSafeArea()
    }
}

private func makeNoise(size: CGSize) -> NSImage {
    let w = Int(size.width)
    let h = Int(size.height)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: w * 4, bitsPerPixel: 32
    ) else { return NSImage(size: size) }

    var pixel: [Int] = [0, 0, 0, 0]
    for y in 0..<h {
        for x in 0..<w {
            let v = Int.random(in: 0...255)
            let a = Int.random(in: 18...64)
            pixel[0] = v; pixel[1] = v; pixel[2] = v; pixel[3] = a
            pixel.withUnsafeMutableBufferPointer { buf in
                rep.setPixel(buf.baseAddress!, atX: x, y: y)
            }
        }
    }
    let img = NSImage(size: size)
    img.addRepresentation(rep)
    return img
}

// ─── MODELS ──────────────────────────────────────────────────────────────────
struct CSVRow: Identifiable, Equatable {
    let id = UUID()
    var date: String = ""          // DD/M format fra Teams-datoheader (kan være tom)
    var tc: String
    var comment: String
    var note: String = ""          // ekstrahert "NOTE: ..."-del (også fortsatt i comment)
    var truncated: Bool = false
}

struct ProcessedFile: Identifiable {
    let id = UUID()
    let pngURL: URL
    let csvURL: URL
    var rows: [CSVRow]
    var thumbnail: NSImage? = nil
    var contentHash: String? = nil
    var markerCount: Int { rows.count }
}

// ─── CONTENT VIEW ────────────────────────────────────────────────────────────
// ─── SETTINGS KEYS ───────────────────────────────────────────────────────────
enum SaveLocationMode: String, CaseIterable, Identifiable {
    case alongside = "alongside"
    case custom    = "custom"
    var id: String { rawValue }
    var label: String {
        self == .alongside ? "Ved siden av PNG" : "Egen mappe"
    }
}

struct ContentView: View {
    @EnvironmentObject var updater: UpdateChecker
    @State private var isDragging = false
    @State private var processedFiles: [ProcessedFile] = []
    @State private var errorMessage: String?
    @State private var isProcessing = false
    @State private var showInfo = false
    @State private var showSettings = false

    // Persisted settings
    @AppStorage("ocrEngine")        private var engine: OCREngine = .tesseract
    @AppStorage("tesseractFallback") private var tesseractFallback: Bool = true
    @AppStorage("saveLocationMode") private var saveLocationMode: SaveLocationMode = .alongside
    @AppStorage("customSavePath")   private var customSavePath: String = ""
    @AppStorage("exportPDF")        private var exportPDF: Bool = false
    @AppStorage("exportXLSX")       private var exportXLSX: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            NoiseBackground(baseColor: Color.canvas)

            VStack(spacing: 0) {
                header
                if updater.availableVersion != nil { updateBanner }

                ScrollView {
                    VStack(spacing: 16) {
                        dropZone
                        resultsList
                        if !processedFiles.isEmpty {
                            clearAllButton
                                .padding(.top, 8)
                        }
                    }
                    .frame(maxWidth: 1240)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 48)
                    .frame(maxWidth: .infinity)
                }
            }

        }
        .sheet(isPresented: $showInfo) { InfoSheet(isPresented: $showInfo) }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                isPresented: $showSettings,
                engine: $engine,
                tesseractFallback: $tesseractFallback,
                saveLocationMode: $saveLocationMode,
                customSavePath: $customSavePath,
                exportPDF: $exportPDF,
                exportXLSX: $exportXLSX
            )
        }
    }

    private var clearAllButton: some View {
        Button {
            processedFiles.removeAll()
            errorMessage = nil
        } label: {
            Text("Tøm alle")
                .font(.system(size: 12))
                .foregroundColor(.inkSoft)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.glassBgSub)
                        .background(
                            RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // Header — GLM-5 style: logo-square + bold title + Settings text-button + About icon
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 0) {
                Text("Teams")
                    .foregroundColor(.ink)
                Text("To")
                    .foregroundColor(.brandAccent)
                Text("Markers")
                    .foregroundColor(.ink)
            }
            .font(.system(size: 18, weight: .semibold))
            .tracking(-0.4)

            BetaPill()
                .padding(.leading, 4)

            Text(appVersionLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.inkFaded)

            Spacer()

            if processedFiles.count >= 2 {
                Button {
                    mergeAllToCSV()
                } label: {
                    Label("Slå sammen", systemImage: "rectangle.stack.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.brandAccent)
                        )
                        .shadow(color: Color.brandAccentGlow, radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .help("Slå sammen alle filer til én CSV, sortert på dato + timecode")
            }

            GhostHeaderButton(label: "Innstillinger", systemIcon: "gearshape") {
                showSettings = true
            }

            IconHeaderButton(systemIcon: "info.circle", help: "Om / personvern") {
                showInfo = true
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            LinearGradient(
                colors: [Color.bgPrimary.opacity(0.95), Color.bgPrimary.opacity(0)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    // Update-banner som vises hvis ny versjon er tilgjengelig
    private var updateBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: updater.isInstalling ? "arrow.down.circle" : "arrow.down.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(.white)
            Text(updater.isInstalling
                 ? "Installerer …"
                 : "Ny versjon tilgjengelig: \(updater.availableVersion ?? "")")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
            Spacer()
            if !updater.isInstalling {
                Button("Oppdater nå") {
                    Task { await updater.installUpdate() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.brandAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Color.brandAccent)
    }

    private var engineLabel: String {
        switch engine {
        case .tesseract:
            return tesseractPath == nil ? "Tesseract (ikke installert)" : "Tesseract (norsk)"
        case .vision:
            return "Apple Vision"
        }
    }

    // Drop zone — GLM-5 stor versjon når tom, compact når filer finnes
    private var dropZone: some View {
        let compact = !processedFiles.isEmpty
        return ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isDragging ? Color.glassBgEl : Color.glassBgSub)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            isDragging ? Color.brandAccent : Color.line,
                            style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                        )
                )

            // Hover/active subtle accent overlay
            if isDragging {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.clear, Color.brandAccentDim],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 0) {
                if isProcessing {
                    VStack(spacing: 12) {
                        AnimationView(htmlName: "timeline-bw")
                            .frame(width: 200, height: 110)
                        Text("Kjører OCR…")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.inkSoft)
                    }
                    .padding(.vertical, compact ? 18 : 36)
                } else if compact {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 13))
                            .foregroundColor(isDragging ? .brandAccent : .inkFaded)
                        Text(isDragging ? "Slipp her" : "Slipp flere screenshots her")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isDragging ? .brandAccent : .inkSoft)
                    }
                    .padding(.vertical, 18)
                } else {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(Color.glassBgEl)
                            .frame(width: 72, height: 72)
                            .overlay(
                                Circle().strokeBorder(Color.line, lineWidth: 1)
                            )
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 28))
                                    .foregroundColor(.brandAccent)
                            )
                            .padding(.bottom, 20)

                        Text(isDragging ? "Slipp filene her" : "Slipp Teams-screenshots her")
                            .font(.system(size: 20, weight: .semibold))
                            .tracking(-0.4)
                            .foregroundColor(.ink)
                            .padding(.bottom, 8)

                        Text("eller klikk for å velge filer")
                            .font(.system(size: 14))
                            .foregroundColor(.inkSoft)
                            .padding(.bottom, 16)

                        HStack(spacing: 8) {
                            FormatTag(text: "PNG")
                            FormatTag(text: "JPG")
                            FormatTag(text: "JPEG")
                        }
                    }
                    .padding(.vertical, 56)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { selectFiles() }
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            loadDropped(providers: providers)
            return true
        }
    }

    // Results list (uten egen scrollview — er allerede inni en)
    @ViewBuilder
    private var resultsList: some View {
        if let err = errorMessage {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.brandAccent)
                Text(err).font(.system(size: 12))
                    .foregroundColor(.ink)
                Spacer()
                Button {
                    errorMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.inkSoft)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.brandAccentDim)
            )
        }

        if processedFiles.isEmpty && errorMessage == nil {
            EmptyView()
        } else {
            ForEach($processedFiles) { $file in
                FileRow(
                    file: $file,
                    onDownload: { saveCSV(file) },
                    onShowInFinder: { NSWorkspace.shared.activateFileViewerSelecting([file.csvURL]) },
                    onRemove: { processedFiles.removeAll { $0.id == file.id } }
                )
            }
        }
    }

    // ── Actions ──
    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            process(urls: panel.urls)
        }
    }

    private func loadDropped(providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                } else if let url = item as? URL {
                    urls.append(url)
                }
            }
        }
        group.notify(queue: .main) {
            process(urls: urls)
        }
    }

    private func process(urls: [URL]) {
        guard !urls.isEmpty else { return }
        errorMessage = nil
        isProcessing = true
        let selectedEngine = engine
        let fallback = tesseractFallback
        let saveMode = saveLocationMode
        let customPath = customSavePath
        let alsoPDF = exportPDF
        let alsoXLSX = exportXLSX
        let existingHashes = Set(processedFiles.compactMap { $0.contentHash })
        DispatchQueue.global(qos: .userInitiated).async {
            var results: [ProcessedFile] = []
            var errors: [String] = []
            var seenHashes = existingHashes
            for url in urls {
                let ext = url.pathExtension.lowercased()
                guard ["png", "jpg", "jpeg"].contains(ext) else {
                    errors.append("Hopper over \(url.lastPathComponent) (ikke bilde)")
                    continue
                }
                // Dup-deteksjon: hash før OCR
                let hash = sha256(of: url)
                if let h = hash, seenHashes.contains(h) {
                    errors.append("\(url.lastPathComponent) er allerede lastet inn (duplikat)")
                    continue
                }
                if let h = hash { seenHashes.insert(h) }

                let outputDir = resolveSaveDirectory(
                    mode: saveMode, customPath: customPath, fallback: url.deletingLastPathComponent()
                )
                switch ocrToCSV(url: url, engine: selectedEngine, fallbackToVision: fallback,
                                outputDir: outputDir, alsoPDF: alsoPDF, alsoXLSX: alsoXLSX) {
                case .success(var result):
                    result.contentHash = hash
                    result.thumbnail   = makeThumbnail(from: url)
                    results.append(result)
                case .failure(let err):
                    errors.append("\(url.lastPathComponent): \(err.localizedDescription)")
                }
            }
            DispatchQueue.main.async {
                processedFiles.append(contentsOf: results)
                isProcessing = false
                if !errors.isEmpty {
                    errorMessage = errors.joined(separator: " · ")
                }
            }
        }
    }

    private func resolveSaveDirectory(mode: SaveLocationMode, customPath: String, fallback: URL) -> URL {
        if mode == .custom, !customPath.isEmpty {
            let url = URL(fileURLWithPath: customPath)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return fallback
    }

    private func mergeAllToCSV() {
        guard processedFiles.count >= 2 else { return }
        var allRows: [CSVRow] = []
        for file in processedFiles {
            allRows.append(contentsOf: file.rows)
        }
        // Sorter på dato (DD/M) først, deretter TC
        allRows.sort { lhs, rhs in
            let lk = dateSortKey(lhs.date), rk = dateSortKey(rhs.date)
            if lk != rk { return lk < rk }
            return lhs.tc < rhs.tc
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "merged-markers.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.directoryURL = processedFiles.first?.pngURL.deletingLastPathComponent()
        if panel.runModal() == .OK, let dest = panel.url {
            let csv = "timecode,comment,note\n" + allRows.map {
                "\($0.tc),\(csvEscape($0.comment)),\(csvEscape($0.note))"
            }.joined(separator: "\n") + "\n"
            do {
                try csv.write(to: dest, atomically: true, encoding: .utf8)
            } catch {
                errorMessage = "Sammenslåing feilet: \(error.localizedDescription)"
            }
        }
    }

    private func saveCSV(_ file: ProcessedFile) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.csvURL.lastPathComponent
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.directoryURL = file.pngURL.deletingLastPathComponent()
        if panel.runModal() == .OK, let dest = panel.url {
            // Regenerer CSV fra nåværende (potentielt redigerte) rader (4 kolonner: date,tc,comment,note)
            let csv = "timecode,comment,note\n" + file.rows.map {
                "\($0.tc),\(csvEscape($0.comment)),\(csvEscape($0.note))"
            }.joined(separator: "\n") + "\n"
            do {
                try csv.write(to: dest, atomically: true, encoding: .utf8)
                // Også oppdater den opprinnelige CSV-en ved siden av PNG
                try? csv.write(to: file.csvURL, atomically: true, encoding: .utf8)
            } catch {
                errorMessage = "Lagring feilet: \(error.localizedDescription)"
            }
        }
    }
}

// ─── BRAND COMPONENTS ────────────────────────────────────────────────────────
let appVersionLabel = "v1.24"

struct ClapperboardLogo: View {
    var size: CGFloat = 40
    var iconScale: CGFloat = 0.55

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.brandAccent, Color.brandAccentHover],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.brandAccentGlow, radius: 8, y: 4)

            // Spreadsheet/table SVG som hvit stroke
            Canvas { ctx, csize in
                let s = min(csize.width, csize.height)
                let stroke = max(1.2, s * 0.085)
                let inset = s * 0.10
                let rect = CGRect(x: inset, y: inset, width: s - 2*inset, height: s - 2*inset)

                let path = Path { p in
                    // Outer rounded rect
                    p.addRoundedRect(in: rect, cornerSize: CGSize(width: s*0.10, height: s*0.10))
                    // Two vertical lines (3 columns)
                    let col1 = rect.minX + rect.width * 0.33
                    let col2 = rect.minX + rect.width * 0.67
                    p.move(to: CGPoint(x: col1, y: rect.minY))
                    p.addLine(to: CGPoint(x: col1, y: rect.maxY))
                    p.move(to: CGPoint(x: col2, y: rect.minY))
                    p.addLine(to: CGPoint(x: col2, y: rect.maxY))
                    // Two horizontal lines (3 rows)
                    let row1 = rect.minY + rect.height * 0.33
                    let row2 = rect.minY + rect.height * 0.67
                    p.move(to: CGPoint(x: rect.minX, y: row1))
                    p.addLine(to: CGPoint(x: rect.maxX, y: row1))
                    p.move(to: CGPoint(x: rect.minX, y: row2))
                    p.addLine(to: CGPoint(x: rect.maxX, y: row2))
                }
                ctx.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
            }
            .frame(width: size * iconScale, height: size * iconScale)
        }
        .frame(width: size, height: size)
    }
}

struct BetaPill: View {
    var body: some View {
        Text("BETA")
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.8)
            .foregroundColor(.brandAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.brandAccentDim)
            )
    }
}

struct GhostHeaderButton: View {
    let label: String
    let systemIcon: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemIcon)
                    .font(.system(size: 13))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(hover ? .ink : .inkSoft)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hover ? Color.glassBgEl : Color.glassBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.glassBorderSub, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.14), value: hover)
    }
}

struct IconHeaderButton: View {
    let systemIcon: String
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemIcon)
                .font(.system(size: 16))
                .foregroundColor(hover ? .ink : .inkSoft)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(hover ? Color.glassBgEl : Color.glassBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.glassBorderSub, lineWidth: 1)
                )
                .shadow(color: hover ? Color.black.opacity(0.06) : Color.clear, radius: 6, y: 2)
                .offset(y: hover ? -1 : 0)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.14), value: hover)
        .help(help)
    }
}

// ─── FORMAT TAGS ─────────────────────────────────────────────────────────────
struct FormatTag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(0.5)
            .foregroundColor(.inkFaded)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.glassBgEl)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.line, lineWidth: 1)
            )
    }
}

// ─── FILM-STRIP PROCESSING OVERLAY ───────────────────────────────────────────
struct ProcessingOverlay: View {
    @State private var elapsed: Double = 0
    @State private var statusIdx: Int = 0
    @State private var scanOffset: CGFloat = 0
    private let statuses = [
        "Initialiserer OCR-motor…",
        "Analyserer bildestruktur…",
        "Oppdager meldingsgrenser…",
        "Ekstraherer tidsstempler…",
        "Parser meldingsinnhold…",
        "Validerer timecodes…",
        "Bygger output-rader…",
        "Avslutter…"
    ]
    private let timer = Timer.publish(every: 0.033, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.bgPrimary.opacity(0.92)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Film strip
                ZStack {
                    // Body (dark gradient)
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.10, blue: 0.10),
                            Color(red: 0.165, green: 0.165, blue: 0.165),
                            Color(red: 0.10, green: 0.10, blue: 0.10)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    HStack(spacing: 0) {
                        // Left perforation strip
                        FilmPerforations()
                            .frame(width: 16)
                        // 8 frames in middle
                        HStack(spacing: 3) {
                            ForEach(0..<8, id: \.self) { i in
                                FilmFrame(delay: Double(i) * 0.1)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                        // Right perforation strip
                        FilmPerforations()
                            .frame(width: 16)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    // Glow center
                    RadialGradient(
                        colors: [Color.brandAccent.opacity(0.20), Color.clear],
                        center: .center, startRadius: 0, endRadius: 80
                    )
                    .frame(width: 200, height: 60)
                }
                .frame(width: 320, height: 80)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 8)

                // Counter (HH:MM:SS film frames)
                Text(frameTimecode())
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.brandAccent)

                Text(statuses[min(statusIdx, statuses.count - 1)])
                    .font(.system(size: 13))
                    .foregroundColor(.inkSoft)
            }
        }
        .onReceive(timer) { _ in
            elapsed += 0.033
            let frames = Int(elapsed / 0.033)
            statusIdx = min((frames / 15) % statuses.count, statuses.count - 1)
        }
    }

    private func frameTimecode() -> String {
        let total = Int(elapsed * 30) // 30fps
        let frames = total % 30
        let sec = (total / 30) % 60
        let min = (total / (30 * 60)) % 60
        return String(format: "%02d:%02d:%02d", min, sec, frames)
    }
}

struct FilmFrame: View {
    let delay: Double
    @State private var scanX: CGFloat = -1.2

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.23, green: 0.23, blue: 0.23),
                        Color(red: 0.165, green: 0.165, blue: 0.165)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.10), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: geo.size.width)
                .offset(x: scanX * geo.size.width)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        scanX = 1.2
                    }
                }
            }
        }
    }
}

struct FilmPerforations: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let cellH: CGFloat = 8
                let holeH: CGFloat = 6
                let holeW: CGFloat = 8
                var y: CGFloat = 0
                while y < size.height {
                    let rect = CGRect(x: (size.width - holeW) / 2, y: y + (cellH - holeH) / 2, width: holeW, height: holeH)
                    ctx.fill(
                        Path(roundedRect: rect, cornerSize: CGSize(width: 1, height: 1)),
                        with: .color(.black.opacity(0.55))
                    )
                    y += cellH * 2
                }
            }
        }
        .background(Color(red: 0.04, green: 0.04, blue: 0.04))
    }
}

// ─── CINEMATIC LOADER ────────────────────────────────────────────────────────
// Sirkulær progress + 4 registreringsmerker + film-strip rull, alt i SwiftUI.
struct CinematicLoader: View {
    @State private var progress: CGFloat = 0
    @State private var counter: Int = 8
    @State private var filmOffset: CGFloat = 0
    @State private var shutter: Bool = false

    let totalSteps: Int = 8

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                // Registreringsmerker (4 hjørner) — sterilt og presist
                ForEach(0..<4, id: \.self) { i in
                    RegMark()
                        .frame(width: 12, height: 12)
                        .offset(regOffset(i))
                }

                // Bakgrunn-ring (svak)
                Circle()
                    .strokeBorder(Color.black.opacity(0.07), lineWidth: 1.5)
                    .frame(width: 110, height: 110)

                // Progress-ring (rød)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.brandAccent,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 110, height: 110)
                    .animation(.easeOut(duration: 0.28), value: progress)

                // Shutter-flash linje (kort blits)
                Rectangle()
                    .fill(Color.brandAccent)
                    .frame(width: 100, height: 1.5)
                    .opacity(shutter ? 0.7 : 0)
                    .animation(.easeOut(duration: 0.18), value: shutter)

                // Stort nummer i midten
                Text(pad2(counter))
                    .font(.system(size: 38, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.brandAccent)
            }
            .frame(width: 140, height: 140)

            Text("ANALYSERER")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(3)
                .foregroundColor(.inkFaded)

            // Film-strip — to rader perforerings-hull som scroller
            FilmStrip(offset: filmOffset)
                .frame(width: 220, height: 28)
        }
        .padding(.vertical, 24)
        .onAppear { tick() }
    }

    private func tick() {
        guard counter > 0 else { return }
        progress = CGFloat(totalSteps - counter + 1) / CGFloat(totalSteps)
        shutter = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { shutter = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            counter -= 1
            if counter > 0 { tick() }
        }
        withAnimation(.linear(duration: 0.38).repeatForever(autoreverses: false)) {
            filmOffset = 22
        }
    }

    private func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    private func regOffset(_ i: Int) -> CGSize {
        let r: CGFloat = 70
        switch i {
        case 0: return CGSize(width: 0, height: -r)   // top
        case 1: return CGSize(width: r, height: 0)    // right
        case 2: return CGSize(width: 0, height: r)    // bottom
        default: return CGSize(width: -r, height: 0)  // left
        }
    }
}

struct RegMark: View {
    var body: some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(0.18)).frame(width: 12, height: 1.5)
            Rectangle().fill(Color.black.opacity(0.18)).frame(width: 1.5, height: 12)
        }
    }
}

struct FilmStrip: View {
    let offset: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let holeW: CGFloat = 6, holeH: CGFloat = 8, holeRx: CGFloat = 1.5
            let step: CGFloat = 22
            let xOffset = -offset.truncatingRemainder(dividingBy: step)
            var x: CGFloat = xOffset
            while x < size.width + step {
                // top hull
                ctx.fill(
                    Path(roundedRect: CGRect(x: x, y: 2, width: holeW, height: holeH),
                         cornerSize: CGSize(width: holeRx, height: holeRx)),
                    with: .color(.black.opacity(0.06))
                )
                // bottom hull
                ctx.fill(
                    Path(roundedRect: CGRect(x: x, y: size.height - 2 - holeH, width: holeW, height: holeH),
                         cornerSize: CGSize(width: holeRx, height: holeRx)),
                    with: .color(.black.opacity(0.06))
                )
                x += step
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Color.black.opacity(0.07)).frame(height: 1.5)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.07)).frame(height: 1.5)
        }
    }
}

struct HoverHighlightButtonStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hover ? Color.black.opacity(0.05) : Color.clear)
            )
            .onHover { hover = $0 }
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct BetaBadge: View {
    var onLight: Bool = false

    var body: some View {
        // Coral-rød for mørk bakgrunn, deeper brandAccent for hvit
        let accent      = onLight ? Color.brandAccent
                                  : Color(red: 1.0, green: 0.40, blue: 0.40)
        let accentBg    = accent.opacity(onLight ? 0.10 : 0.16)
        let versionTint = onLight ? Color.inkSoft : Color.inkOnDarkSoft

        return HStack(spacing: 4) {
            Text("BETA")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(accent, lineWidth: 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(accentBg))
                )
            Text(appVersionLabel)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.6)
                .foregroundColor(versionTint)
        }
    }
}

// ─── FILE CARD (GLM-5 style) ─────────────────────────────────────────────────
struct FileRow: View {
    @Binding var file: ProcessedFile
    let onDownload: () -> Void
    let onShowInFinder: () -> Void
    let onRemove: () -> Void
    @State private var showAll: Bool = false
    @State private var isEditing: Bool = false
    @State private var hoverCard: Bool = false

    private let initialRows = 8

    private var truncatedCount: Int {
        file.rows.filter { $0.truncated }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Card header: thumbnail + filename + meta + actions ──
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 14) {
                    // Thumbnail box (44×44)
                    if let thumb = file.thumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.line, lineWidth: 1)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.bgSecondary)
                            .frame(width: 44, height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.line, lineWidth: 1)
                            )
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 18))
                                    .foregroundColor(.inkFaded)
                            )
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Button {
                            quickLook(file.pngURL)
                        } label: {
                            HStack(spacing: 5) {
                                Text(file.pngURL.lastPathComponent)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.ink)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Image(systemName: "eye")
                                    .font(.system(size: 10))
                                    .foregroundColor(.inkFaded)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Klikk for Quick Look av kilde-PNG")

                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Text("\(file.markerCount)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.brandAccent)
                                Text("markers")
                                    .font(.system(size: 12))
                                    .foregroundColor(.inkFaded)
                            }
                            if truncatedCount > 0 {
                                Text("\(truncatedCount) kanskje kuttet")
                                    .font(.system(size: 12))
                                    .foregroundColor(.dangerRed)
                            }
                        }
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    SecondaryPill(label: isEditing ? "Ferdig" : "Rediger", active: isEditing) {
                        isEditing.toggle()
                    }
                    SquareIconBtn(systemIcon: "folder", help: "Vis i Finder", action: onShowInFinder)
                    SquareIconBtn(systemIcon: "trash", help: "Fjern fra listen", danger: true, action: onRemove)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.glassBgEl)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.divider).frame(height: 1)
            }

            // ── Table preview ──
            CSVTablePreview(rows: $file.rows, showAll: $showAll, limit: initialRows, isEditing: isEditing)

            // ── Footer: Clear markers (ghost) + Download CSV (primary red) ──
            HStack {
                Button {
                    file.rows = []
                } label: {
                    Text("Tøm rader")
                        .font(.system(size: 12))
                        .foregroundColor(.inkSoft)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onDownload) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Last ned CSV")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.brandAccent)
                    )
                    .shadow(color: Color.brandAccentGlow, radius: 6, y: 3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.glassBgSub)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.divider).frame(height: 1)
            }
        }
        .background(Color.glassBg)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.glassBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(hoverCard ? 0.10 : 0.06), radius: hoverCard ? 18 : 10, y: hoverCard ? 8 : 3)
        .offset(y: hoverCard ? -2 : 0)
        .onHover { hoverCard = $0 }
        .animation(.easeOut(duration: 0.22), value: hoverCard)
    }
}

// ─── SECONDARY PILL + SQUARE ICON ────────────────────────────────────────────
struct SecondaryPill: View {
    let label: String
    var active: Bool = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: active ? .semibold : .medium))
                .foregroundColor(active ? .brandAccent : .ink)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(active ? Color.brandAccentDim : (hover ? Color.glassBgEl : Color.glassBg))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(active ? Color.brandAccent.opacity(0.5) : Color.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.14), value: hover)
    }
}

struct SquareIconBtn: View {
    let systemIcon: String
    let help: String
    var danger: Bool = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemIcon)
                .font(.system(size: 14))
                .foregroundColor(hover && danger ? .dangerRed : (hover ? .ink : .inkSoft))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hover ? (danger ? Color.dangerBg : Color.glassBgEl) : Color.glassBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.14), value: hover)
        .help(help)
    }
}

// ─── BUTTONS (GLM) ───────────────────────────────────────────────────────────
struct GhostButton: View {
    let title: String
    var active: Bool = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: active ? .semibold : .medium))
                .foregroundColor(active ? .brandAccent : (hover ? .ink : .inkSoft))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(active ? Color.brandAccentDim : (hover ? Color.black.opacity(0.05) : Color.clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hover ? Color(red: 0.77, green: 0.08, blue: 0.08) : Color.brandAccent)
                )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

struct IconGhostButton: View {
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(hover ? .brandAccent : .inkFaded)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hover ? Color.brandAccentDim : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .help(help)
    }
}

// ─── CSV TABLE PREVIEW ───────────────────────────────────────────────────────
struct CSVTablePreview: View {
    @Binding var rows: [CSVRow]
    @Binding var showAll: Bool
    let limit: Int
    let isEditing: Bool

    private var visibleCount: Int {
        showAll ? rows.count : min(limit, rows.count)
    }

    private let dateW: CGFloat = 60
    private let tcW:   CGFloat = 78

    var body: some View {
        VStack(spacing: 0) {
            // Header row (mono uppercase, light bg)
            HStack(spacing: 0) {
                tableHead("DATE", width: dateW)
                tableHead("TIMECODE", width: tcW)
                tableHead("MESSAGE", flex: true)
                if isEditing { Color.clear.frame(width: 48) }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.glassBgSub)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.divider).frame(height: 1)
            }

            // Rows
            ForEach(0..<visibleCount, id: \.self) { idx in
                rowView(idx: idx)
            }

            // Expand/collapse
            if rows.count > limit {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showAll.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showAll ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                        Text(showAll ? "Vis færre" : "Vis alle \(rows.count) rader (+\(rows.count - limit))")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .foregroundColor(.brandAccent)
                    .background(Color.glassBgSub)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.divider).frame(height: 1)
                }
            }
        }
    }

    @ViewBuilder
    private func tableHead(_ title: String, width: CGFloat? = nil, flex: Bool = false) -> some View {
        let view = Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundColor(.inkFaded)
            .textCase(.uppercase)
        if flex {
            view.frame(maxWidth: .infinity, alignment: .leading)
        } else if let w = width {
            view.frame(width: w, alignment: .leading)
        }
    }

    @ViewBuilder
    private func rowView(idx: Int) -> some View {
        let row = rows[idx]
        HStack(alignment: .top, spacing: 0) {
            if isEditing {
                // Edit mode: input fields
                editCell {
                    TextField("DD/M", text: $rows[idx].date)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.inkSoft)
                }
                .frame(width: dateW)
                editCell {
                    TextField("HH:MM", text: $rows[idx].tc)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.brandAccent)
                }
                .frame(width: tcW)
                VStack(alignment: .leading, spacing: 4) {
                    editCell {
                        TextField("Melding", text: $rows[idx].comment, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundColor(.ink)
                            .lineLimit(1...50)
                    }
                    editCell {
                        TextField("NOTE: …", text: $rows[idx].note)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11).italic())
                            .foregroundColor(.inkFaded)
                    }
                }
                .frame(maxWidth: .infinity)
                Button {
                    if let realIdx = rows.firstIndex(where: { $0.id == row.id }) {
                        rows.remove(at: realIdx)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundColor(.inkFaded)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .frame(width: 48)
            } else {
                // View mode: 3 columns with Note as inline yellow box under message
                Text(row.date)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.inkSoft)
                    .frame(width: dateW, alignment: .leading)

                Text(row.tc)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.brandAccent)
                    .frame(width: tcW, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(row.comment)
                            .font(.system(size: 13))
                            .foregroundColor(.ink)
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if row.truncated {
                            Text("kanskje kuttet")
                                .font(.system(size: 9, weight: .medium))
                                .tracking(0.3)
                                .foregroundColor(.dangerRed)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.dangerBg)
                                )
                                .help("Slutter midt i setning — sjekk i Rediger-modus")
                        }
                    }
                    if !row.note.isEmpty {
                        Text(noteDisplay(row.note))
                            .font(.system(size: 12))
                            .foregroundColor(.inkSoft)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.warnBg)
                            )
                            .overlay(alignment: .leading) {
                                Rectangle().fill(Color.warnBorder).frame(width: 2)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.divider.opacity(0.5)).frame(height: 1)
        }
    }

    @ViewBuilder
    private func editCell<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.glassBgEl)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.line, lineWidth: 1)
            )
            .padding(.horizontal, 4)
    }

    private func noteDisplay(_ note: String) -> String {
        if note.isEmpty { return "" }
        let trimmed = note.replacingOccurrences(
            of: #"^NOTE\s*:\s*"#, with: "", options: .regularExpression
        )
        return trimmed.isEmpty ? note : "NOTE: \(trimmed)"
    }
}

// ─── OCR + PARSE ─────────────────────────────────────────────────────────────
enum OCRError: Error, LocalizedError {
    case decodeFailed
    case noText
    case noTimestamps
    case writeFailed(String)
    var errorDescription: String? {
        switch self {
        case .decodeFailed:  return "kunne ikke lese bildet"
        case .noText:        return "ingen tekst funnet"
        case .noTimestamps:  return "ingen tidsstempler funnet"
        case .writeFailed(let m): return "skriving feilet (\(m))"
        }
    }
}

func ocrToCSV(url: URL, engine: OCREngine, fallbackToVision: Bool, outputDir: URL,
              alsoPDF: Bool, alsoXLSX: Bool) -> Result<ProcessedFile, OCRError> {
    var lines: [String] = []
    switch engine {
    case .vision:
        guard let cg = loadCGImage(url: url) else { return .failure(.decodeFailed) }
        lines = visionOCR(cg)
    case .tesseract:
        if let path = tesseractPath {
            switch tesseractOCR(url: url, binaryPath: path) {
            case .success(let l): lines = l
            case .failure(let e):
                // Tesseract feilet — fallback til Vision hvis tillatt
                if fallbackToVision, let cg = loadCGImage(url: url) {
                    lines = visionOCR(cg)
                } else {
                    return .failure(e)
                }
            }
        } else if fallbackToVision {
            // Tesseract ikke installert — fallback til Vision
            guard let cg = loadCGImage(url: url) else { return .failure(.decodeFailed) }
            lines = visionOCR(cg)
        } else {
            return .failure(.writeFailed("Tesseract ikke installert. Aktiver fallback i innstillinger."))
        }
    }

    if lines.isEmpty { return .failure(.noText) }
    let parsed = parseTeamsLines(lines)
    if parsed.isEmpty { return .failure(.noTimestamps) }

    let baseName = url.deletingPathExtension().lastPathComponent
    let csvURL  = outputDir.appendingPathComponent(baseName).appendingPathExtension("csv")
    let csv = "timecode,comment,note\n" + parsed.map { p in
        let note = extractNote(from: p.comment)
        return "\(p.tc),\(csvEscape(p.comment)),\(csvEscape(note))"
    }.joined(separator: "\n") + "\n"
    do {
        try csv.write(to: csvURL, atomically: true, encoding: .utf8)
    } catch {
        return .failure(.writeFailed(error.localizedDescription))
    }

    if alsoPDF {
        let pdfURL = outputDir.appendingPathComponent(baseName).appendingPathExtension("pdf")
        try? writePDF(rows: parsed.map { (tc: $0.tc, comment: $0.comment) }, title: baseName, to: pdfURL)
    }
    if alsoXLSX {
        let xlsxURL = outputDir.appendingPathComponent(baseName).appendingPathExtension("xlsx")
        try? writeXLSX(rows: parsed.map { (tc: $0.tc, comment: $0.comment) }, to: xlsxURL)
    }

    let rows = parsed.map { p -> CSVRow in
        let note = extractNote(from: p.comment)
        return CSVRow(date: p.date, tc: p.tc, comment: p.comment, note: note, truncated: p.truncated)
    }
    return .success(ProcessedFile(pngURL: url, csvURL: csvURL, rows: rows))
}

// ─── FILE HASH / THUMBNAIL / QUICK LOOK ──────────────────────────────────────
func sha256(of url: URL) -> String? {
    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

func makeThumbnail(from url: URL, maxDim: CGFloat = 80) -> NSImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: Int(maxDim * 2),
        kCGImageSourceCreateThumbnailWithTransform: true
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
    let size = NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2)
    return NSImage(cgImage: cg, size: size)
}

func quickLook(_ url: URL) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
    p.arguments = ["-p", url.path]
    p.standardOutput = Pipe()
    p.standardError = Pipe()
    try? p.run()
}

// "16/5" → 516, "2/6" → 602. Tomme datoer sorteres sist.
func dateSortKey(_ date: String) -> Int {
    let trimmed = date.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return Int.max }
    let parts = trimmed.split(separator: "/").compactMap { Int($0) }
    if parts.count == 2 { return parts[1] * 100 + parts[0] }
    return Int.max
}

// ─── IMAGE LOADING + PREPROCESSING ───────────────────────────────────────────
func loadCGImage(url: URL) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    return cg
}

// Scale up 2x and boost contrast — helps Vision recognise Teams UI fonts and
// Norwegian diacritics. Operates entirely in memory; source file untouched.
func preprocessForOCR(_ cg: CGImage) -> CGImage {
    let scale: CGFloat = 2.0
    let newW = Int(CGFloat(cg.width) * scale)
    let newH = Int(CGFloat(cg.height) * scale)

    let ciImage = CIImage(cgImage: cg)
    let filter = CIFilter(name: "CIColorControls")
    filter?.setValue(ciImage, forKey: kCIInputImageKey)
    filter?.setValue(1.3, forKey: kCIInputContrastKey)   // boost contrast
    filter?.setValue(0.0, forKey: kCIInputSaturationKey) // grayscale
    filter?.setValue(0.05, forKey: kCIInputBrightnessKey)
    let boosted = filter?.outputImage ?? ciImage

    let context = CIContext()
    let rect = CGRect(x: 0, y: 0, width: newW, height: newH)
    let scaled = boosted.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    return context.createCGImage(scaled, from: rect) ?? cg
}

// ─── VISION OCR ──────────────────────────────────────────────────────────────
func visionOCR(_ cg: CGImage) -> [String] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    if #available(macOS 13.0, *) {
        request.revision = VNRecognizeTextRequestRevision3
    }
    request.recognitionLanguages = ["nb-NO", "no", "en-US"]

    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    do { try handler.perform([request]) } catch { return [] }
    guard let observations = request.results else { return [] }

    return observations
        .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
        .compactMap { $0.topCandidates(1).first?.string }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

// ─── TESSERACT OCR ───────────────────────────────────────────────────────────
func tesseractOCR(url: URL, binaryPath: String) -> Result<[String], OCRError> {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("teams2csv-\(UUID().uuidString)")
    let stdoutPath = tmp.appendingPathExtension("txt").path

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: binaryPath)
    proc.arguments = [
        url.path,
        tmp.path,
        "-l", "nor+eng",
        "--psm", "6"     // assume uniform block of text
    ]
    let errPipe = Pipe()
    proc.standardError = errPipe
    proc.standardOutput = Pipe()

    do {
        try proc.run()
        proc.waitUntilExit()
    } catch {
        return .failure(.writeFailed("Tesseract feilet: \(error.localizedDescription)"))
    }

    guard proc.terminationStatus == 0,
          let data = FileManager.default.contents(atPath: stdoutPath),
          let text = String(data: data, encoding: .utf8)
    else {
        let stderr = (try? errPipe.fileHandleForReading.readToEnd())
            .flatMap { String(data: $0, encoding: .utf8) } ?? "ukjent feil"
        return .failure(.writeFailed("Tesseract returnerte feil: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"))
    }
    try? FileManager.default.removeItem(atPath: stdoutPath)

    let lines = text
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    return .success(lines)
}

let tcRegex = try! NSRegularExpression(pattern: #"(\d{1,2})[:.](\d{2})(?:[:.](\d{2}))?"#)

// Returner Range hvis linjen er en EKTE TC-linje (sender-header), ellers nil.
// Heuristikk: tekst FØR timestamp må være sender-header-aktig:
//   - empty, ELLER
//   - kort (< 30 tegn) og starter med stor bokstav
// Inline-referanser som "se 14:21 i morgen" har lang tekst eller lowercase start
// og blir avvist (vi vil ikke splitte meldingen der).
func findRealTimestamp(in line: String) -> Range<String.Index>? {
    let r = NSRange(line.startIndex..., in: line)
    guard let m = tcRegex.firstMatch(in: line, range: r),
          let tcR = Range(m.range, in: line) else { return nil }
    let textBefore = String(line[..<tcR.lowerBound])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if textBefore.isEmpty { return tcR }

    // Klart body content hvis: prefix er lang ELLER starter med lowercase
    if textBefore.count > 30 { return nil }
    if let first = textBefore.first, first.isLowercase { return nil }

    return tcR
}

// Range-pattern: starter med "-HH:MM" eller "—HH:MM" (etter første TC)
// Brukes til å strippe end-tiden i intervaller som "17:35-17:55 noe skjedde"
let rangePattern = try! NSRegularExpression(
    pattern: #"^\s*[-–—til ]+\s*\d{1,2}[:.]\d{2}(?:[:.]\d{2})?\s*"#,
    options: [.caseInsensitive]
)

// Strips Norwegian short-date prefixes like "15/5.", "15/5,", "15.5." etc.
let datePrefixRegex = try! NSRegularExpression(
    pattern: #"^\s*\d{1,2}\s*[/.\-]\s*\d{1,2}\s*[.,:\-\s]*"#
)
// Norsk + engelske månedsnavn
private let monthNames = #"(jan(uar(y)?)?|feb(ruar(y)?)?|mar(ch|s)?|apr(il)?|mai|may|mal|jun(i|e)?|jul(i|y)?|aug(ust)?|sep(t(ember)?)?|okt|oct(ober)?|nov(ember)?|des(ember)?|dec(ember)?)"#

let dateMonthPrefixRegex = try! NSRegularExpression(
    pattern: "^\\s*\\d{1,2}\\.?\\s*\(monthNames)\\.?[,.\\s]*",
    options: [.caseInsensitive]
)
let dateAnywhereRegex = try! NSRegularExpression(
    pattern: "\\s*\\d{1,2}\\.?\\s*\(monthNames)\\.?\\s*",
    options: [.caseInsensitive]
)
let dateSlashAnywhereRegex = try! NSRegularExpression(
    pattern: #"\s*\d{1,2}\s*[/]\s*\d{1,2}\s*"#
)
// Teams system-meldinger.
// Format: "{Avsender-navn} added/removed/left/joined ... [to the chat] [shared all chat history]"
// Vi fanger også navn-prefixen ("Selma Knudsen added ...") så det strippes komplett.
let teamsSystemMsgRegex = try! NSRegularExpression(
    pattern: #"\b(?:[A-ZÆØÅ][\p{L}]+(?:\s+[A-ZÆØÅ][\p{L}]+){0,2}\s+)?(added\s+.{1,150}?to\s+the\s+chat(?:\s+(?:and\s+)?shared\s+all\s+chat\s+history)?|shared\s+all\s+chat\s+history|left\s+the\s+chat|joined\s+the\s+chat|removed\s+.{1,100}?from\s+the\s+chat)\b"#,
    options: [.caseInsensitive]
)
// Hengende fragmenter som blir igjen etter system-stripping
// Eks: "& Selma Knudsen and", "and Gorm Huse and"
let danglingFragmentRegex = try! NSRegularExpression(
    pattern: #"(?:^|\s)(?:[&]|\band\b|\bog\b)\s+[A-ZÆØÅ][\p{L}]+(?:\s+[A-ZÆØÅ][\p{L}]+){0,3}\s+(?:[&]|\band\b|\bog\b)\b"#,
    options: [.caseInsensitive]
)
// Også email-adresser som rester av system-meldinger
let emailRegex = try! NSRegularExpression(
    pattern: #"\b[\w.+-]+@[\w-]+\.[\w.-]+\b"#
)
// Strips leading punctuation/quotes/whitespace
let leadingJunkRegex = try! NSRegularExpression(
    pattern: #"^[\s,.;:\-–—|·•"'`«»\]\)]+"#
)
// Strips trailing junk
let trailingJunkRegex = try! NSRegularExpression(
    pattern: #"[\s,;:\-–—|·•"'`«»\[\(]+$"#
)
// Teams UI noise words (often appear next to author name as hover/menu items)
let teamsUiNoiseRegex = try! NSRegularExpression(
    pattern: #"\b(edited|transials|translate|translation|translated|reply|forwarded|reageringer|reactions|pinned)\b"#,
    options: [.caseInsensitive]
)
// Whole-line: just a date header like "15 mai" / "15. mai" / "15 mal"
let dateOnlyRegex = try! NSRegularExpression(
    pattern: #"^\d{1,2}\.?\s*(jan(uar)?|feb(ruar)?|mar(s)?|apr(il)?|mai|mal|jun(i)?|jul(i)?|aug(ust)?|sep(tember)?|okt(ober)?|nov(ember)?|des(ember)?)\.?$"#,
    options: [.caseInsensitive]
)
// Whole-line: just looks like "FirstName LastName" (1-3 capitalised words)
let nameOnlyRegex = try! NSRegularExpression(
    pattern: #"^[A-ZÆØÅ][\p{L}]+(\s+[A-ZÆØÅ][\p{L}]+){0,2}$"#
)

func cleanComment(_ raw: String) -> String {
    var c = raw.trimmingCharacters(in: .whitespacesAndNewlines)

    // Strip Teams system-meldinger først (kan inneholde emails/navn)
    var rAny = NSRange(c.startIndex..., in: c)
    c = teamsSystemMsgRegex.stringByReplacingMatches(in: c, range: rAny, withTemplate: " ")
    // Strip email-adresser (kan være rester)
    rAny = NSRange(c.startIndex..., in: c)
    c = emailRegex.stringByReplacingMatches(in: c, range: rAny, withTemplate: " ")
    // Strip dato-mønstre ("16. mai", "16 May", "15/5")
    rAny = NSRange(c.startIndex..., in: c)
    c = dateAnywhereRegex.stringByReplacingMatches(in: c, range: rAny, withTemplate: " ")
    rAny = NSRange(c.startIndex..., in: c)
    c = dateSlashAnywhereRegex.stringByReplacingMatches(in: c, range: rAny, withTemplate: " ")
    // Strip hengende fragmenter ("& Selma Knudsen and") — kjør flere ganger
    for _ in 0..<3 {
        rAny = NSRange(c.startIndex..., in: c)
        let before = c
        c = danglingFragmentRegex.stringByReplacingMatches(in: c, range: rAny, withTemplate: " ")
        if c == before { break }
    }

    // Three passes: strip leading junk, then date prefix, then leading junk again
    for _ in 0..<3 {
        let before = c
        var r = NSRange(c.startIndex..., in: c)
        c = leadingJunkRegex.stringByReplacingMatches(in: c, range: r, withTemplate: "")
        r = NSRange(c.startIndex..., in: c)
        c = datePrefixRegex.stringByReplacingMatches(in: c, range: r, withTemplate: "")
        r = NSRange(c.startIndex..., in: c)
        c = dateMonthPrefixRegex.stringByReplacingMatches(in: c, range: r, withTemplate: "")
        if c == before { break }
    }
    // Remove Teams UI noise words anywhere in the comment
    var r = NSRange(c.startIndex..., in: c)
    c = teamsUiNoiseRegex.stringByReplacingMatches(in: c, range: r, withTemplate: "")
    // Collapse double whitespace
    c = c.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    // Trailing junk
    r = NSRange(c.startIndex..., in: c)
    c = trailingJunkRegex.stringByReplacingMatches(in: c, range: r, withTemplate: "")
    return c.trimmingCharacters(in: .whitespacesAndNewlines)
}

// A comment is "uninteresting" if it's just a name, a date, or too short.
// Used to decide whether to look ahead to the next line for the real message.
func isUninteresting(_ s: String) -> Bool {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.count < 4 { return true }
    let r = NSRange(trimmed.startIndex..., in: trimmed)
    if dateOnlyRegex.firstMatch(in: trimmed, range: r) != nil { return true }
    if nameOnlyRegex.firstMatch(in: trimmed, range: r) != nil { return true }
    return false
}

func isJunkComment(_ s: String) -> Bool {
    return isUninteresting(s)
}

// Norsk + engelske månedsnavn → tallverdi. "mal" = OCR-feil for "mai".
private let monthNumberMap: [String: Int] = [
    "jan": 1, "januar": 1, "january": 1,
    "feb": 2, "februar": 2, "february": 2,
    "mar": 3, "mars": 3, "march": 3,
    "apr": 4, "april": 4,
    "mai": 5, "may": 5, "mal": 5,
    "jun": 6, "juni": 6, "june": 6,
    "jul": 7, "juli": 7, "july": 7,
    "aug": 8, "august": 8,
    "sep": 9, "sept": 9, "september": 9,
    "okt": 10, "oct": 10, "oktober": 10, "october": 10,
    "nov": 11, "november": 11,
    "des": 12, "dec": 12, "desember": 12, "december": 12
]
// Hel-linje "15 mai" / "15. mai" / "15. mai 2024"
private let dateHeaderRegex = try! NSRegularExpression(
    pattern: #"^\s*(\d{1,2})\.?\s*([A-Za-zæøåÆØÅ]+)\.?(?:\s+\d{2,4})?\s*$"#,
    options: [.caseInsensitive]
)
// Hel-linje "15/5" / "15.5" / "15/5/24"
private let dateSlashHeaderRegex = try! NSRegularExpression(
    pattern: #"^\s*(\d{1,2})\s*[/.\-]\s*(\d{1,2})(?:\s*[/.\-]\s*\d{2,4})?\s*$"#
)
// Prefiks-mønstre (start av body) — fanger "15. mai, ..." / "15/5. ..."
// Tillater ledende komma/punktum/space slik at vi også fanger datoer som står
// rett etter TC: "21:18, 15/5. body..." → bodyen starter med ", 15/5."
private let dateInlinePrefixRegex = try! NSRegularExpression(
    pattern: #"^[\s,.;:\-–—|]*(\d{1,2})\.?\s*([A-Za-zæøåÆØÅ]+)\.?[,.\s]"#,
    options: [.caseInsensitive]
)
private let dateSlashInlinePrefixRegex = try! NSRegularExpression(
    pattern: #"^[\s,.;:\-–—|]*(\d{1,2})\s*[/.\-]\s*(\d{1,2})[,.\s]"#
)

// Returner "DD/M" hvis linja er en ren dato-header, ellers nil.
func parseDateHeader(from line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let r = NSRange(trimmed.startIndex..., in: trimmed)

    if let m = dateHeaderRegex.firstMatch(in: trimmed, range: r),
       let dayR = Range(m.range(at: 1), in: trimmed),
       let monthR = Range(m.range(at: 2), in: trimmed) {
        let day = Int(trimmed[dayR]) ?? 0
        let mn = String(trimmed[monthR]).lowercased()
        if let month = monthNumberMap[mn], (1...31).contains(day) {
            return "\(day)/\(month)"
        }
    }
    if let m = dateSlashHeaderRegex.firstMatch(in: trimmed, range: r),
       let dayR = Range(m.range(at: 1), in: trimmed),
       let monthR = Range(m.range(at: 2), in: trimmed) {
        let day = Int(trimmed[dayR]) ?? 0
        let month = Int(trimmed[monthR]) ?? 0
        if (1...31).contains(day) && (1...12).contains(month) {
            return "\(day)/\(month)"
        }
    }
    return nil
}

// Returner "DD/M" hvis body starter med en dato (inline-prefiks), ellers nil.
func parseDatePrefix(from body: String) -> String? {
    let r = NSRange(body.startIndex..., in: body)
    if let m = dateInlinePrefixRegex.firstMatch(in: body, range: r),
       let dayR = Range(m.range(at: 1), in: body),
       let monthR = Range(m.range(at: 2), in: body) {
        let day = Int(body[dayR]) ?? 0
        let mn = String(body[monthR]).lowercased()
        if let month = monthNumberMap[mn], (1...31).contains(day) {
            return "\(day)/\(month)"
        }
    }
    if let m = dateSlashInlinePrefixRegex.firstMatch(in: body, range: r),
       let dayR = Range(m.range(at: 1), in: body),
       let monthR = Range(m.range(at: 2), in: body) {
        let day = Int(body[dayR]) ?? 0
        let month = Int(body[monthR]) ?? 0
        if (1...31).contains(day) && (1...12).contains(month) {
            return "\(day)/\(month)"
        }
    }
    return nil
}

func parseTeamsLines(_ lines: [String]) -> [(tc: String, comment: String, date: String, truncated: Bool)] {
    var rows: [(tc: String, comment: String, date: String, truncated: Bool)] = []
    // Aktiv akkumulator: TC + pieces av body som hører til denne markeren
    var currentTC: String? = nil
    var currentPieces: [String] = []
    var currentDate: String = ""

    func flush() {
        guard let tc = currentTC else { return }
        let joined = currentPieces.joined(separator: " ")
        // Hvis body starter med en dato-prefiks, oppdater currentDate FØR cleaning.
        if let bodyDate = parseDatePrefix(from: joined) {
            currentDate = bodyDate
        }
        let comment = cleanComment(joined)
        if !comment.isEmpty && !isUninteresting(comment) {
            rows.append((tc: tc, comment: comment, date: currentDate, truncated: false))
        }
        currentTC = nil
        currentPieces = []
    }

    for line in lines {
        // Date-header-linje? ("15. mai", "16/5") — oppdater currentDate, hopp over.
        if let d = parseDateHeader(from: line) {
            currentDate = d
            continue
        }

        let r = NSRange(line.startIndex..., in: line)
        let matches = tcRegex.matches(in: line, range: r)

        if matches.isEmpty {
            // Ingen TC i linja — alt er body for nåværende marker (hvis noen)
            if currentTC != nil {
                currentPieces.append(line)
            }
            continue
        }

        // For hver TC funnet på linja: finaliser nåværende marker (med tekst før TC
        // som body), så start en ny.
        var lastEnd = line.startIndex
        for m in matches {
            guard let tcR = Range(m.range, in: line) else { continue }
            // Tekst fra lastEnd til denne TC hører til NÅVÆRENDE marker
            let segment = String(line[lastEnd..<tcR.lowerBound])
            if currentTC != nil {
                currentPieces.append(segment)
            }
            flush()
            // Start ny
            currentTC = String(line[tcR]).replacingOccurrences(of: ".", with: ":")
            currentPieces = []
            lastEnd = tcR.upperBound

            // Range-mønster: "17:35-17:55 ..." → strip "-17:55"
            let rest = String(line[lastEnd...])
            if let rm = rangePattern.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
               let rr = Range(rm.range, in: rest),
               rr.lowerBound == rest.startIndex {
                lastEnd = rest.index(lastEnd, offsetBy: rest.distance(from: rest.startIndex, to: rr.upperBound))
            }
        }
        // Rest av linja etter siste TC går til den nylig opprettede markeren
        if currentTC != nil {
            currentPieces.append(String(line[lastEnd...]))
        }
    }
    flush()

    // ── Statistisk sender-detektor ──────────────────────────────────────────
    // Finn navn-mønstre (1-3 capitalized ord) som dukker opp som SISTE ORD
    // i mange kommentarer. Hvis "Håkon Bolstad" står på slutten av >=3 rader,
    // er det åpenbart sender-navnet, ikke body content → stripp det.
    rows = stripCommonSenders(rows)

    // ── Filtrer ut tomme/sender-only rader ──────────────────────────────────
    // Detekter dominante sender-navn fra alle kommentarer for å droppe rader
    // som BARE er "Håkon Bolstad e" o.l. (uten ekte body content).
    let senderNames = detectSenderNames(rows)
    rows = rows.filter { row in
        let cleaned = stripSenderAndNoise(row.comment, senderNames: senderNames)
        // Drop bare hvis essensielt ingen meningsfull tekst igjen
        return cleaned.count >= 2
    }

    // ── Truncation-flagg ────────────────────────────────────────────────────
    // Bruker smartere detektor — kun varsel hvis kommentaren STERKT ser ut
    // som kuttet (stopword-ending, bindestrek osv.), ikke bare mangler punktum
    for k in 0..<rows.count {
        rows[k].truncated = looksTruncated(rows[k].comment)
    }

    return rows
}

// Detekter dominante sender-navn i hele datasettet (1-3 cap-ord patterns som
// dukker opp i mange rader, ikke bare på slutten).
private func detectSenderNames(_ rows: [(tc: String, comment: String, date: String, truncated: Bool)]) -> Set<String> {
    guard rows.count >= 3 else { return [] }
    var counts: [String: Int] = [:]
    for row in rows {
        let words = row.comment.split(separator: " ").map(String.init)
        for length in [3, 2] {
            for i in 0...(max(0, words.count - length)) {
                let slice = Array(words[i..<min(i+length, words.count)])
                if let pat = nameFromWords(slice) {
                    counts[pat, default: 0] += 1
                }
            }
        }
    }
    return Set(counts.filter { $0.value >= 3 }.keys)
}

private func nameFromWords(_ words: [String]) -> String? {
    guard !words.isEmpty else { return nil }
    var clean: [String] = []
    for w in words {
        let stripped = w.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
        guard !stripped.isEmpty, let first = stripped.first, first.isUppercase else { return nil }
        for ch in stripped where !ch.isLetter { return nil }
        clean.append(stripped)
    }
    return clean.joined(separator: " ")
}

// Sjekk om kommentar er essentially bare et sender-navn + noise (e/Ca/etc)
private func stripSenderAndNoise(_ comment: String, senderNames: Set<String>) -> String {
    var c = comment.trimmingCharacters(in: .whitespacesAndNewlines)
    // Strip kjente sender-navn (uansett posisjon)
    for sender in senderNames {
        c = c.replacingOccurrences(of: sender, with: "")
    }
    // Strip vanlige OCR-rester ("e", "Ca", "Tom")
    c = c.replacingOccurrences(of: #"\b(e|Ca|Tom)\b"#, with: "", options: .regularExpression)
    // Strip alle ikke-bokstaver så vi sitter igjen med ren tekst
    c = c.replacingOccurrences(of: #"[^\p{L}]"#, with: "", options: .regularExpression)
    return c
}

// OCR-rester som ofte henger igjen rett etter sender-navn ("Håkon Bolstad e Ca")
private let ocrNoiseWords: Set<String> = ["e", "Ca", "Tom", "Translate", "Translation", "Edited"]

private func stripCommonSenders(_ input: [(tc: String, comment: String, date: String, truncated: Bool)])
    -> [(tc: String, comment: String, date: String, truncated: Bool)]
{
    guard input.count >= 2 else { return input }

    // Tell ALLE 2-3-ords cap-mønstre i HELE teksten (uansett posisjon).
    // Sender-navnet vil dukke opp i nesten alle kommentarer.
    var counts2: [String: Int] = [:]
    var counts3: [String: Int] = [:]
    for row in input {
        let words = row.comment.split(separator: " ").map(String.init)
        for i in 0..<words.count {
            if let p = nameAt(words, start: i, length: 2) { counts2[p, default: 0] += 1 }
            if let p = nameAt(words, start: i, length: 3) { counts3[p, default: 0] += 1 }
        }
    }
    // Threshold: ≥30% av radene må inneholde mønsteret for å regnes som sender
    let threshold = max(2, input.count / 3)
    var senders: Set<String> = Set(counts3.filter { $0.value >= threshold }.keys)
    senders.formUnion(counts2.filter { $0.value >= threshold }.keys)

    var output = input
    for k in 0..<output.count {
        var c = output[k].comment
        // Strip ALLE forekomster av sender-navn (uansett posisjon i kommentaren)
        for sender in senders {
            c = c.replacingOccurrences(of: sender, with: " ")
        }
        // Strip "e", "Ca" osv. som ofte henger igjen (kun som hele ord)
        c = c.replacingOccurrences(of: #"\b(e|Ca|Tom|Translate|Translation|Edited)\b"#,
                                    with: " ", options: .regularExpression)
        // Rydd dobbel whitespace og leading/trailing punctuation
        c = c.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        c = c.trimmingCharacters(in: .whitespacesAndNewlines)
        c = c.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:.-"))
        output[k].comment = c
    }
    return output
}

// Returnerer N ord starting at index hvis alle starter med stor bokstav (navn-mønster)
private func nameAt(_ words: [String], start: Int, length: Int) -> String? {
    guard start + length <= words.count else { return nil }
    var clean: [String] = []
    for i in start..<(start + length) {
        let stripped = words[i].trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
        guard !stripped.isEmpty, let first = stripped.first, first.isUppercase else { return nil }
        for ch in stripped where !ch.isLetter { return nil }
        // Skip 1-bokstavs ord (filtrerer ut "e", "I", etc)
        if stripped.count < 2 { return nil }
        clean.append(stripped)
    }
    return clean.joined(separator: " ")
}

private func endsWithTerminalPunctuation(_ s: String) -> Bool {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if let last = trimmed.last {
        return ".!?:".contains(last)
    }
    return false
}

// Returnerer true hvis kommentaren ENDER på en måte som sterkt tyder på
// avkutting (ikke bare manglende punktum — folk skriver Teams uten det).
// Triggere: siste ord er en stopword/konjunksjon, eller slutter med bindestrek,
// eller siste "ord" er ufullstendig (kun 1 bokstav).
private func looksTruncated(_ s: String) -> Bool {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    if endsWithTerminalPunctuation(trimmed) { return false }

    // Ender på bindestrek/em-dash → avkuttet
    if let last = trimmed.last, "-–—,".contains(last) { return true }

    // Ta siste ord (etter siste mellomrom)
    let words = trimmed.split(separator: " ").map(String.init)
    guard let lastRaw = words.last else { return false }
    let lastWord = lastRaw
        .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
        .lowercased()
    guard !lastWord.isEmpty else { return false }

    // Norsk + engelske stopword/konjunksjoner som SJELDEN avslutter en setning
    let stopwords: Set<String> = [
        "og", "i", "på", "til", "for", "med", "som", "at", "eller", "men",
        "av", "har", "var", "kan", "vil", "skal", "om", "den", "det",
        "en", "et", "de", "er", "å", "vi", "du", "han", "hun",
        "and", "or", "the", "a", "to", "of", "in", "for", "with", "by"
    ]
    if stopwords.contains(lastWord) { return true }

    // Siste ord kun 1 bokstav (uten å være "å" eller "i" som er gyldige norske ord)
    if lastWord.count == 1 && !["a", "i", "å"].contains(lastWord) { return true }

    return false
}

func csvEscape(_ s: String) -> String {
    if s.contains(",") || s.contains("\"") || s.contains("\n") {
        return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return s
}

// Ekstraherer "NOTE: ..."-del fra kommentar. Returnerer tom streng hvis ingen.
// NOTE-en blir IKKE fjernet fra original-kommentaren (slik at Premiere-plugin
// fortsatt viser hele teksten).
func extractNote(from comment: String) -> String {
    let pattern = #"\bNOTE\s*:\s*(.+?)\s*$"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
          let m = regex.firstMatch(in: comment, range: NSRange(comment.startIndex..., in: comment)),
          let r = Range(m.range(at: 1), in: comment)
    else { return "" }
    return String(comment[r]).trimmingCharacters(in: .whitespacesAndNewlines)
}

// ─── GLM-5 MODAL PRIMITIVES ──────────────────────────────────────────────────
struct ModalShell<Content: View>: View {
    let title: String
    let subtitle: String?
    @Binding var isPresented: Bool
    var footer: AnyView? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.ink)
                    if let s = subtitle {
                        Text(s)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.inkFaded)
                    }
                }
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13))
                        .foregroundColor(.inkFaded)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.divider).frame(height: 1)
            }

            // Body
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    content()
                }
                .padding(24)
            }

            // Footer (optional)
            if let f = footer {
                f
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(Color.glassBgSub)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.divider).frame(height: 1)
                    }
            }
        }
        .frame(width: 520, height: 620)
        .background(
            ZStack {
                Color.white.opacity(0.88)
                Rectangle().fill(.ultraThinMaterial)
            }
        )
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundColor(.inkFaded)
    }
}

// Radio card med tittel + beskrivelse
struct RadioCard<T: Hashable>: View {
    let value: T
    @Binding var selection: T
    let title: String
    let desc: String
    @State private var hover = false

    private var selected: Bool { selection == value }

    var body: some View {
        Button {
            selection = value
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(selected ? Color.brandAccent : Color.line, lineWidth: 2)
                        .frame(width: 18, height: 18)
                    if selected {
                        Circle()
                            .fill(Color.brandAccent)
                            .frame(width: 8, height: 8)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.ink)
                    Text(desc)
                        .font(.system(size: 12))
                        .foregroundColor(.inkFaded)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? Color.brandAccentDim : Color.glassBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? Color.brandAccent : Color.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct ToggleRow: View {
    let label: String
    let sublabel: String?
    @Binding var isOn: Bool
    var disabled: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.ink)
                if let s = sublabel {
                    Text(s)
                        .font(.system(size: 12))
                        .foregroundColor(.inkFaded)
                }
            }
            Spacer()
            CapsuleToggle(isOn: $isOn, disabled: disabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.glassBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.line, lineWidth: 1)
        )
    }
}

struct CapsuleToggle: View {
    @Binding var isOn: Bool
    var disabled: Bool = false

    var body: some View {
        Button {
            if !disabled { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Color.brandAccent : Color.bgSecondary)
                    .frame(width: 44, height: 24)
                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .padding(3)
            }
            .opacity(disabled ? 0.55 : 1)
            .animation(.easeOut(duration: 0.18), value: isOn)
        }
        .buttonStyle(.plain)
    }
}

// ─── INFO SHEET (GLM-5) ──────────────────────────────────────────────────────
struct InfoSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        ModalShell(title: "Om", subtitle: nil, isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 20) {
                // Logo + name + version
                HStack(spacing: 14) {
                    ClapperboardLogo(size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TeamsToMarkers")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.ink)
                        Text("\(appVersionLabel)-beta")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.inkFaded)
                    }
                }

                Text("Konverterer Microsoft Teams chat-screenshots til rene CSV-filer med timecodes for video-redigerings-arbeidsflyter.")
                    .font(.system(size: 13))
                    .foregroundColor(.inkSoft)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                // Privacy list med grønne ikoner
                VStack(spacing: 0) {
                    privacyItem(icon: "shield.fill",
                                title: "All OCR kjøres lokalt",
                                desc: "Ingen internett-forbindelse nødvendig for prosessering")
                    Divider().background(Color.divider)
                    privacyItem(icon: "lock.fill",
                                title: "Null data forlater enheten",
                                desc: "Ingen telemetri, ingen analytics, ingen sky-opplastinger")
                    Divider().background(Color.divider)
                    privacyItem(icon: "doc.fill",
                                title: "Kildefiler endres aldri",
                                desc: "Original-screenshots forblir urørte")
                }

                // Contact
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Kontakt")
                    Text("ENSAMBLE AS · victoria@ensamble.no")
                        .font(.system(size: 13))
                        .foregroundColor(.brandAccent)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func privacyItem(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: 0.133, green: 0.773, blue: 0.369).opacity(0.10))
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(Color(red: 0.086, green: 0.639, blue: 0.290))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.ink)
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundColor(.inkFaded)
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }
}

// ─── SETTINGS SHEET (GLM-5 radio-cards) ──────────────────────────────────────
struct SettingsSheet: View {
    @EnvironmentObject var updater: UpdateChecker
    @Binding var isPresented: Bool
    @Binding var engine: OCREngine
    @Binding var tesseractFallback: Bool
    @Binding var saveLocationMode: SaveLocationMode
    @Binding var customSavePath: String
    @Binding var exportPDF: Bool
    @Binding var exportXLSX: Bool

    @State private var csvOnDummy = true

    var body: some View {
        ModalShell(title: "Innstillinger", subtitle: nil, isPresented: $isPresented) {
            // OCR Engine
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "OCR-motor")
                VStack(spacing: 8) {
                    RadioCard(value: .tesseract, selection: $engine,
                              title: "Tesseract",
                              desc: "Open-source, multilingual, best på norske tegn")
                    RadioCard(value: .vision, selection: $engine,
                              title: "Apple Vision",
                              desc: "macOS-innebygd, rask, høy nøyaktighet")
                }
                if engine == .tesseract && tesseractPath == nil {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.brandAccent)
                            .font(.system(size: 11))
                        Text("Tesseract ikke installert. Installeres via Homebrew.")
                            .font(.system(size: 12))
                            .foregroundColor(.inkSoft)
                    }
                }
            }

            // Processing
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Prosessering")
                ToggleRow(
                    label: "Fallback ved feil",
                    sublabel: "Bruk Apple Vision hvis Tesseract feiler",
                    isOn: $tesseractFallback
                )
            }

            // Save Location
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Lagringsplassering")
                VStack(spacing: 8) {
                    RadioCard(value: .alongside, selection: $saveLocationMode,
                              title: "Ved siden av kilden",
                              desc: "Lagre CSV i samme mappe som originalbildet")
                    RadioCard(value: .custom, selection: $saveLocationMode,
                              title: "Egen mappe",
                              desc: "Velg en spesifikk output-mappe")
                }
                if saveLocationMode == .custom {
                    HStack(spacing: 8) {
                        Text(customSavePath.isEmpty ? "Ingen mappe valgt" : customSavePath)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(customSavePath.isEmpty ? .inkFaded : .inkSoft)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.glassBgEl)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.line, lineWidth: 1)
                            )
                        Button("Velg…") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let url = panel.url {
                                customSavePath = url.path
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.glassBg)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.line, lineWidth: 1)
                        )
                    }
                }
            }

            // Export formats
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Eksportformater")
                VStack(spacing: 8) {
                    ToggleRow(label: "CSV", sublabel: "Alltid på", isOn: $csvOnDummy, disabled: true)
                    ToggleRow(label: "PDF Report", sublabel: "Generer formatert PDF sammen med CSV", isOn: $exportPDF)
                    ToggleRow(label: "XLSX Spreadsheet", sublabel: "Excel-kompatibelt format", isOn: $exportXLSX)
                }
            }

            // Updates
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Oppdatering")
                HStack(spacing: 8) {
                    Text("Nåværende:")
                        .font(.system(size: 12))
                        .foregroundColor(.inkFaded)
                    Text(appVersionLabel)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.ink)
                    Spacer()
                    if let v = updater.availableVersion {
                        Button("Installer \(v)") {
                            Task { await updater.installUpdate() }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.brandAccent)
                        )
                        .shadow(color: Color.brandAccentGlow, radius: 6, y: 3)
                    } else {
                        Button(updater.isChecking ? "Sjekker…" : "Sjekk nå") {
                            Task { await updater.checkForUpdate() }
                        }
                        .disabled(updater.isChecking)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.glassBg)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.line, lineWidth: 1)
                        )
                    }
                }
            }
        }
    }
}

// ─── PDF WRITER ──────────────────────────────────────────────────────────────
func writePDF(rows: [(tc: String, comment: String)], title: String, to url: URL) throws {
    let pageW: CGFloat = 595, pageH: CGFloat = 842    // A4
    let margin: CGFloat = 40
    let tcColW: CGFloat = 70
    let gap: CGFloat = 12
    let commentX = margin + tcColW + gap
    let commentW = pageW - commentX - margin

    var mediaBox = CGRect(x: 0, y: 0, width: pageW, height: pageH)
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
          let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        throw NSError(domain: "pdf", code: 0)
    }

    let titleFont = NSFont.boldSystemFont(ofSize: 14)
    let tcFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
    let textFont = NSFont.systemFont(ofSize: 10)
    let headerFont = NSFont.systemFont(ofSize: 9, weight: .semibold)

    func newPage() -> CGFloat {
        ctx.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        var y = pageH - margin
        let titleStr = NSAttributedString(string: title, attributes: [
            .font: titleFont,
            .foregroundColor: NSColor.black
        ])
        titleStr.draw(at: CGPoint(x: margin, y: y - titleFont.ascender))
        y -= 26
        let header = NSAttributedString(string: "TIMECODE    KOMMENTAR", attributes: [
            .font: headerFont,
            .foregroundColor: NSColor.gray,
            .kern: 1.0
        ])
        header.draw(at: CGPoint(x: margin, y: y - headerFont.ascender))
        y -= 16
        ctx.setStrokeColor(NSColor.gray.withAlphaComponent(0.4).cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: margin, y: y))
        ctx.addLine(to: CGPoint(x: pageW - margin, y: y))
        ctx.strokePath()
        y -= 8
        return y
    }
    var y: CGFloat = newPage()

    for row in rows {
        let tcStr = NSAttributedString(string: row.tc, attributes: [
            .font: tcFont,
            .foregroundColor: NSColor.systemOrange
        ])
        let textStyle = NSMutableParagraphStyle()
        textStyle.lineBreakMode = .byWordWrapping
        let commentStr = NSAttributedString(string: row.comment, attributes: [
            .font: textFont,
            .foregroundColor: NSColor.black,
            .paragraphStyle: textStyle
        ])

        let boundedRect = commentStr.boundingRect(
            with: CGSize(width: commentW, height: 9999),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let rowH = max(tcFont.ascender - tcFont.descender, boundedRect.height) + 6

        if y - rowH < margin {
            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
            y = newPage()
        }

        tcStr.draw(at: CGPoint(x: margin, y: y - tcFont.ascender))
        commentStr.draw(in: CGRect(x: commentX, y: y - boundedRect.height, width: commentW, height: boundedRect.height))
        y -= rowH
    }

    NSGraphicsContext.restoreGraphicsState()
    ctx.endPDFPage()
    ctx.closePDF()

    try data.write(to: url, options: .atomic)
}

// ─── XLSX WRITER ─────────────────────────────────────────────────────────────
// Builds a minimal valid .xlsx (which is a ZIP of XML files) using /usr/bin/zip.
func writeXLSX(rows: [(tc: String, comment: String)], to url: URL) throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("xlsx-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let relsDir = tmp.appendingPathComponent("_rels")
    let xlDir   = tmp.appendingPathComponent("xl")
    let xlRels  = xlDir.appendingPathComponent("_rels")
    let sheetsDir = xlDir.appendingPathComponent("worksheets")
    try fm.createDirectory(at: relsDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: xlRels, withIntermediateDirectories: true)
    try fm.createDirectory(at: sheetsDir, withIntermediateDirectories: true)

    let contentTypes = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>
"""
    try contentTypes.write(to: tmp.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)

    let rootRels = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
"""
    try rootRels.write(to: relsDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)

    let workbook = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets><sheet name="Markers" sheetId="1" r:id="rId1"/></sheets>
</workbook>
"""
    try workbook.write(to: xlDir.appendingPathComponent("workbook.xml"), atomically: true, encoding: .utf8)

    let workbookRels = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>
"""
    try workbookRels.write(to: xlRels.appendingPathComponent("workbook.xml.rels"), atomically: true, encoding: .utf8)

    func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    var sheetXML = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<cols><col min="1" max="1" width="14"/><col min="2" max="2" width="80"/></cols>
<sheetData>
<row r="1"><c r="A1" t="inlineStr"><is><t>Timecode</t></is></c><c r="B1" t="inlineStr"><is><t>Kommentar</t></is></c></row>
"""
    for (i, row) in rows.enumerated() {
        let r = i + 2
        sheetXML += "<row r=\"\(r)\"><c r=\"A\(r)\" t=\"inlineStr\"><is><t>\(xmlEscape(row.tc))</t></is></c><c r=\"B\(r)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xmlEscape(row.comment))</t></is></c></row>\n"
    }
    sheetXML += "</sheetData></worksheet>"
    try sheetXML.write(to: sheetsDir.appendingPathComponent("sheet1.xml"), atomically: true, encoding: .utf8)

    if fm.fileExists(atPath: url.path) {
        try fm.removeItem(at: url)
    }

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    proc.currentDirectoryURL = tmp
    proc.arguments = ["-rq", url.path, "[Content_Types].xml", "_rels", "xl"]
    proc.standardOutput = Pipe()
    proc.standardError = Pipe()
    try proc.run()
    proc.waitUntilExit()
    if proc.terminationStatus != 0 {
        throw NSError(domain: "xlsx", code: Int(proc.terminationStatus))
    }
}
