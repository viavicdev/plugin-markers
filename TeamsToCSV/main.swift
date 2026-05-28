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
    static let canvas      = Color(red: 0.13, green: 0.13, blue: 0.16)    // #21212A dark glass base
    static let card        = Color.white                                   // #FFFFFF
    static let cardBehind  = Color(red: 0.84, green: 0.84, blue: 0.88)    // #D6D6E0
    static let ink         = Color(red: 0.04, green: 0.04, blue: 0.04)    // #0A0A0A
    static let inkSoft     = Color(red: 0.36, green: 0.36, blue: 0.39)    // #5C5C63
    static let inkFaded    = Color(red: 0.60, green: 0.60, blue: 0.63)    // #999AA0
    static let line        = Color(red: 0.89, green: 0.89, blue: 0.92)    // #E2E2EA
    static let surfaceMute = Color(red: 0.96, green: 0.96, blue: 0.97)    // #F5F5F7
    static let brandAccent = Color(red: 0.859, green: 0.102, blue: 0.102) // #DB1A1A
    static let brandAccentDim = Color(red: 0.859, green: 0.102, blue: 0.102).opacity(0.10)

    // Tekstfarger som ligger DIREKTE på mørk canvas
    static let inkOnDark      = Color.white
    static let inkOnDarkSoft  = Color(red: 0.70, green: 0.70, blue: 0.75)  // #B3B3BF
    static let inkOnDarkFaded = Color(red: 0.50, green: 0.50, blue: 0.56)  // #80808F
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

// ─── FROSTED DARK GLASS BAKGRUNN ─────────────────────────────────────────────
struct NoiseBackground: View {
    let baseColor: Color
    private let noiseImage: NSImage = makeNoise(size: CGSize(width: 240, height: 240))

