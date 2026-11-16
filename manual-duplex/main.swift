import AppKit
import PDFKit

struct DuplexError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// Zero-based page indices. A nil back is a real blank sheet side, not a skipped page.
func plan(_ count: Int) -> (fronts: [Int?], backs: [Int?]) {
    let fronts = stride(from: 0, to: count, by: 2).map { Optional($0) }
    let backs = fronts.reversed().map { index -> Int? in
        let back = index! + 1
        return back < count ? back : nil
    }
    return (fronts, backs)
}

func makePass(_ source: PDFDocument, _ indices: [Int?], rotate: Bool) throws -> PDFDocument {
    let output = PDFDocument()
    for (position, index) in indices.enumerated() {
        let page: PDFPage
        if let index = index, let original = source.page(at: index),
           let copy = original.copy() as? PDFPage {
            page = copy
        } else if index == nil, let last = source.page(at: source.pageCount - 1) {
            page = PDFPage()
            page.setBounds(last.bounds(for: .mediaBox), for: .mediaBox)
            page.setBounds(last.bounds(for: .cropBox), for: .cropBox)
        } else {
            throw DuplexError(message: "Nie można odczytać strony PDF.")
        }
        if rotate { page.rotation = (page.rotation + 180) % 360 }
        output.insert(page, at: position)
    }
    return output
}

func command(_ executable: String, _ args: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = args
    var environment = ProcessInfo.processInfo.environment
    environment["LC_ALL"] = "C"
    process.environment = environment
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let text = String(decoding: data, as: UTF8.self)
    guard process.terminationStatus == 0 else { throw DuplexError(message: text) }
    return text
}

@discardableResult
func alert(_ title: String, _ text: String, buttons: [String] = ["OK"]) -> NSApplication.ModalResponse {
    NSApp.activate(ignoringOtherApps: true)
    let dialog = NSAlert()
    dialog.messageText = title
    dialog.informativeText = text
    for button in buttons { dialog.addButton(withTitle: button) }
    return dialog.runModal()
}

func submit(_ file: URL, printer: String, title: String, media: String) throws -> String {
    // Override queue defaults: each generated PDF already has the correct order and parity.
    return try command("/usr/bin/lp", ["-d", printer, "-n", "1", "-t", title,
        "-o", "sides=one-sided", "-o", "number-up=1", "-o", "page-set=all",
        "-o", "outputorder=normal", "-o", "fit-to-page", "-o", "media=\(media)",
        "-o", "page-ranges=1-\(PDFDocument(url: file)!.pageCount)", file.path])
}

