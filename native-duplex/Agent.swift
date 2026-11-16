// SPDX-License-Identifier: MIT
import AppKit
import Darwin

struct Request: Equatable {
    let job: Int, pages: Int, copy: Int, copies: Int
    static func parse(_ text: String) -> Request? {
        let parts = text.trimmingCharacters(in: .newlines).split(separator: "\t", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let values = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(part)
        }
        guard values.count == 4, values[0] > 0, values[1] > 1, values[1] <= 5000,
              values[2] > 0, values[2] <= values[3], values[3] <= 100 else { return nil }
        return Request(job: values[0], pages: values[1], copy: values[2], copies: values[3])
    }
}
func validName(_ name: String) -> Bool {
    let suffix = ".request"
    guard name.hasSuffix(suffix) else { return false }
    let token = name.dropLast(suffix.count)
    return token.count == 32 && token.allSatisfy { "0123456789abcdef".contains($0) }
}
let directory = "/Users/Shared/hp1020-duplex-\(getuid())"
var directoryFD: Int32 = -1
func readRequest(_ name: String) -> Request? {
    guard validName(name) else { return nil }
    let fd = openat(directoryFD, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    var st = stat()
    let spoolUID = getpwnam("_lp")?.pointee.pw_uid
    guard fstat(fd, &st) == 0, st.st_mode & S_IFMT == S_IFREG, st.st_nlink == 1,
          st.st_uid == 0 || st.st_uid == spoolUID,
          st.st_size > 0, st.st_size < 128,
          Date().timeIntervalSince1970 - Double(st.st_mtimespec.tv_sec) < 1800,
          Double(st.st_mtimespec.tv_sec) <= Date().timeIntervalSince1970 + 5 else { return nil }
    var buffer = [UInt8](repeating: 0, count: 128)
    let count = read(fd, &buffer, buffer.count)
    guard count > 0 else { return nil }
    return Request.parse(String(decoding: buffer.prefix(count), as: UTF8.self))
}
func atomicWrite(_ name: String, _ value: String) -> Bool {
    let pending = ".agent-\(UUID().uuidString)"
    let fd = openat(directoryFD, pending, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
    guard fd >= 0 else { return false }
    guard fchmod(fd, 0o644) == 0 else { close(fd); unlinkat(directoryFD, pending, 0); return false }
    let data = Array(value.utf8)
    let count = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    close(fd)
    guard count == data.count else { unlinkat(directoryFD, pending, 0); return false }
    if renameat(directoryFD, pending, directoryFD, name) != 0 { unlinkat(directoryFD, pending, 0); return false }
    return true
}
func prepareDirectory() -> Bool {
    if mkdir(directory, 0o700) != 0 && errno != EEXIST { return false }
    directoryFD = open(directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard directoryFD >= 0 else { return false }
    var st = stat()
    guard fstat(directoryFD, &st) == 0, st.st_uid == getuid() else { return false }
    return fchmod(directoryFD, 0o1733) == 0
}

func makeDialog(_ request: Request) -> NSAlert {
    let dialog = NSAlert()
    dialog.messageText = "HP 1020 — przełóż papier"
    dialog.informativeText = "Zadanie \(request.job), kopia \(request.copy) z \(request.copies), \((request.pages + 1) / 2) kartek.\n\nPoczekaj, aż WSZYSTKIE kartki wyjdą z drukarki. Sprawdź, czy wydruk jest kompletny.\n\nWyjmij czysty papier z podajnika. Włóż wydrukowany stos zadrukowaną stroną w dół, dolną krawędzią stron w stronę drukarki. Zachowaj kolejność: ostatnia nieparzysta strona ma być pobrana pierwsza.\n\nKliknij „Kontynuuj” dopiero po przełożeniu całego stosu. Jeśli brakuje kartek lub wystąpiło zacięcie, anuluj."
    dialog.addButton(withTitle: "Papier przełożony — Kontynuuj")
    dialog.addButton(withTitle: "Anuluj pozostałe strony")
    return dialog
}

final class Startup: NSObject, NSApplicationDelegate {
    var onLaunch: (() -> Void)?
    func applicationDidFinishLaunching(_ notification: Notification) { onLaunch?() }
}

if CommandLine.arguments.contains("--self-test") {
    assert(Request.parse("12\t5\t1\t2\n") == Request(job: 12, pages: 5, copy: 1, copies: 2))
    for bad in ["", "1\t0\t1\t1", "1\t5\t2\t1", "1\t5\t1\t101", "1\t5\t1\t1\textra", "-1\t5\t1\t1", "1\t5001\t1\t1"] { assert(Request.parse(bad) == nil) }
    assert(validName(String(repeating: "a", count: 32) + ".request"))
    assert(!validName("../request"))
    assert(!validName(String(repeating: "g", count: 32) + ".request"))
    let testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: false)
    directoryFD = open(testDirectory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    assert(directoryFD >= 0)
    for name in ["heartbeat", "test.reply"] {
        assert(atomicWrite(name, "test"))
        var info = stat()
        assert(fstatat(directoryFD, name, &info, AT_SYMLINK_NOFOLLOW) == 0)
        assert(info.st_mode & 0o777 == 0o644, "CUPS must be able to read agent metadata")
    }
    close(directoryFD)
    try FileManager.default.removeItem(at: testDirectory)
    print("PASS: agent protocol validation and cross-user metadata permissions")
} else if CommandLine.arguments.contains("--preview") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = Startup()
    delegate.onLaunch = {
        let dialog = makeDialog(Request(job: 123, pages: 5, copy: 1, copies: 1))
        app.activate(ignoringOtherApps: true)
        _ = dialog.runModal()
        app.terminate(nil)
    }
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
} else {
    guard prepareDirectory() else { fputs("Cannot create secure confirmation directory\n", stderr); exit(1) }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    var activeName: String?
    var shown = Set<String>()
    var currentAlert: NSAlert?
    func tick() {
        _ = atomicWrite("heartbeat", "HP1020 Duplex Agent v1\n")
        if let name = activeName {
            if readRequest(name) == nil {
                app.abortModal()
                currentAlert?.window.orderOut(nil)
            }
            return
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        shown.formIntersection(Set(names))
        for name in names.sorted() where !shown.contains(name) {
            guard let request = readRequest(name) else { continue }
            shown.insert(name)
            activeName = name
            let dialog = makeDialog(request)
            currentAlert = dialog
            app.activate(ignoringOtherApps: true)
            let result = dialog.runModal()
            if readRequest(name) != nil {
                let response = result == .alertFirstButtonReturn ? "continue\n" : "cancel\n"
                _ = atomicWrite(String(name.dropLast(8)) + ".reply", response)
            }
            currentAlert = nil
            activeName = nil
            break
        }
    }
    let timer = Timer(timeInterval: 1, repeats: true) { _ in tick() }
    let delegate = Startup()
    delegate.onLaunch = {
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .modalPanel)
        tick()
    }
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
