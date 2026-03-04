import SwiftUI

@main
struct MacDjViewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // CLI test mode: render all pages and exit
        let args = ProcessInfo.processInfo.arguments
        if let testIdx = args.firstIndex(of: "--test"), testIdx + 1 < args.count {
            let path = args[testIdx + 1]
            Self.cliTest(path: path)
            exit(0)
        }
    }

    var body: some Scene {
        Window("MacDjView", id: "main") {
            ContentView()
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open...") {
                    NotificationCenter.default.post(name: .openDjVuFile, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }

    private static func log(_ msg: String) {
        FileHandle.standardError.write(Data((msg + "\n").utf8))
    }

    private static func currentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / (1024 * 1024)
    }

    private static func cliTest(path: String) {
        let allArgs = ProcessInfo.processInfo.arguments
        let startPage: Int
        if let testIdx = allArgs.firstIndex(of: "--test"), testIdx + 2 < allArgs.count {
            startPage = Int(allArgs[testIdx + 2]) ?? 0
        } else {
            startPage = 0
        }
        do {
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url)
            log("Loaded \(data.count) bytes")
            let doc = try DjVuDocument(data: data)
            let pageCount = doc.pageCount
            log("Document: \(path) — \(pageCount) pages, \(doc.sharedDictCount) shared dicts, starting at \(startPage)")

            let totalStart = DispatchTime.now()
            let baseMemory = currentMemoryMB()
            var peakMemory = baseMemory
            var pageTimes = [Double]()
            var errorCount = 0

            for i in startPage..<pageCount {
                do {
                    let startTime = DispatchTime.now()
                    let _ = try doc.renderPage(at: i, scale: 0.25)
                    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
                    pageTimes.append(elapsed)
                    let mem = currentMemoryMB()
                    if mem > peakMemory { peakMemory = mem }
                    log("  Page \(i + 1)/\(pageCount): OK (\(Int(elapsed))ms, \(String(format: "%.0f", mem))MB)")
                } catch {
                    errorCount += 1
                    log("  Page \(i + 1)/\(pageCount): ERROR — \(error)")
                }
            }

            let totalElapsed = Double(DispatchTime.now().uptimeNanoseconds - totalStart.uptimeNanoseconds) / 1_000_000
            let finalMemory = currentMemoryMB()

            // Summary
            log("")
            log("=== Performance Summary ===")
            log("Pages rendered: \(pageTimes.count)/\(pageCount - startPage) (\(errorCount) errors)")
            log("Total time: \(String(format: "%.0f", totalElapsed))ms")
            if !pageTimes.isEmpty {
                let avg = pageTimes.reduce(0, +) / Double(pageTimes.count)
                let sorted = pageTimes.sorted()
                let median = sorted[sorted.count / 2]
                let p95 = sorted[Int(Double(sorted.count) * 0.95)]
                let maxTime = sorted.last!
                log("Per-page: avg=\(Int(avg))ms median=\(Int(median))ms p95=\(Int(p95))ms max=\(Int(maxTime))ms")
            }
            log("Memory: base=\(String(format: "%.0f", baseMemory))MB peak=\(String(format: "%.0f", peakMemory))MB final=\(String(format: "%.0f", finalMemory))MB")
            log("===========================")
        } catch {
            log("Failed to open document: \(error)")
        }
    }
}