    var body: some View {
        ZStack {
            // Base dark
            baseColor

            // Soft radial highlight (som lys treffer glass) — øverst venstre
            RadialGradient(
                colors: [Color.white.opacity(0.10), Color.clear],
                center: UnitPoint(x: 0.2, y: 0.1),
                startRadius: 50,
                endRadius: 500
            )

            // Sekundær subtle accent-glød — nederst høyre
            RadialGradient(
                colors: [Color.brandAccent.opacity(0.06), Color.clear],
                center: UnitPoint(x: 0.95, y: 0.95),
                startRadius: 40,
                endRadius: 350
            )

            // Veldig subtil grain (frosted-feel uten å bli "kornet")
            Image(nsImage: noiseImage)
                .resizable(resizingMode: .tile)
                .opacity(0.08)
                .blendMode(.softLight)
                .allowsHitTesting(false)
        }
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
        VStack(spacing: 0) {
            header
            if updater.availableVersion != nil { updateBanner }
            dropZone
                .padding(20)
            Divider()
            resultsList
        }
        .background(NoiseBackground(baseColor: Color.canvas).ignoresSafeArea())
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

    // Header — hvit frosted-glass på toppen
    private var header: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                // Brand mark + tittel
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Circle().fill(Color.brandAccent).frame(width: 6, height: 6)
                        Text("RENDER")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(2.0)
                            .foregroundColor(.inkSoft)
                    }
                    HStack(spacing: 8) {
                        Text("Teams → CSV")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.ink)
                        BetaBadge(onLight: true)
                    }
                }
                Spacer()
                if processedFiles.count >= 2 {
                    Button {
                        mergeAllToCSV()
                    } label: {
                        Label("Slå sammen", systemImage: "rectangle.stack.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.brandAccent))
                    .help("Slå sammen alle filer til én CSV, sortert på dato + timecode")
                }
                if !processedFiles.isEmpty {
                    Button {
                        processedFiles.removeAll()
                        errorMessage = nil
                    } label: {
                        Label("Tøm", systemImage: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.inkSoft)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.05)))
                }
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(.inkSoft)
                .help("Innstillinger")

                Button {
                    showInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(.inkSoft)
                .help("Om / personvern")
            }

            // Subtil motor-indikator
            HStack(spacing: 8) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 10))
                Text(engineLabel)
                    .font(.system(size: 11))
                if engine == .tesseract && tesseractPath == nil && tesseractFallback {
                    Text("· faller tilbake til Apple Vision")
                        .font(.system(size: 11))
                        .foregroundColor(.brandAccent)
                }
                Spacer()
            }
            .foregroundColor(.inkFaded)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            ZStack {
                Color.white
                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        )
        .shadow(color: .black.opacity(0.10), radius: 10, y: 2)
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

    // Drop zone
    private var dropZone: some View {
        ZStack {
            // Semi-transparent fyll så glass-canvas skinner gjennom
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDragging
                      ? Color.brandAccent.opacity(0.15)
                      : Color.white.opacity(0.06))
                .shadow(color: .black.opacity(0.20), radius: 12, y: 4)

            // Tydeligere kant
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isDragging ? Color.brandAccent : Color.white.opacity(0.25),
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                )

            VStack(spacing: 8) {
                if isProcessing {
                    AnimationView(htmlName: "timeline-bw")
                        .frame(width: 140, height: 80)
                    Text("Kjører OCR...")
                        .font(.system(size: 13))
                        .foregroundColor(.inkOnDarkSoft)
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 36))
                        .foregroundColor(isDragging ? .brandAccent : .inkOnDarkSoft)
                    Text(isDragging ? "Slipp her" : "Dra PNG/JPG hit")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.inkOnDark)
                    Text("eller klikk for å velge filer")
                        .font(.system(size: 11))
                        .foregroundColor(.inkOnDarkFaded)
                }
            }
        }
        .frame(minHeight: 120, maxHeight: 140)
        .contentShape(Rectangle())
        .onTapGesture { selectFiles() }
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            loadDropped(providers: providers)
            return true
        }
    }

    // Results list
    @ViewBuilder
    private var resultsList: some View {
        if processedFiles.isEmpty && errorMessage == nil {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "doc.text")
                    .font(.system(size: 24))
                    .foregroundColor(.inkOnDarkFaded)
                Text("Ingen filer behandlet ennå")
                    .font(.system(size: 12))
                    .foregroundColor(.inkOnDarkSoft)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    if let err = errorMessage {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.brandAccent)
                            Text(err).font(.system(size: 12))
                            Spacer()
                            Button("✕") { errorMessage = nil }
                                .buttonStyle(.plain)
                                .foregroundColor(.inkSoft)
                        }
                        .padding(10)
                        .background(Color.brandAccentDim)
                        .cornerRadius(6)
                    }
                    ForEach($processedFiles) { $file in
                        FileRow(
                            file: $file,
                            onDownload: { saveCSV(file) },
                            onShowInFinder: { NSWorkspace.shared.activateFileViewerSelecting([file.csvURL]) },
                            onRemove: { processedFiles.removeAll { $0.id == file.id } }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
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
            let csv = "date,timecode,comment,note\n" + allRows.map {
                "\(csvEscape($0.date)),\($0.tc),\(csvEscape($0.comment)),\(csvEscape($0.note))"
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
            let csv = "date,timecode,comment,note\n" + file.rows.map {
                "\(csvEscape($0.date)),\($0.tc),\(csvEscape($0.comment)),\(csvEscape($0.note))"
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

// ─── BETA BADGE ──────────────────────────────────────────────────────────────
let appVersionLabel = "v1.20"

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

// ─── FILE ROW ────────────────────────────────────────────────────────────────
struct FileRow: View {
    @Binding var file: ProcessedFile
    let onDownload: () -> Void
    let onShowInFinder: () -> Void
    let onRemove: () -> Void
    @State private var showAll: Bool = false
    @State private var isEditing: Bool = false

    private let initialRows = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ── Header row ──
            HStack(spacing: 10) {
                if let thumb = file.thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 38, height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.line, lineWidth: 1)
                        )
                        .help("Klikk filnavnet for Quick Look av kilde-PNG")
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 14))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Button {
                        quickLook(file.pngURL)
                    } label: {
                        HStack(spacing: 4) {
                            Text(file.pngURL.lastPathComponent)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.ink)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Image(systemName: "eye")
                                .font(.system(size: 9))
                                .foregroundColor(.inkFaded)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Klikk for Quick Look av kilde-PNG")
                    HStack(spacing: 6) {
                        Text("\(file.markerCount) markers")
                            .font(.system(size: 11))
                            .foregroundColor(.inkSoft)
                        Text("·")
                            .foregroundColor(.inkSoft)
                        Text(file.csvURL.lastPathComponent)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.inkSoft)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()

                Button {
                    isEditing.toggle()
                } label: {
                    Label(isEditing ? "Ferdig" : "Rediger",
                          systemImage: isEditing ? "checkmark" : "pencil")
                }
                .controlSize(.small)

                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.inkSoft)
                .help("Fjern fra listen")
            }

            // ── Table preview ──
            CSVTablePreview(rows: $file.rows, showAll: $showAll, limit: initialRows, isEditing: isEditing)

            // ── Actions ──
            HStack(spacing: 8) {
                Button {
                    onDownload()
                } label: {
                    Label("Last ned CSV", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    onShowInFinder()
                } label: {
                    Label("Vis i Finder", systemImage: "folder")
                }
                .controlSize(.small)

                Spacer()

                if file.rows.count > initialRows {
                    Button {
                        showAll.toggle()
                    } label: {
                        Text(showAll ? "Vis færre" : "Vis alle (\(file.rows.count))")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.brandAccent)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.card)
                .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isEditing ? Color.brandAccent.opacity(0.5) : Color.line.opacity(0.5), lineWidth: 1)
        )
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

    // Lys grå palett
    private let bgColor       = Color(red: 0.96, green: 0.96, blue: 0.97)  // #F5F5F7 lys
    private let headerBg      = Color(red: 0.91, green: 0.91, blue: 0.93)  // #E8E8EE litt mørkere
    private let stripeBg      = Color(red: 0.94, green: 0.94, blue: 0.96)  // #F0F0F4
    private let lineColor     = Color(red: 0.82, green: 0.82, blue: 0.85)  // #D2D2D9
    private let textColor     = Color(red: 0.10, green: 0.10, blue: 0.12)  // #1A1A1F
    private let textSoftColor = Color(red: 0.40, green: 0.40, blue: 0.43)  // #66666E

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                Text("DATO")
                    .frame(width: 55, alignment: .leading)
                Rectangle().fill(lineColor).frame(width: 1)
                Text("TIMECODE")
                    .frame(width: 130, alignment: .leading)
                    .padding(.leading, 10)
                Rectangle().fill(lineColor).frame(width: 1)
                Text("KOMMENTAR")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10)
                if isEditing {
                    Text("").frame(width: 28)
                }
            }
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1.0)
            .foregroundColor(textSoftColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(headerBg)
            .overlay(
                Rectangle().fill(lineColor).frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            )

            // Rader
            ForEach(0..<visibleCount, id: \.self) { idx in
                HStack(alignment: .top, spacing: 0) {
                    if isEditing {
                        TextField("DD/M", text: $rows[idx].date)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(textSoftColor)
                            .frame(width: 55, alignment: .leading)
                        Rectangle().fill(lineColor).frame(width: 1)
                        TextField("HH:MM:SS:FF", text: $rows[idx].tc)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.brandAccent)
                            .frame(width: 120, alignment: .leading)
                            .padding(.leading, 10)
                            .padding(.trailing, 4)
                        Rectangle().fill(lineColor).frame(width: 1)
                        HStack(alignment: .top, spacing: 6) {
                            TextField("Kommentar", text: $rows[idx].comment, axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                                .foregroundColor(textColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1...50)
                            if rows[idx].truncated {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(Color(red: 0.95, green: 0.70, blue: 0.10))
                                    .font(.system(size: 11))
                                    .help("Slutter midt i setning — kan være kuttet.")
                                    .padding(.top, 1)
                            }
                        }
                        .padding(.leading, 10)
                        Button {
                            if let realIdx = rows.firstIndex(where: { $0.id == rows[idx].id }) {
                                rows.remove(at: realIdx)
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundColor(textSoftColor)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 28)
                    } else {
                        Text(rows[idx].date)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(textSoftColor)
                            .frame(width: 55, alignment: .leading)
                        Rectangle().fill(lineColor).frame(width: 1)
                        Text(rows[idx].tc)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.brandAccent)
                            .frame(width: 130, alignment: .leading)
                            .padding(.leading, 10)
                        Rectangle().fill(lineColor).frame(width: 1)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top, spacing: 6) {
                                Text(rows[idx].comment)
                                    .font(.system(size: 12))
                                    .foregroundColor(textColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                if rows[idx].truncated {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(Color(red: 0.95, green: 0.70, blue: 0.10))
                                        .font(.system(size: 11))
                                        .help("Slutter midt i setning — kan være kuttet. Sjekk i Rediger-modus.")
                                        .padding(.top, 2)
                                }
                            }
                            if !rows[idx].note.isEmpty {
                                HStack(alignment: .top, spacing: 6) {
                                    Text("NOTE")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .tracking(0.8)
                                        .foregroundColor(.brandAccent)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.brandAccent.opacity(0.10))
                                        .cornerRadius(3)
                                    Text(rows[idx].note)
                                        .font(.system(size: 11, design: .default).italic())
                                        .foregroundColor(textSoftColor)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(.leading, 10)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(idx % 2 == 0 ? bgColor : stripeBg)
                .overlay(
                    Rectangle().fill(lineColor.opacity(0.5)).frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                )
            }

            // Klikkbar expand-rad
            if !showAll && rows.count > limit {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showAll = true }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Vis alle \(rows.count) rader (+\(rows.count - limit))")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .foregroundColor(.brandAccent)
                    .background(headerBg)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if showAll && rows.count > limit {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showAll = false }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Vis færre")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .foregroundColor(.brandAccent)
                    .background(headerBg)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(bgColor)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isEditing ? Color.brandAccent.opacity(0.6) : lineColor, lineWidth: 1)
        )
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
    let csv = "date,timecode,comment,note\n" + parsed.map { p in
        let note = extractNote(from: p.comment)
        return "\(csvEscape(p.date)),\(p.tc),\(csvEscape(p.comment)),\(csvEscape(note))"
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

// ─── INFO SHEET ──────────────────────────────────────────────────────────────
struct InfoSheet: View {
    @Binding var isPresented: Bool
    var body: some View {
        VStack(spacing: 0) {
            // Fixed header
            HStack(spacing: 10) {
                Circle().fill(Color.brandAccent).frame(width: 8, height: 8)
                Text("RENDER")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2.4)
                    .foregroundColor(.inkOnDarkSoft)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.inkOnDarkSoft)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // Tittel
                    HStack(spacing: 10) {
                        Text("Teams → CSV")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.inkOnDark)
                            .tracking(-0.3)
                        BetaBadge()
                    }

                    Text("Konverterer Teams-screenshots til CSV med timecodes og kommentarer. CSV-en kan importeres i RENDER Multicam Markers-pluginen i Premiere Pro.")
                        .font(.system(size: 13))
                        .foregroundColor(.inkOnDarkSoft)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    InfoCard(title: "Personvern", icon: "lock.shield") {
                        VStack(alignment: .leading, spacing: 8) {
                            infoBullet("Alt OCR kjøres lokalt på din maskin")
                            infoBullet("Ingen bilder eller data sendes til skyen")
                            infoBullet("Ingen API-kall, ingen telemetri")
                            infoBullet("Source-PNGer modifiseres aldri")
                        }
                    }

                    InfoCard(title: "OCR-motorer", icon: "doc.text.viewfinder") {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Tesseract (norsk)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.inkOnDark)
                                Text("Standard. Best på norske tegn. Krever Homebrew (installeres automatisk av installer-en).")
                                    .font(.system(size: 11))
                                    .foregroundColor(.inkOnDarkSoft)
                                    .lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Apple Vision")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.inkOnDark)
                                Text("Innebygd i macOS. Brukes som fallback hvis Tesseract feiler.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.inkOnDarkSoft)
                            }
                        }
                    }

                    InfoCard(title: "Kontakt", icon: "envelope") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("© ENSAMBLE AS")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.inkOnDark)
                            Text("victoria@ensamble.no")
                                .font(.system(size: 12))
                                .foregroundColor(.brandAccent)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(width: 520, height: 600)
        .background(Color.canvas)
    }

    private func infoBullet(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.brandAccent)
                .padding(.top, 3)
            Text(s)
                .font(.system(size: 12))
                .foregroundColor(.inkOnDark)
                .lineSpacing(2)
            Spacer()
        }
    }
}

