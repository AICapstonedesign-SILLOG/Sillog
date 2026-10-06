import SwiftUI
import WorkGraphCore

/// 채팅 본문의 제목·문단·코드를 구분한다. 완성된 문서는 별도 미리보기로 제공한다.
struct ChatMessageText: View {
    let text: String
    let sources: [ChatSource]
    let onSource: (ChatSource) -> Void

    private static let citationPattern = try! NSRegularExpression(pattern: #"\[((?:(?:node|observation|card|chat|conversation|message|library|file|git|gmail|drive|notion|digest|usage):|https?://)[^\]\n]+)\]"#)

    /// Args: paragraph는 모델이 작성한 문단, sources는 실제로 조회한 근거이다.
    /// Returns: 식별자를 제거한 문단, 조회된 근거, 확인되지 않은 인용 여부.
    /// Raises: 없음.
    static func citations(in paragraph: String, sources: [ChatSource]) -> (String, [ChatSource], Bool) {
        let matches = citationPattern.matches(in: paragraph, range: NSRange(paragraph.startIndex..., in: paragraph))
        var body = paragraph
        var ids: [String] = []
        for match in matches.reversed() {
            guard let range = Range(match.range, in: body), let idRange = Range(match.range(at: 1), in: body) else { continue }
            ids.insert(String(body[idRange]), at: 0)
            body.removeSubrange(range)
        }
        let cited = ids.reduce(into: [ChatSource]()) { result, id in
            if let source = sources.first(where: { $0.id == id }), !result.contains(where: { $0.id == id }) { result.append(source) }
        }
        return (body.trimmingCharacters(in: .whitespacesAndNewlines), cited, ids.contains { id in !cited.contains(where: { $0.id == id }) })
    }

    /// Args: value는 코드 블록을 제외한 채팅 문단이다.
    /// Returns: 단일 물결표는 보존하고 명시적인 ~~취소선~~만 해석한 본문.
    /// Raises: 없음. Markdown 해석 실패 시 원문을 표시한다.
    static func inlineMarkdown(_ value: String) -> AttributedString {
        // Foundation은 ~ 하나도 취소선으로 해석한다. 코드·자동 링크·기존 이스케이프는 그대로 둔다.
        let tokens = try! NSRegularExpression(pattern: #"(`+)(?!`)[\s\S]*?(?<!`)\1(?!`)|<[^>\n]+>|\\[\s\S]|~+"#)
        var escaped = value
        for match in tokens.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
            guard let range = Range(match.range, in: escaped), escaped[range] == "~" else { continue }
            escaped.replaceSubrange(range, with: #"\~"#)
        }
        return (try? AttributedString(markdown: escaped, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(text.components(separatedBy: "```").enumerated()), id: \.offset) { index, part in
                if index.isMultiple(of: 2) {
                    ForEach(Array(part.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                        let (value, cited, missing) = Self.citations(in: paragraph, sources: sources)
                        if !value.isEmpty || !cited.isEmpty || missing {
                            VStack(alignment: .leading, spacing: 6) {
                                if let rows = ChatMarkdownTable.rows(in: value) {
                                    ChatMarkdownTableView(rows: rows)
                                } else if value.hasPrefix("#") {
                                    Text(value.replacingOccurrences(of: "^#{1,6} +", with: "", options: .regularExpression))
                                        .font(Brand.suit(value.hasPrefix("# ") ? 18 : 15, .semibold)).foregroundStyle(Brand.ink)
                                        .padding(.top, 4)
                                } else if !value.isEmpty {
                                    Text(Self.inlineMarkdown(value))
                                        .font(Brand.suit(13)).foregroundStyle(Brand.tabText).lineSpacing(9)
                                }
                                if !cited.isEmpty { ChatCitationButton(sources: cited, onSource: onSource) }
                                if missing { Text("확인되지 않은 근거").font(Brand.suit(10)).foregroundStyle(Brand.gray) }
                            }
                        }
                    }
                } else {
                    let lines = part.components(separatedBy: "\n")
                    VStack(alignment: .leading, spacing: 10) {
                        if let language = lines.first, !language.isEmpty { Text(language).font(Brand.suit(10)).foregroundStyle(Brand.gray) }
                        ScrollView(.horizontal) {
                            Text(lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .newlines))
                                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Brand.tabText)
                        }
                    }.padding(14).background(ChatPalette.soft, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
                }
            }
        }.textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChatMarkdownTableView: View {
    let rows: [[String]]
    private let columnWidth: CGFloat = 220
    private let cellPadding: CGFloat = 12

    var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(rows[row].indices, id: \.self) { column in
                            Text(ChatMessageText.inlineMarkdown(rows[row][column]))
                                .font(Brand.suit(12, row == 0 ? .semibold : .regular)).foregroundStyle(row == 0 ? Brand.ink : Brand.tabText)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(width: columnWidth, alignment: .topLeading)
                                .padding(.horizontal, cellPadding).padding(.vertical, 9)
                        }
                    }
                    .background(row == 0 ? ChatPalette.soft : .clear)
                    if row < rows.count - 1 { Rectangle().fill(Brand.line).frame(height: 1) }
                }
            }
            .frame(width: CGFloat(rows[0].count) * (columnWidth + cellPadding * 2))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Brand.line))
        }
        .defaultScrollAnchor(.leading)
    }
}

private struct ChatCitationButton: View {
    let sources: [ChatSource]
    let onSource: (ChatSource) -> Void
    @State private var showingSources = false

    var body: some View {
        Button { showingSources = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "text.book.closed").font(.system(size: 9))
                Text(sources[0].title).lineLimit(1).frame(maxWidth: 220)
                if sources.count > 1 { Text("+\(sources.count - 1)").font(Brand.jost(9)) }
            }
            .font(Brand.suit(9))
            .foregroundStyle(Brand.tabText)
            .padding(.horizontal, 7).frame(height: 26)
            .background(.white, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Brand.line))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingSources) {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow("EVIDENCE")
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(sources) { source in
                            Button {
                                showingSources = false
                                onSource(source)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(source.title).font(Brand.suit(12, .medium)).foregroundStyle(Brand.ink)
                                    if !source.location.isEmpty {
                                        Text(source.location).font(Brand.suit(10)).foregroundStyle(Brand.gray).lineLimit(1)
                                    }
                                    Text(source.excerpt).font(Brand.suit(11)).foregroundStyle(Brand.tabText).lineLimit(4)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 340)
            }.padding(16).frame(width: 320)
        }
    }
}
