import AppKit
import ApplicationServices

public struct ContextSnapshot: Equatable, Sendable {
    public var appBundle: String
    public var appName: String
    public var windowTitle: String?
    public var url: String?
    public var docPath: String?
    public var pid: Int32
    public var windowFrame: CGRect? = nil

    /// 수집 도중 프로세스나 창이 바뀌었으면 이전 관찰에 붙이지 않는다.
    public func sameContext(as other: ContextSnapshot?) -> Bool {
        guard let other else { return false }
        return pid == other.pid && windowFrame == other.windowFrame && appBundle == other.appBundle
            && windowTitle == other.windowTitle && url == other.url && docPath == other.docPath
    }
}

/// "지금 무엇을 보고 있나"를 읽는다. 접근성 권한이 없으면 앱 이름만 나온다.
public final class ContextSampler: @unchecked Sendable {
    private let textReader: AXTextReader
    private var webAccessibilityEnabled = Set<pid_t>()
    private let lock = NSLock()

    public init(textReader: AXTextReader = AXTextReader()) { self.textReader = textReader }

    public func sample(enableWebAccessibility: Bool) -> ContextSnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let bundle = app.bundleIdentifier ?? "unknown.\(app.localizedName ?? "app")"
        var snapshot = ContextSnapshot(appBundle: bundle, appName: app.localizedName ?? bundle, windowTitle: nil,
                                       url: nil, docPath: nil, pid: app.processIdentifier)
        guard AXIsProcessTrusted() else { return snapshot }

        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.25)
        if enableWebAccessibility { turnOnWebAccessibility(element, app: app, bundle: bundle) }
        guard let window = axFocusedWindow(of: element) else { return snapshot }

        snapshot.windowTitle = axString(window, kAXTitleAttribute as String)
        snapshot.windowFrame = axWindowFrame(window)
        if let document = axString(window, kAXDocumentAttribute as String) {
            if BrowserURL.isHTTP(document) {
                snapshot.url = document
            } else if document.hasPrefix("file://"), let url = URL(string: document) {
                snapshot.docPath = url.path
            } else if document.hasPrefix("/") {
                snapshot.docPath = document
            }
        }
        if snapshot.url == nil, BrowserURL.isBrowser(bundle) { snapshot.url = BrowserURL.find(in: window) }
        return snapshot
    }

    /// 현재 포커스된 창의 화면 텍스트.
    public func readText(pid: pid_t) -> (text: String, truncated: Bool)? {
        guard AXIsProcessTrusted() else { return nil }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.2)
        guard let window = axFocusedWindow(of: element) else { return nil }
        return textReader.read(window: window)
    }

    /// Chromium·Electron 은 요청이 있어야 웹 콘텐츠의 접근성 트리를 만든다. 프로세스마다 한 번만 켠다.
    private func turnOnWebAccessibility(_ element: AXUIElement, app: NSRunningApplication, bundle: String) {
        lock.lock()
        let inserted = webAccessibilityEnabled.insert(app.processIdentifier).inserted
        lock.unlock()
        guard inserted else { return }
        let isElectron = app.bundleURL.map {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path)
        } ?? false
        if isElectron {
            AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        } else if BrowserURL.isBrowser(bundle), bundle != "com.apple.Safari", bundle != "org.mozilla.firefox" {
            AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }
}