// Reusable card for info sections
struct InfoCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(.brandAccent)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundColor(.inkOnDarkSoft)
            }
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundColor(.brandAccent)
            content()
        }
        .padding(.bottom, 4)
    }
}

// ─── SETTINGS SHEET ──────────────────────────────────────────────────────────
struct SettingsSheet: View {
    @EnvironmentObject var updater: UpdateChecker
    @Binding var isPresented: Bool
    @Binding var engine: OCREngine
    @Binding var tesseractFallback: Bool
    @Binding var saveLocationMode: SaveLocationMode
    @Binding var customSavePath: String
    @Binding var exportPDF: Bool
    @Binding var exportXLSX: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Fixed header
            HStack(spacing: 10) {
                Circle().fill(Color.brandAccent).frame(width: 8, height: 8)
                Text("RENDER")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2.4)
                    .foregroundColor(.inkOnDarkSoft)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.inkOnDarkSoft)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Innstillinger")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.inkOnDark)
                        .tracking(-0.3)

                    InfoCard(title: "OCR-motor", icon: "doc.text.viewfinder") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("", selection: $engine) {
                                ForEach(OCREngine.allCases) { e in
                                    Text(e.rawValue).tag(e)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                            if engine == .tesseract {
                                if tesseractPath != nil {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.brandAccent)
                                            .font(.system(size: 11))
                                        Text("Tesseract er installert og klar.")
                                            .font(.system(size: 11))
                                            .foregroundColor(.inkOnDarkSoft)
                                    }
                                } else {
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.brandAccent)
                                            .font(.system(size: 11))
                                            .padding(.top, 1)
                                        Text("Tesseract ikke installert. Installeres med RENDER Suite Installer eller manuelt via Homebrew.")
                                            .font(.system(size: 11))
                                            .foregroundColor(.inkOnDarkSoft)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                Toggle(isOn: $tesseractFallback) {
                                    Text("Bruk Apple Vision som fallback hvis Tesseract feiler")
                                        .font(.system(size: 11))
                                        .foregroundColor(.inkOnDark)
                                }
                                .toggleStyle(.switch)
                                .controlSize(.small)
                            } else {
                                Text("Apple Vision er innebygd i macOS — fungerer alltid, men sliter mer med æ/ø/å.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.inkOnDarkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    InfoCard(title: "Lagringsplassering", icon: "folder") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("", selection: $saveLocationMode) {
                                ForEach(SaveLocationMode.allCases) { m in
                                    Text(m.label).tag(m)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                            if saveLocationMode == .custom {
                                HStack(spacing: 8) {
                                    Text(customSavePath.isEmpty ? "Ingen valgt" : customSavePath)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(customSavePath.isEmpty ? .inkOnDarkFaded : .inkOnDark)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(Color.white.opacity(0.06))
                                        .cornerRadius(4)
                                    Button("Velg mappe…") {
                                        let panel = NSOpenPanel()
                                        panel.canChooseFiles = false
                                        panel.canChooseDirectories = true
                                        panel.allowsMultipleSelection = false
                                        if panel.runModal() == .OK, let url = panel.url {
                                            customSavePath = url.path
                                        }
                                    }
                                    .controlSize(.small)
                                }
                            } else {
                                Text("Filene lagres i samme mappe som PNG-en.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.inkOnDarkSoft)
                            }
                        }
                    }

                    InfoCard(title: "Eksportformater", icon: "doc.on.doc") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.brandAccent)
                                    .font(.system(size: 11))
                                Text(".csv")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.inkOnDark)
                                Text("alltid på")
                                    .font(.system(size: 11))
                                    .foregroundColor(.inkOnDarkSoft)
                                Spacer()
                            }
                            Toggle(isOn: $exportPDF) {
                                HStack(spacing: 8) {
                                    Text(".pdf").font(.system(size: 12, design: .monospaced)).foregroundColor(.inkOnDark)
                                    Text("PDF-tabell").font(.system(size: 11)).foregroundColor(.inkOnDarkSoft)
                                }
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            Toggle(isOn: $exportXLSX) {
                                HStack(spacing: 8) {
                                    Text(".xlsx").font(.system(size: 12, design: .monospaced)).foregroundColor(.inkOnDark)
                                    Text("Excel-arbeidsbok").font(.system(size: 11)).foregroundColor(.inkOnDarkSoft)
                                }
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                    }

                    InfoCard(title: "Oppdatering", icon: "arrow.down.circle") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Text("Nåværende versjon:")
                                    .font(.system(size: 11))
                                    .foregroundColor(.inkOnDarkSoft)
                                Text(appVersionLabel)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.inkOnDark)
                            }
                            if let v = updater.availableVersion {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.down.circle.fill").foregroundColor(.brandAccent)
                                    Text("Ny versjon tilgjengelig: \(v)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.brandAccent)
                                }
                                Button("Installer ny versjon nå") {
                                    Task { await updater.installUpdate() }
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.brandAccent))
                            } else {
                                HStack(spacing: 6) {
                                    Button(updater.isChecking ? "Sjekker…" : "Sjekk for oppdatering") {
                                        Task { await updater.checkForUpdate() }
                                    }
                                    .disabled(updater.isChecking)
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.inkOnDark)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Color.white.opacity(0.10)))
                                    if let err = updater.errorMessage {
                                        Text(err).font(.system(size: 10)).foregroundColor(.brandAccent)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(width: 520, height: 700)
        .background(Color.canvas)
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
