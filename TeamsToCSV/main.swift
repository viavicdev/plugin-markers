// TeamsToCSV — drag-and-drop SwiftUI app for OCR-ing Teams screenshots to CSV.
// READ-ONLY: source PNG is never modified.

import SwiftUI
import Vision
import AppKit
import CoreImage
import UniformTypeIdentifiers

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
    var body: some Scene {
        WindowGroup("Teams → CSV") {
            ContentView()
                .frame(minWidth: 520, minHeight: 560)
        }
        .windowResizability(.contentMinSize)
    }
}

// ─── MODELS ──────────────────────────────────────────────────────────────────
struct CSVRow: Identifiable {
    let id = UUID()
    let tc: String
    let comment: String
}

struct ProcessedFile: Identifiable {
    let id = UUID()
    let pngURL: URL
    let csvURL: URL
    let rows: [CSVRow]
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
    @State private var isDragging = false
    @State private var processedFiles: [ProcessedFile] = []
    @State private var errorMessage: String?
    @State private var isProcessing = false
    @State private var engine: OCREngine = .tesseract
    @State private var showInfo = false
    @State private var showSettings = false

    // Persisted settings
    @AppStorage("saveLocationMode") private var saveLocationMode: SaveLocationMode = .alongside
    @AppStorage("customSavePath")   private var customSavePath: String = ""
    @AppStorage("exportPDF")        private var exportPDF: Bool = false
    @AppStorage("exportXLSX")       private var exportXLSX: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            dropZone
                .padding(20)
            Divider()
            resultsList
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showInfo) { InfoSheet(isPresented: $showInfo) }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                isPresented: $showSettings,
                saveLocationMode: $saveLocationMode,
                customSavePath: $customSavePath,
                exportPDF: $exportPDF,
                exportXLSX: $exportXLSX
            )
        }
    }

    // Header
    private var header: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Teams → CSV")
                            .font(.system(size: 17, weight: .bold))
                        BetaBadge()
                    }
                    Text("Offline OCR · ingen API · ingen data sendes ut")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if !processedFiles.isEmpty {
                    Button {
                        processedFiles.removeAll()
                        errorMessage = nil
                    } label: {
                        Label("Tøm", systemImage: "trash")
                    }
                    .controlSize(.small)
                }
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Innstillinger")

                Button {
                    showInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Om / personvern")
            }

            HStack(spacing: 10) {
                Label {
                    Text("OCR-motor")
                        .font(.system(size: 11, weight: .medium))
                } icon: {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary)

                Picker("", selection: $engine) {
                    ForEach(OCREngine.allCases) { e in
                        Text(e.rawValue).tag(e)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 320)

                Spacer()
            }

            if engine == .tesseract && tesseractPath == nil {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Tesseract ikke funnet — kjør: brew install tesseract tesseract-lang")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    // Drop zone
    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isDragging ? Color.accentColor : Color.gray.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isDragging
                              ? Color.accentColor.opacity(0.10)
                              : Color.gray.opacity(0.04))
                )

            VStack(spacing: 12) {
                if isProcessing {
                    ProgressView().scaleEffect(0.8)
                    Text("Kjører OCR...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 36))
                        .foregroundColor(isDragging ? .accentColor : .secondary)
                    Text(isDragging ? "Slipp her" : "Dra PNG/JPG hit")
                        .font(.system(size: 14, weight: .medium))
                    Text("eller klikk for å velge filer")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(minHeight: 180)
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
                    .foregroundColor(.secondary.opacity(0.5))
                Text("Ingen filer behandlet ennå")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
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
                                .foregroundColor(.orange)
                            Text(err).font(.system(size: 12))
                            Spacer()
                            Button("✕") { errorMessage = nil }
                                .buttonStyle(.plain)
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                    }
                    ForEach(processedFiles) { file in
                        FileRow(
                            file: file,
                            onDownload: { saveCSV(file) },
                            onShowInFinder: { NSWorkspace.shared.activateFileViewerSelecting([file.csvURL]) }
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
        let saveMode = saveLocationMode
        let customPath = customSavePath
        let alsoPDF = exportPDF
        let alsoXLSX = exportXLSX
        DispatchQueue.global(qos: .userInitiated).async {
            var results: [ProcessedFile] = []
            var errors: [String] = []
            for url in urls {
                let ext = url.pathExtension.lowercased()
                guard ["png", "jpg", "jpeg"].contains(ext) else {
                    errors.append("Hopper over \(url.lastPathComponent) (ikke bilde)")
                    continue
                }
                let outputDir = resolveSaveDirectory(
                    mode: saveMode, customPath: customPath, fallback: url.deletingLastPathComponent()
                )
                switch ocrToCSV(url: url, engine: selectedEngine, outputDir: outputDir,
                                alsoPDF: alsoPDF, alsoXLSX: alsoXLSX) {
                case .success(let result): results.append(result)
                case .failure(let err):    errors.append("\(url.lastPathComponent): \(err.localizedDescription)")
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

    private func saveCSV(_ file: ProcessedFile) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.csvURL.lastPathComponent
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.directoryURL = file.pngURL.deletingLastPathComponent()
        if panel.runModal() == .OK, let dest = panel.url {
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: file.csvURL, to: dest)
            } catch {
                errorMessage = "Lagring feilet: \(error.localizedDescription)"
            }
        }
    }
}

// ─── BETA BADGE ──────────────────────────────────────────────────────────────
struct BetaBadge: View {
    var body: some View {
        Text("BETA")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(0.8)
            .foregroundColor(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color.orange, lineWidth: 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.orange.opacity(0.12)))
            )
    }
}

// ─── FILE ROW ────────────────────────────────────────────────────────────────
struct FileRow: View {
    let file: ProcessedFile
    let onDownload: () -> Void
    let onShowInFinder: () -> Void
    @State private var showAll: Bool = false

    private let initialRows = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ── Header row ──
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.pngURL.lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        Text("\(file.markerCount) markers")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(file.csvURL.lastPathComponent)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
            }

            // ── Table preview ──
            CSVTablePreview(rows: file.rows, showAll: $showAll, limit: initialRows)

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
                    .foregroundColor(.accentColor)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.gray.opacity(0.18), lineWidth: 1)
        )
    }
}