func run() throws {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.pdf]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    guard let source = PDFDocument(url: url), !source.isLocked, source.pageCount > 0 else {
        throw DuplexError(message: "Wybierz niezaszyfrowany, niepusty plik PDF.")
    }
    let listing = try command("/usr/bin/lpstat", ["-e"])
    let printers = listing.split(whereSeparator: \.isNewline).map(String.init)
    guard !printers.isEmpty else { throw DuplexError(message: "Najpierw zainstaluj sterownik i dodaj drukarkę w macOS.") }
    let setup = NSAlert()
    setup.messageText = "Ręczny druk dwustronny — HP 1020"
    setup.informativeText = "PDF: \(url.lastPathComponent)\n\(source.pageCount) stron, \((source.pageCount + 1) / 2) kartek.\nNa czas obu przebiegów nie wysyłaj innych zadań do tej drukarki. Najpierw wykonaj próbę na 4 stronach."
    setup.addButton(withTitle: "Drukuj pierwsze strony")
    setup.addButton(withTitle: "Anuluj")
    let view = NSStackView()
    view.orientation = .vertical
    view.alignment = .leading
    let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 330, height: 28))
    picker.addItems(withTitles: printers)
    if printers.contains("HP_LaserJet_1020") { picker.selectItem(withTitle: "HP_LaserJet_1020") }
    view.addArrangedSubview(picker)
    let paper = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 330, height: 28))
    paper.addItems(withTitles: ["A4", "Letter"])
    view.addArrangedSubview(paper)
    let binding = NSButton(checkboxWithTitle: "Oprawa przy krótkiej krawędzi (obrót tyłu o 180°)", target: nil, action: nil)
    view.addArrangedSubview(binding)
    view.frame = NSRect(x: 0, y: 0, width: 460, height: 110)
    setup.accessoryView = view
    guard setup.runModal() == .alertFirstButtonReturn else { return }
    let printer = picker.titleOfSelectedItem!
    let media = paper.titleOfSelectedItem!
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    let pages = plan(source.pageCount)
    let fronts = directory.appendingPathComponent("fronts.pdf")
    let backs = directory.appendingPathComponent("backs.pdf")
    guard try makePass(source, pages.fronts, rotate: false).write(to: fronts),
          try makePass(source, pages.backs, rotate: binding.state == .on).write(to: backs) else {
        throw DuplexError(message: "Nie można zapisać plików tymczasowych.")
    }
    let receipt = try submit(fronts, printer: printer, title: "HP1020 — przody", media: media)
    if source.pageCount == 1 {
        alert("Wysłano jedną stronę", receipt + "\nDokument nie wymaga drugiego przebiegu.")
        return
    }
    let result = alert("Przełóż papier po zakończeniu drukowania", "\(receipt)\n1. Poczekaj, aż WSZYSTKIE kartki wyjdą z drukarki. Sprawdź, że wydruk jest kompletny i bez błędów.\n2. Wyjmij czysty papier z podajnika. Przełóż cały wydrukowany stos bez zmiany kolejności: zadrukowaną stroną w dół, dolną krawędzią stron do przodu (w stronę drukarki). Ostatnia nieparzysta strona ma być pobrana jako pierwsza.\n3. Kliknij przycisk dopiero po przygotowaniu stosu.\n\nJeśli pierwsze zadanie anulowano lub brakuje kartek, wybierz „Anuluj”. Anulowanie tutaj nie zatrzymuje już wysłanego zadania — użyj kolejki drukowania macOS.", buttons: ["Papier przełożony — drukuj drugą stronę", "Anuluj"])
    guard result == .alertFirstButtonReturn else { return }
    let backReceipt = try submit(backs, printer: printer, title: "HP1020 — tyły", media: media)
    alert("Wysłano drugie strony", backReceipt + "\nPoczekaj na zakończenie drukowania. Stan i ewentualne anulowanie znajdziesz w kolejce drukowania macOS.")
}

if CommandLine.arguments.contains("--self-test") {
    for count in 1...101 {
        let p = plan(count)
        assert(p.fronts.count == (count + 1) / 2)
        assert(p.backs.count == p.fronts.count)
        for (front, back) in zip(p.fronts, p.backs.reversed()) {
            assert(front! % 2 == 0)
            assert(back == (front! + 1 < count ? front! + 1 : nil))
        }
    }
    let pdf = PDFDocument()
    for i in 0..<5 {
        let page = PDFPage()
        page.setBounds(NSRect(x: 0, y: 0, width: 595 + i, height: 842), for: .mediaBox)
        page.rotation = i == 1 ? 90 : 0
        pdf.insert(page, at: i)
    }
    let back = try makePass(pdf, plan(5).backs, rotate: true)
    assert(back.pageCount == 3)
    assert(back.page(at: 0)!.bounds(for: .mediaBox).width == 599)
    assert(back.page(at: 1)!.bounds(for: .mediaBox).width == 598)
    assert(back.page(at: 2)!.bounds(for: .mediaBox).width == 596)
    assert(back.page(at: 2)!.rotation == 270)
    assert(pdf.page(at: 1)!.rotation == 90)
    assert(PDFDocument(data: back.dataRepresentation()!)!.pageCount == 3)
    print("PASS: pairing 1...101 pages, blank padding, PDF round trip, rotation and source preservation")
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.activate(ignoringOtherApps: true)
    do { try run() } catch { alert("Nie udało się wydrukować", error.localizedDescription) }
}
