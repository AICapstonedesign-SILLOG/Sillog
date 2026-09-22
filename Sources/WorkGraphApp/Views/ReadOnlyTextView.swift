import AppKit
import SwiftUI

/// 긴 텍스트(화면 텍스트 전문, 프롬프트, 응답) 표시용. SwiftUI Text 는 수천 자에 선택까지 켜면 느려서 NSTextView 를 쓴다.
struct ReadOnlyTextView: NSViewRepresentable {
    let text: String
    var monospaced = true

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.font = monospaced ? .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular) : .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
        textView.scroll(.zero)
    }
}

/// 상세 패널 안에서 쓰는 고정 높이 텍스트 상자.
struct TextBlock: View {
    let title: String
    let text: String
    var height: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            ReadOnlyTextView(text: text)
                .frame(height: min(height, CGFloat(max(3, text.split(whereSeparator: \.isNewline).count + 1)) * 17 + 12))
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