// ─── CSV TABLE PREVIEW ───────────────────────────────────────────────────────
struct CSVTablePreview: View {
    let rows: [CSVRow]
    @Binding var showAll: Bool
    let limit: Int

    private var visibleRows: [CSVRow] {
        showAll ? rows : Array(rows.prefix(limit))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                Text("TIMECODE")
                    .frame(width: 84, alignment: .leading)
                Text("KOMMENTAR")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1.0)
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.08))

            // Rows
            ForEach(Array(visibleRows.enumerated()), id: \.element.id) { idx, row in
                HStack(alignment: .top, spacing: 0) {
                    Text(row.tc)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.accentColor)
                        .frame(width: 84, alignment: .leading)
                    Text(row.comment)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(idx % 2 == 0
                    ? Color.clear
                    : Color.gray.opacity(0.04))
            }

            if !showAll && rows.count > limit {
                HStack {
                    Text("+ \(rows.count - limit) flere rader")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.06))
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
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

func ocrToCSV(url: URL, engine: OCREngine, outputDir: URL,
              alsoPDF: Bool, alsoXLSX: Bool) -> Result<ProcessedFile, OCRError> {
    let lines: [String]
    switch engine {
    case .vision:
        guard let cg = loadCGImage(url: url) else { return .failure(.decodeFailed) }
        lines = visionOCR(cg)
    case .tesseract:
        guard let path = tesseractPath else {
            return .failure(.writeFailed("Tesseract ikke installert. Kjør: brew install tesseract tesseract-lang"))
        }
        switch tesseractOCR(url: url, binaryPath: path) {
        case .success(let l): lines = l
        case .failure(let e): return .failure(e)
        }
    }

    if lines.isEmpty { return .failure(.noText) }
    let parsed = parseTeamsLines(lines)
    if parsed.isEmpty { return .failure(.noTimestamps) }

    let baseName = url.deletingPathExtension().lastPathComponent
    let csvURL  = outputDir.appendingPathComponent(baseName).appendingPathExtension("csv")
    let csv = parsed.map { "\($0.tc),\(csvEscape($0.comment))" }.joined(separator: "\n") + "\n"
    do {
        try csv.write(to: csvURL, atomically: true, encoding: .utf8)
    } catch {
        return .failure(.writeFailed(error.localizedDescription))
    }

    if alsoPDF {
        let pdfURL = outputDir.appendingPathComponent(baseName).appendingPathExtension("pdf")
        try? writePDF(rows: parsed, title: baseName, to: pdfURL)
    }
    if alsoXLSX {
        let xlsxURL = outputDir.appendingPathComponent(baseName).appendingPathExtension("xlsx")
        try? writeXLSX(rows: parsed, to: xlsxURL)
    }

    let rows = parsed.map { CSVRow(tc: $0.tc, comment: $0.comment) }
    return .success(ProcessedFile(pngURL: url, csvURL: csvURL, rows: rows))
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

// Strips Norwegian short-date prefixes like "15/5.", "15/5,", "15.5." etc.
let datePrefixRegex = try! NSRegularExpression(
    pattern: #"^\s*\d{1,2}\s*[/.\-]\s*\d{1,2}\s*[.,:\-\s]*"#
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
    // Two passes: strip leading junk, then date prefix, then leading junk again
    for _ in 0..<3 {
        let before = c
        var r = NSRange(c.startIndex..., in: c)
        c = leadingJunkRegex.stringByReplacingMatches(in: c, range: r, withTemplate: "")
        r = NSRange(c.startIndex..., in: c)
        c = datePrefixRegex.stringByReplacingMatches(in: c, range: r, withTemplate: "")
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

func parseTeamsLines(_ lines: [String]) -> [(tc: String, comment: String)] {
    var rows: [(tc: String, comment: String)] = []
    var i = 0
    while i < lines.count {
        let line = lines[i]
        let r = NSRange(line.startIndex..., in: line)
        guard let m = tcRegex.firstMatch(in: line, range: r),
              let tcR = Range(m.range, in: line) else { i += 1; continue }

        let tc = String(line[tcR]).replacingOccurrences(of: ".", with: ":")
        var rawComment = String(line[tcR.upperBound...])

        // Look ahead if comment is empty OR just looks like a name/date/UI noise.
        // Walk up to 2 lines forward to find the actual message.
        var lookahead = 0
        while lookahead < 2,
              i + 1 + lookahead < lines.count,
              isUninteresting(cleanComment(rawComment))
        {
            let candidate = lines[i + 1 + lookahead]
            let cr = NSRange(candidate.startIndex..., in: candidate)
            if tcRegex.firstMatch(in: candidate, range: cr) != nil { break } // next TC line — stop
            rawComment = candidate
            lookahead += 1
        }
        i += lookahead

        let comment = cleanComment(rawComment)
        if !comment.isEmpty && !isUninteresting(comment) {
            rows.append((tc: tc, comment: comment))
        }
        i += 1
    }
    return rows
}

func csvEscape(_ s: String) -> String {
    if s.contains(",") || s.contains("\"") || s.contains("\n") {
        return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return s
}

// ─── INFO SHEET ──────────────────────────────────────────────────────────────
struct InfoSheet: View {
    @Binding var isPresented: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Text("Teams → CSV").font(.system(size: 18, weight: .bold))
                    BetaBadge()
                    Spacer()
                    Button("Lukk") { isPresented = false }.keyboardShortcut(.escape)
                }

                Section(title: "Hva gjør appen") {
                    Text("Konverterer Teams-screenshots til CSV med timecodes og kommentarer. CSV-en kan importeres i RENDER Multicam Markers-pluginen i Premiere Pro.")
                }

                Section(title: "Personvern") {
                    VStack(alignment: .leading, spacing: 6) {
                        bullet("Alt OCR kjøres lokalt på din maskin.")
                        bullet("Ingen bilder eller data sendes til skyen eller eksterne tjenester.")
                        bullet("Ingen API-kall, ingen telemetri.")
                        bullet("Source-PNGer modifiseres aldri (kun lesing).")
                    }
                }

                Section(title: "OCR-motorer") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Apple Vision").fontWeight(.semibold)
                        Text("Innebygd i macOS. Ingen installasjon nødvendig.")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                        Text("Tesseract (norsk)").fontWeight(.semibold).padding(.top, 4)
                        Text("Krever Homebrew. Lastes IKKE ned automatisk. Installeres med:")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                        Text("brew install tesseract tesseract-lang")
                            .font(.system(size: 11, design: .monospaced))
                            .padding(6)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(4)
                            .textSelection(.enabled)
                    }
                }

                Section(title: "Kontakt & opphavsrett") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("© ENSAMBLE AS").fontWeight(.semibold)
                        HStack(spacing: 4) {
                            Text("Kontakt:")
                                .foregroundColor(.secondary)
                            Text("victoria@ensamble.no")
                                .foregroundColor(.accentColor)
                                .textSelection(.enabled)
                        }
                        .font(.system(size: 12))
                    }
                }

                Spacer(minLength: 10)
            }
            .padding(20)
        }
        .frame(width: 500, height: 540)
    }

    private func bullet(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").foregroundColor(.secondary)
            Text(s).font(.system(size: 12))
            Spacer()
        }
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
                .foregroundColor(.accentColor)
            content()
        }
        .padding(.bottom, 4)
    }
}

