import SwiftUI
import WorkGraphCore

/// 파일 탭: 대기 중인 정리 제안과 지난 결정.
struct FilesView: View {
    @EnvironmentObject private var state: AppState

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    private var pending: [FileSuggestion] { state.fileSuggestions.filter { $0.status == "pending" } }
    private var history: [FileSuggestion] { state.fileSuggestions.filter { $0.status != "pending" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = state.fileError {
                HStack {
                    Text(error).foregroundStyle(.red)
                    Spacer()
                    Button("닫기") { state.fileError = nil }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.red.opacity(0.08))
            }
            if state.notificationsDenied {
                HStack {
                    Text("알림이 꺼져 있어 새 제안은 이 화면과 메뉴바에만 표시됩니다.")
                    Spacer()
                    Button("알림 켜기…") { SuggestionNotifier.openSystemSettings() }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.yellow.opacity(0.10))
            }
            if pending.isEmpty && history.isEmpty {
                ContentUnavailableView("정리할 파일이 없습니다", systemImage: "folder",
                                       description: Text("다운로드 폴더에 새 파일이 생기면 어디에 둘지 제안합니다."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !pending.isEmpty {
                            Text("제안 \(pending.count)건").font(.title3.weight(.semibold))
                            ForEach(pending) { suggestion in pendingCard(suggestion) }
                        }
                        if !history.isEmpty {
                            Text("지난 기록").font(.title3.weight(.semibold)).padding(.top, pending.isEmpty ? 0 : 8)
                            historyTable
                        }
                    }
                    .padding(20)
                }
            }
        }
        .onAppear { state.refreshFileSuggestions() }
    }

    private func pendingCard(_ suggestion: FileSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "doc")
                Text(suggestion.fileName).font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(Self.time.string(from: Date(timeIntervalSince1970: suggestion.ts))).foregroundStyle(.secondary).font(.callout)
            }
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary)
                Text(short(suggestion.suggestedFolder)).font(.body.monospaced()).textSelection(.enabled)
            }
            if let reason = suggestion.reason, !reason.isEmpty {
                Text(reason).font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button("옮기기") { state.acceptSuggestion(suggestion) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                Button("다른 폴더…") { state.chooseFolderAndMove(suggestion) }
                Button("무시") { state.ignoreSuggestion(suggestion) }
                Spacer()
                Button("Finder 에서 보기") { state.revealSuggestionFile(suggestion) }.buttonStyle(.link)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private var historyTable: some View {
        VStack(spacing: 0) {
            ForEach(history) { suggestion in
                HStack(spacing: 12) {
                    Text(Self.time.string(from: Date(timeIntervalSince1970: suggestion.ts))).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                    Text(suggestion.fileName).lineLimit(1).truncationMode(.middle).frame(minWidth: 160, alignment: .leading)
                    Text(short(suggestion.status == "moved" ? (suggestion.movedTo.map { ($0 as NSString).deletingLastPathComponent } ?? suggestion.suggestedFolder) : suggestion.suggestedFolder))
                        .font(.callout.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(label(suggestion.status)).font(.callout).foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
                    if suggestion.status == "moved" {
                        Button("되돌리기") { state.undoSuggestion(suggestion) }.controlSize(.small)
                    } else {
                        Color.clear.frame(width: 64, height: 1)
                    }
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
    }

    private func label(_ status: String) -> String {
        switch status {
        case "moved": return "옮김"
        case "ignored": return "무시"
        case "undone": return "되돌림"
        case "rejected": return "거절"
        case "gone": return "직접 처리"
        default: return status
        }
    }

    private func short(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

/// 설정: 정리 위치 후보를 찾을 폴더 목록.
struct FolderRootsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("후보를 찾을 폴더")
            ForEach(state.settings.folderRoots, id: \.self) { root in
                HStack {
                    Text(root).font(.callout.monospaced())
                    Spacer()
                    Button { state.settings.folderRoots.removeAll { $0 == root } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            Button("폴더 추가…") { addRoot() }
        }
    }

    private func addRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let home = NSHomeDirectory()
        for url in panel.urls {
            let path = url.path
            let shown = path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
            if !state.settings.folderRoots.contains(shown) { state.settings.folderRoots.append(shown) }
        }
    }
}
