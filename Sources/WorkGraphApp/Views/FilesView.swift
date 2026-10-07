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
            BrandPageHeader(title: "파일") {
                HStack(spacing: 15) {
                    Text(String(format: "%02d", pending.count)).font(Brand.jost(52).weight(.ultraLight)).foregroundStyle(Brand.ink)
                    Text("대기 중인\n제안").font(Brand.suit(11)).foregroundStyle(Brand.gray).lineSpacing(2)
                }
            }
            if let error = state.fileError { errorBanner(error) }
            if pending.isEmpty && history.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if state.notificationsDenied { notificationRow }
                        if !pending.isEmpty { pendingSection }
                        if !history.isEmpty { historySection }
                    }
                    .padding(.horizontal, 34).padding(.bottom, 28)
                }
            }
        }
        .background(.white)
        .onAppear { state.refreshFileSuggestions() }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Image(systemName: "folder").font(.system(size: 26, weight: .light)).foregroundStyle(Brand.sub)
            Text("정리할 파일이 없어요").font(Brand.suit(20, .bold)).foregroundStyle(Brand.ink).padding(.top, 14)
            Text("다운로드 폴더에 새 파일이 생기면 어디에 둘지 제안해요.").font(Brand.suit(13)).foregroundStyle(Brand.gray).padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle").font(.system(size: 13)).foregroundStyle(Brand.ink)
            Text(error).font(Brand.suit(13, .medium)).foregroundStyle(Brand.ink)
            Spacer()
            Button("닫기") { state.fileError = nil }.buttonStyle(.plain).font(Brand.suit(12, .medium)).foregroundStyle(Brand.ink)
        }
        .padding(.horizontal, 34).frame(height: 52).frame(maxWidth: .infinity)
        .background(Color(hex: 0xF6F5F4))
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
    }

    private var notificationRow: some View {
        HStack(spacing: 9) {
            Image(systemName: "bell.slash").font(.system(size: 13)).foregroundStyle(Brand.gray)
            Text("알림 권한이 꺼져 있어요. 파일 제안은 이곳에서 확인할 수 있어요.").font(Brand.suit(11)).foregroundStyle(Brand.gray)
            Spacer()
            Button { SuggestionNotifier.openSystemSettings() } label: {
                HStack(spacing: 4) { Text("권한 확인"); Image(systemName: "arrow.up.right").font(.system(size: 10)) }
            }
            .buttonStyle(.plain).font(Brand.suit(11)).foregroundStyle(Brand.tabText)
        }
        .frame(height: 55)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
    }

    private func sectionTitle(_ title: String, count: Int? = nil, trailing: some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(Brand.suit(14)).foregroundStyle(Brand.ink)
            if let count { Text("\(count)").font(Brand.jost(12)).foregroundStyle(Brand.gray) }
            Spacer()
            trailing
        }
        .padding(.top, 24).padding(.bottom, 16)
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("대기 중인 제안", count: pending.count,
                         trailing: Text("승인한 파일만 옮겨요").font(Brand.suit(10)).foregroundStyle(Brand.gray))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 18, alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 18) {
                ForEach(pending) { suggestion in pendingCard(suggestion) }
            }
        }
    }

    private func pendingCard(_ suggestion: FileSuggestion) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "doc.text").font(.system(size: 20, weight: .light)).foregroundStyle(Brand.ink).padding(.top, 2)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(suggestion.fileName).font(Brand.suit(15, .bold)).foregroundStyle(Brand.ink).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(Self.time.string(from: Date(timeIntervalSince1970: suggestion.ts))).font(Brand.suit(11)).foregroundStyle(Brand.gray)
                }
                if let reason = suggestion.reason, !reason.isEmpty {
                    Text(reason).font(Brand.suit(12)).foregroundStyle(Brand.gray).padding(.top, 8)
                }
                HStack(spacing: 8) {
                    Text(source(suggestion)).font(Brand.suit(11)).foregroundStyle(Brand.gray)
                    Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Brand.gray)
                    Image(systemName: "folder").font(.system(size: 11)).foregroundStyle(Brand.ink)
                    Text(short(suggestion.suggestedFolder)).font(Brand.suit(11, .medium)).foregroundStyle(Brand.ink)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                .padding(.top, 14)
                HStack(spacing: 8) {
                    Button { state.acceptSuggestion(suggestion) } label: {
                        HStack(spacing: 4) { Text("옮기기"); Image(systemName: "arrow.right").font(.system(size: 10)) }
                    }
                    .buttonStyle(BrandButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
                    Button("다른 폴더 고르기") { state.chooseFolderAndMove(suggestion) }.buttonStyle(BrandButtonStyle())
                    Button("무시") { state.ignoreSuggestion(suggestion) }.buttonStyle(.plain)
                        .font(Brand.suit(12, .medium)).foregroundStyle(Brand.ink).padding(.horizontal, 2)
                    Spacer(minLength: 0)
                    Button("Finder에서 보기") { state.revealSuggestionFile(suggestion) }.buttonStyle(.plain)
                        .font(Brand.suit(12, .medium)).foregroundStyle(Brand.ink)
                }
                .padding(.top, 16)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 20)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Brand.line))
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("지난 기록", trailing: EmptyView()).padding(.top, 30)
            VStack(spacing: 0) {
                historyRow(Text("파일"), Text("폴더"), Text("처리 결과"), Text("시간"), AnyView(EmptyView()), header: true)
                ForEach(history) { suggestion in
                    let folder = short(suggestion.status == "moved" ? (suggestion.movedTo.map { ($0 as NSString).deletingLastPathComponent } ?? suggestion.suggestedFolder) : suggestion.suggestedFolder)
                    historyRow(Text(suggestion.fileName), Text(folder), Text(label(suggestion.status)),
                               Text(Self.time.string(from: Date(timeIntervalSince1970: suggestion.ts))),
                               AnyView(undoButton(suggestion)), header: false, failed: suggestion.status == "rejected")
                }
            }
        }
    }

    @ViewBuilder private func undoButton(_ suggestion: FileSuggestion) -> some View {
        if suggestion.status == "moved" {
            Button { state.undoSuggestion(suggestion) } label: {
                HStack(spacing: 6) { Image(systemName: "arrow.uturn.backward").font(.system(size: 11)); Text("되돌리기") }
            }
            .buttonStyle(.plain).font(Brand.suit(11)).foregroundStyle(Brand.tabText)
        }
    }

    private func historyRow(_ file: Text, _ folder: Text, _ result: Text, _ time: Text, _ action: AnyView, header: Bool, failed: Bool = false) -> some View {
        HStack(spacing: 0) {
            file.lineLimit(1).truncationMode(.middle).padding(.leading, 14).frame(maxWidth: .infinity, alignment: .leading)
            folder.lineLimit(1).truncationMode(.middle).padding(.leading, 12).frame(width: 256, alignment: .leading)
            result.foregroundStyle(failed ? Color(hex: 0x934C3B) : (header ? Brand.gray : Brand.tabText)).padding(.leading, 12).frame(width: 139, alignment: .leading)
            time.foregroundStyle(Brand.gray).padding(.leading, 12).frame(width: 190, alignment: .leading)
            action.padding(.leading, 12).frame(width: 140, alignment: .leading)
        }
        .font(Brand.suit(header ? 10 : 11)).foregroundStyle(header ? Brand.gray : Brand.tabText)
        .frame(height: header ? 38 : 46)
        .background(header ? Color(hex: 0xF6F5F4) : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
    }

    private func source(_ suggestion: FileSuggestion) -> String {
        (((suggestion.path as NSString).deletingLastPathComponent) as NSString).lastPathComponent
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
            Text("후보를 찾을 폴더").font(Brand.suit(12, .medium)).foregroundStyle(Brand.ink)
            ForEach(state.settings.folderRoots, id: \.self) { root in
                HStack {
                    Text(root).font(Brand.suit(11)).foregroundStyle(Brand.tabText)
                    Spacer()
                    Button { state.settings.folderRoots.removeAll { $0 == root } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain).foregroundStyle(Brand.gray)
                }
            }
            Button("폴더 추가…") { addRoot() }.buttonStyle(BrandButtonStyle())
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