// ─── SETTINGS SHEET ──────────────────────────────────────────────────────────
struct SettingsSheet: View {
    @Binding var isPresented: Bool
    @Binding var saveLocationMode: SaveLocationMode
    @Binding var customSavePath: String
    @Binding var exportPDF: Bool
    @Binding var exportXLSX: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Innstillinger").font(.system(size: 18, weight: .bold))
                Spacer()
                Button("Lukk") { isPresented = false }.keyboardShortcut(.escape)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("LAGRINGSPLASSERING")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.2).foregroundColor(.accentColor)

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
                            .foregroundColor(customSavePath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(4)
                        Button("Velg mappe...") {
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
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("EKSPORTFORMATER")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.2).foregroundColor(.accentColor)
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.square.fill").foregroundColor(.green)
                    Text(".csv").font(.system(size: 12, design: .monospaced))
                    Text("(alltid)").font(.system(size: 11)).foregroundColor(.secondary)
                    Spacer()
                }
                Toggle(isOn: $exportPDF) {
                    HStack(spacing: 6) {
                        Text(".pdf").font(.system(size: 12, design: .monospaced))
                        Text("PDF-tabell").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
                Toggle(isOn: $exportXLSX) {
                    HStack(spacing: 6) {
                        Text(".xlsx").font(.system(size: 12, design: .monospaced))
                        Text("Excel-arbeidsbok").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 460, height: 380)
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
