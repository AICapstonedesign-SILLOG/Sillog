import AppKit
import SwiftUI

/// 한글 조합 중 Enter는 조합을 확정하고, 일반 Enter는 전송한다.
struct ChatInput: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var onSend: () -> Void

    /// Args: context는 SwiftUI 연결 상태이다.
    /// Returns: 여러 줄 입력과 스크롤을 지원하는 입력창.
    /// Raises: 없음.
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let editor = ChatTextView()
        editor.isRichText = false; editor.allowsUndo = true
        editor.font = .systemFont(ofSize: 15)
        editor.textColor = .labelColor; editor.insertionPointColor = .labelColor
        editor.drawsBackground = false; editor.textContainerInset = NSSize(width: 0, height: 8)
        editor.isHorizontallyResizable = false; editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator; editor.onSend = onSend
        editor.setAccessibilityLabel("메시지 입력")
        scroll.documentView = editor; scroll.drawsBackground = false
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        return scroll
    }

    /// Args: view는 입력창, context는 연결 상태이다.
    /// Returns: 없음. 외부에서 변경된 초안을 반영한다.
    /// Raises: 없음.
    func updateNSView(_ view: NSScrollView, context: Context) {
        guard let editor = view.documentView as? ChatTextView else { return }
        context.coordinator.parent = self; editor.onSend = onSend
        if editor.string != text, !editor.hasMarkedText() { editor.string = text }
        context.coordinator.resize(editor)
    }

    /// Args: 없음.
    /// Returns: 텍스트 변경을 SwiftUI에 전달하는 연결 객체.
    /// Raises: 없음.
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatInput
        /// Args: parent는 입력 바인딩이다.
        /// Returns: 입력 상태 연결 객체.
        /// Raises: 없음.
        init(_ parent: ChatInput) { self.parent = parent }

        /// Args: notification은 편집 완료 알림이다.
        /// Returns: 없음. 초안과 높이를 갱신한다.
        /// Raises: 없음.
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string; resize(editor)
        }

        /// Args: editor는 현재 입력창이다.
        /// Returns: 없음. 내용에 맞춰 56~160pt 범위로 높이를 바꾼다.
        /// Raises: 없음.
        func resize(_ editor: NSTextView) {
            guard let container = editor.textContainer, let layout = editor.layoutManager else { return }
            layout.ensureLayout(for: container)
            let height = min(160, max(56, ceil(layout.usedRect(for: container).height) + 16))
            if parent.height != height { DispatchQueue.main.async { self.parent.height = height } }
        }
    }
}

final class ChatTextView: NSTextView {
    var onSend: (() -> Void)?
    /// Args: event는 키보드 입력이다.
    /// Returns: 없음. Enter 전송, Shift+Enter 줄바꿈, 조합 중 Enter 확정을 처리한다.
    /// Raises: 없음.
    override func keyDown(with event: NSEvent) {
        if [36, 76].contains(event.keyCode), !hasMarkedText() {
            if event.modifierFlags.contains(.shift) { insertNewline(nil) }
            else { onSend?() }
            return
        }
        super.keyDown(with: event)
    }
}
