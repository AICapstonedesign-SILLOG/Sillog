import AppKit
import SwiftUI
import WorkGraphCore

/// 파일 탭: 대기 중인 정리 제안과 지난 결정.
struct FilesView: View {
    @EnvironmentObject private var state: AppState
    @State private var hovered: FileSuggestion.ID?          // 커서를 댄 제안: 오른쪽 나무에서 그 가지를 진하게

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    private var pending: [FileSuggestion] { state.fileSuggestions.filter { $0.status == "pending" } }
    private var history: [FileSuggestion] { state.fileSuggestions.filter { $0.status != "pending" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandPageHeader(title: "파일")
            if let error = state.fileError { errorBanner(error) }
            FileSuggestSettings().padding(.horizontal, 34).padding(.top, 14)
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
            Text("정리할 파일이 없어요").font(Brand.suit(14, .medium)).foregroundStyle(Brand.ink)
            Text("다운로드 폴더에 새 파일이 생기면 어디에 둘지 제안해요.").font(Brand.suit(12)).foregroundStyle(Brand.gray).padding(.top, 8)
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
        .background(ChatPalette.soft)
    }

    private var notificationRow: some View {
        Button { state.selectedTab = .settings; state.settingsSection = .record } label: {
            HStack(spacing: 4) {
                Text("알림이 꺼져 있어요. 설정의 일반에서 켤 수 있어요.")
                Image(systemName: "arrow.up.right").font(.system(size: 9))
            }
            .font(Brand.suit(11)).foregroundStyle(Brand.gray)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            sectionTitle("대기 중인 제안", count: pending.count, trailing: EmptyView())
            HStack(alignment: .top, spacing: 28) {                 // 왼쪽 제안 카드, 오른쪽 옮겨질 곳 나무
                VStack(spacing: 0) {
                    ForEach(pending) { suggestion in
                        pendingCard(suggestion)
                            .onHover { h in hovered = h ? suggestion.id : (hovered == suggestion.id ? nil : hovered) }
                    }
                }
                .frame(maxWidth: .infinity)
                pendingTree.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 나무 그림용 묶음: 원래 폴더 → 옮길 폴더 → 파일 (제안이 나온 순서 유지)
    private var pendingGroups: [(source: String, folders: [(path: String, files: [FileSuggestion])])] {
        var groups: [(source: String, folders: [(path: String, files: [FileSuggestion])])] = []
        for suggestion in pending {
            let src = source(suggestion)
            let i = groups.firstIndex { $0.source == src } ?? { groups.append((src, [])); return groups.count - 1 }()
            if let j = groups[i].folders.firstIndex(where: { $0.path == suggestion.suggestedFolder }) {
                groups[i].folders[j].files.append(suggestion)
            } else {
                groups[i].folders.append((suggestion.suggestedFolder, [suggestion]))
            }
        }
        return groups
    }

    /// 옮겨질 곳: 원래 폴더에서 옮길 폴더로 가지가 뻗고, 그 아래에 파일. 같은 폴더로 가는 파일은 한 가지에 묶인다
    private var pendingTree: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("옮겨질 곳").font(Brand.suit(11, .medium)).foregroundStyle(Brand.gray).padding(.bottom, 6)
            ForEach(Array(pendingGroups.enumerated()), id: \.offset) { _, group in
                HStack(spacing: 6) {
                    Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(Brand.ink).frame(width: 12)
                    Text(group.source).font(Brand.suit(12, .medium)).foregroundStyle(Brand.ink)
                    Text("\(group.folders.reduce(0) { $0 + $1.files.count })").font(Brand.jost(11)).foregroundStyle(Brand.gray)
                }
                .frame(height: 28)
                ForEach(Array(group.folders.enumerated()), id: \.offset) { index, folder in
                    let lastFolder = index == group.folders.count - 1
                    let on = folder.files.contains { $0.id == hovered }
                    let shown = short(folder.path)
                    HStack(spacing: 0) {
                        TreeElbow(last: lastFolder).stroke(Brand.line, lineWidth: 1).frame(width: 20)
                        HStack(spacing: 7) {
                            Image(systemName: "folder.fill").font(.system(size: 12)).foregroundStyle(Color(hex: 0x5E97C8))
                            Text((shown as NSString).lastPathComponent).font(Brand.suit(13, on ? .semibold : .regular)).foregroundStyle(Brand.ink).lineLimit(1)
                            Text((shown as NSString).deletingLastPathComponent + "/").font(Brand.suit(11)).foregroundStyle(Brand.gray)
                                .lineLimit(1).truncationMode(.head)
                        }
                        .padding(.leading, 8)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 30)
                    .help(shown)
                    ForEach(folder.files) { file in
                        HStack(spacing: 0) {
                            if lastFolder { Color.clear.frame(width: 20) }       // 위 가지가 이어지면 세로 줄기만
                            else { Rectangle().fill(Brand.line).frame(width: 1).padding(.leading, 6).frame(width: 20, alignment: .leading) }
                            TreeElbow(last: file.id == folder.files.last?.id).stroke(Brand.line, lineWidth: 1).frame(width: 20).padding(.leading, 7.5)
                            HStack(spacing: 6) {
                                Image(systemName: "doc").font(.system(size: 11)).foregroundStyle(Brand.gray)
                                Text(file.fileName).font(Brand.suit(12, file.id == hovered ? .semibold : .regular))
                                    .foregroundStyle(file.id == hovered ? Brand.ink : Brand.tabText).lineLimit(1).truncationMode(.middle)
                            }
                            .padding(.horizontal, 6).frame(height: 24)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(file.id == hovered ? 0.05 : 0)))
                            .padding(.leading, 2)
                            Spacer(minLength: 0)
                        }
                        .frame(height: 28)
                        .contentShape(Rectangle())
                        .onHover { h in hovered = h ? file.id : (hovered == file.id ? nil : hovered) }
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 10).fill(Brand.paper))
        .padding(.top, 18)
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
                    Text(reason).font(Brand.suit(12)).foregroundStyle(Brand.tabText).lineLimit(2).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                }
                HStack(spacing: 8) {
                    Text(source(suggestion)).font(Brand.suit(11)).foregroundStyle(Brand.gray)
                    Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Brand.gray)
                    Image(systemName: "folder").font(.system(size: 11)).foregroundStyle(Brand.ink)
                    Text(short(suggestion.suggestedFolder)).font(Brand.suit(11, .medium)).foregroundStyle(Brand.ink)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                .padding(.top, 14)
                HStack(spacing: 4) {
                    Button { state.acceptSuggestion(suggestion) } label: {
                        HStack(spacing: 4) { Text("옮기기"); Image(systemName: "arrow.right").font(.system(size: 10)) }
                    }
                    .buttonStyle(BrandButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
                    Button("다른 폴더 고르기") { state.chooseFolderAndMove(suggestion) }.buttonStyle(BrandButtonStyle())
                    Button("무시") { state.ignoreSuggestion(suggestion) }.buttonStyle(BrandButtonStyle())
                    Spacer(minLength: 0)
                    Button("Finder에서 보기") { state.revealSuggestionFile(suggestion) }.buttonStyle(BrandButtonStyle())
                }
                .padding(.top, 12)
            }
        }
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
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
        .hoverHighlight(cornerRadius: 6, active: !header)
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

/// 파일 탭 맨 위의 설정 한 줄: 제안 켜고 끄기와 정리 대상 폴더(나무 그림). 폴더가 5개를 넘으면 접어 둔다.
private struct FileSuggestSettings: View {
    @EnvironmentObject private var state: AppState
    @State private var open = false

    private var roots: [String] { state.settings.folderRoots }
    private var collapsible: Bool { roots.count > 5 }
    private var showTree: Bool { !collapsible || open }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("새 파일의 정리 위치 제안").font(Brand.suit(13, .medium)).foregroundStyle(Brand.ink)
                    Text("새 파일에 어울리는 폴더 한 곳을 추천해요. 승인한 파일만 옮겨요.").font(Brand.suit(11)).foregroundStyle(Brand.gray)
                }
                Spacer(minLength: 12)
                Toggle("", isOn: $state.settings.suggestFolders).toggleStyle(BrandSwitchStyle())
            }
            .padding(.vertical, 12)
            tree.padding(.bottom, 12)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
    }

    /// 뿌리 "정리 대상 폴더" 아래로 폴더마다 가지가 뻗고, 맨 끝 가지가 "폴더 추가"
    private var tree: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(Brand.ink).frame(width: 12)
                Text("정리 대상 폴더").font(Brand.suit(12, .medium)).foregroundStyle(Brand.ink)
                Text("\(roots.count)").font(Brand.jost(11)).foregroundStyle(Brand.gray)
                if collapsible {
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .medium)).foregroundStyle(Brand.gray)
                }
            }
            .frame(height: 28).contentShape(Rectangle())
            .onTapGesture { if collapsible { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } } }
            if showTree {
                ForEach(roots, id: \.self) { root in
                    FolderBranch(root: root, last: false) { state.settings.folderRoots.removeAll { $0 == root } }
                }
                HStack(spacing: 0) {
                    TreeElbow(last: true).stroke(Brand.line, lineWidth: 1).frame(width: 20)
                    Button { addRoot() } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "plus").font(.system(size: 10, weight: .medium)).frame(width: 12)
                            Text("폴더 추가").font(Brand.suit(12))
                        }
                        .foregroundStyle(Brand.tabText).padding(.horizontal, 8).frame(height: 26).contentShape(Rectangle())
                        .hoverHighlight(cornerRadius: 6)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
                .frame(height: 30)
            }
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

/// 나무 가지 선: 왼쪽 세로 줄기(x=6, 뿌리 아이콘 가운데)와 줄기에서 오른쪽으로 꺾이는 짧은 가로선. 마지막 가지는 줄기를 가운데에서 끊어 └ 모양
private struct TreeElbow: Shape {
    let last: Bool
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.minX + 6.5, midY = rect.midY.rounded() + 0.5
        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: x, y: last ? midY : rect.maxY))
        path.move(to: CGPoint(x: x, y: midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: midY))
        return path
    }
}

/// 정리 대상 폴더 한 가지: 폴더 이름은 진하게, 위 경로는 옅게, 삭제 단추는 커서를 대면 진해진다
private struct FolderBranch: View {
    let root: String
    let last: Bool
    let onRemove: () -> Void
    @State private var hover = false

    private var name: String { (root as NSString).lastPathComponent }
    private var parent: String {
        let dir = (root as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir + "/"
    }

    var body: some View {
        HStack(spacing: 0) {
            TreeElbow(last: last).stroke(Brand.line, lineWidth: 1).frame(width: 20)
            HStack(spacing: 7) {
                Image(systemName: "folder.fill").font(.system(size: 12)).foregroundStyle(Color(hex: 0x5E97C8))
                Text(name).font(Brand.suit(13)).foregroundStyle(Brand.ink)
                if !parent.isEmpty { Text(parent).font(Brand.suit(11)).foregroundStyle(Brand.gray) }
                Spacer(minLength: 8)
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(Brand.gray)
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("\(root) 폴더 삭제")
                .opacity(hover ? 1 : 0.35)
            }
            .padding(.leading, 8).padding(.trailing, 4).frame(height: 26)
            .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
            .hoverHighlight(cornerRadius: 6)
        }
        .frame(height: 30)
    }
}
