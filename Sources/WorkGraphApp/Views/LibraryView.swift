import SwiftUI
import Quartz
import WorkGraphCore

/// 시트 머리: 제목(22), 설명(12), 닫기 버튼. 유리 판 바탕에 아래 구분선 (Figma 자료 연결 시트)
struct LibrarySheetHeader: View {
    let title: String
    var detail: String? = nil
    var onClose: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Brand.suit(22)).tracking(-0.77).foregroundStyle(Brand.ink)
                if let detail { Text(detail).font(Brand.suit(12)).foregroundStyle(Brand.gray).padding(.top, 6) }
            }
            Spacer(minLength: 12)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 13)).foregroundStyle(Brand.tabText)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("닫기")
        }
        .padding(.horizontal, 27).padding(.top, 25).padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brandGlass()
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.hairline).frame(height: 1) }
    }
}

/// 자료 한 줄에 쓰는 작은 아이콘 칸 (회백 바탕, 얇은 테두리, 모서리 5)
private struct LibraryTile: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(Brand.ink)
            .frame(width: 30, height: 30)
    }
}

struct LibraryView: View {
    @ObservedObject var library: LibraryState
    @ObservedObject var projects: ProjectState
    @State private var query = ""
    @State private var kind = ""
    @State private var projectID = ""
    @State private var preview: ChatLibraryItem?
    @State private var deleting: ChatLibraryItem?
    @FocusState private var searchFocused: Bool

    private var filtered: [ChatLibraryItem] {
        library.items.filter { item in
            (query.isEmpty || item.title.localizedCaseInsensitiveContains(query)) && (kind.isEmpty || item.kind == kind)
                && (projectID.isEmpty || library.projectIDs(item).contains(projectID))
        }
    }
    var body: some View {
        content
        .sheet(item: $preview) { LibraryPreview(library: library, item: $0) }
        .alert("자료를 삭제할까요?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("취소", role: .cancel) { deleting = nil }
            Button("삭제", role: .destructive) { if let deleting { library.delete(deleting) }; deleting = nil }
        } message: { Text("보관함의 복사본과 모든 대화·프로젝트 연결이 삭제됩니다. 업로드한 원본 파일과 기존 채팅 답변은 남습니다.") }
        .onChange(of: projects.projects) { _, values in if !values.contains(where: { $0.id == projectID }) { projectID = "" } }
    }

    /// 종류 탭: 전체 / 업로드 / 생성한 결과물 / 저장한 답변
    private static let kinds: [(id: String, label: String)] = [("", "전체"), ("upload", "업로드"), ("generated", "생성한 결과물"), ("note", "저장한 답변")]

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandPageHeader(title: "자료 보관함") {
                if library.busy { ProgressView().controlSize(.small) }
            }
            filterBar
            if let error = library.error {
                Text(error).font(Brand.suit(12)).foregroundStyle(.red).textSelection(.enabled).padding(.horizontal, 34).padding(.top, 10)
            }
            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray").font(.system(size: 26, weight: .light)).foregroundStyle(Brand.line)
                    Text(library.items.isEmpty ? "보관한 자료가 없습니다" : "조건에 맞는 자료가 없습니다").font(Brand.suit(12)).foregroundStyle(Brand.gray)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) { ForEach(filtered) { row($0) } }.padding(.horizontal, 26).padding(.top, 6)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.white)
    }

    /// 한 줄 필터 막대: 왼쪽 종류 글자 탭, 오른쪽은 그래프 도구 줄과 같은 업로드, 필터 알약과 밑줄 검색칸. 아래 1px 선만 둔다
    private var filterBar: some View {
        HStack(spacing: 4) {
            ForEach(Self.kinds, id: \.id) { option in
                let on = kind == option.id
                Button { kind = option.id } label: {
                    Text(option.label).font(Brand.suit(12, on ? .medium : .regular))
                        .foregroundStyle(on ? Brand.ink : Brand.tabText)
                        .padding(.horizontal, 12).frame(height: 26)
                        .background(Capsule().fill(on ? ChatPalette.soft : .clear))
                        .contentShape(Capsule())
                }.buttonStyle(.plain).hoverHighlight(cornerRadius: 13, active: !on)
            }
            Spacer(minLength: 16)
            Button { library.importFiles() } label: {
                toolPill(icon: "plus", title: "파일 업로드")
            }.buttonStyle(.plain).hoverHighlight(cornerRadius: 15).disabled(library.busy)
            projectMenu
            HStack(spacing: 7) {                                 // 그래프 검색칸: 테두리 없이 밑줄, 돋보기는 오른쪽
                TextField("자료 이름 검색", text: $query).textFieldStyle(.plain).font(Brand.suit(13)).foregroundStyle(Brand.text)
                    .focused($searchFocused)
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(searchFocused ? Brand.text : Brand.gray)
            }
            .frame(width: 260, height: 34)
            .overlay(alignment: .bottom) { Rectangle().fill(Brand.ink.opacity(searchFocused ? 0.45 : 0.14)).frame(height: 1).padding(.bottom, 2) }
            .padding(.leading, 12)
        }
        .padding(.horizontal, 34).padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
    }

    /// 그래프 도구 줄의 필터 단추와 같은 알약: 아이콘과 회색 글씨, 커서를 대면 옅은 바탕
    private func toolPill(icon: String, title: String, dot: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12))
            Text(title).font(Brand.suit(12.5))
            if dot { Circle().fill(Color(hex: 0x8FB4CF)).frame(width: 6, height: 6) }
        }
        .foregroundStyle(Brand.gray)
        .padding(.horizontal, 12).frame(height: 30).contentShape(Capsule())
    }

    /// 프로젝트 필터: 그래프처럼 "필터" 알약, 고르면 하늘색 점
    private var projectMenu: some View {
        Menu {
            Picker("프로젝트", selection: $projectID) {
                Text("프로젝트 전체").tag("")
                ForEach(projects.projects) { Text($0.title).tag($0.id) }
            }.pickerStyle(.inline)
        } label: {
            toolPill(icon: "line.3.horizontal.decrease", title: "필터", dot: !projectID.isEmpty)
        }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().hoverHighlight(cornerRadius: 15)
    }

    private func icon(_ item: ChatLibraryItem) -> String {
        item.kind == "upload" ? "arrow.up.doc" : item.kind == "note" ? "text.quote" : "doc.richtext"
    }

    /// 항목 동작 (점 세 개 메뉴와 오른쪽 클릭 메뉴가 같이 쓴다)
    @ViewBuilder private func actions(_ item: ChatLibraryItem) -> some View {
        Menu("프로젝트에서 사용") {
            ForEach(projects.projects) { project in
                let linked = library.projectIDs(item).contains(project.id)
                Button(linked ? "\(project.title)에서 연결 해제" : project.title) {
                    if linked { library.detach(item, projectID: project.id) } else { library.attach(item, projectID: project.id) }
                }
            }
        }
        Button("파일 내보내기") { library.export(item) }
        Button("보관함에서 삭제", role: .destructive) { deleting = item }
    }

    private func row(_ item: ChatLibraryItem) -> some View {
        let names = projects.projects.filter { library.projectIDs(item).contains($0.id) }.map(\.title)
        let detail: [String] = (names.isEmpty ? [] : [names.joined(separator: ", ")])
            + [item.filename, Date(timeIntervalSince1970: item.createdAt).formatted(date: .abbreviated, time: .shortened)]
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Button { preview = item } label: {
                    HStack(spacing: 12) {
                        Image(systemName: icon(item)).font(.system(size: 14, weight: .light)).foregroundStyle(Brand.tabText).frame(width: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(Brand.suit(13)).foregroundStyle(Brand.ink).lineLimit(1)
                            Text(detail.joined(separator: " / ")).font(Brand.suit(11)).foregroundStyle(Brand.gray).lineLimit(1)
                            if !item.extractionNote.isEmpty { Text(item.extractionNote).font(Brand.suit(11)).foregroundStyle(Brand.gray) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.vertical, 12).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Menu { actions(item) } label: { Image(systemName: "ellipsis").foregroundStyle(Brand.gray) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 30)
            }.padding(.horizontal, 8)
                .hoverHighlight(cornerRadius: 8)
                .contextMenu { actions(item) }
            Rectangle().fill(Brand.line).frame(height: 1).padding(.horizontal, 8)
        }
    }
}

struct LibraryPreview: View {
    @ObservedObject var library: LibraryState
    let item: ChatLibraryItem
    @Environment(\.dismiss) private var dismiss
    private var artifact: ChatArtifact? {
        let ext = URL(fileURLWithPath: item.filename).pathExtension.lowercased()
        guard item.kind != "upload" || ["html", "htm"].contains(ext),
              let text = try? String(contentsOf: library.store.url(for: item), encoding: .utf8) else { return nil }
        return .init(title: item.title, format: ext == "md" ? "markdown" : ext == "htm" ? "html" : ext, content: text)
    }
    var body: some View {
        Group {
        if let artifact {
            ArtifactPreview(artifact: artifact)
        } else {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(item.title).font(Brand.suit(14, .medium)).foregroundStyle(Brand.ink).lineLimit(1); Spacer()
                Button { library.export(item) } label: {
                    Text("파일 내보내기").font(Brand.suit(12)).foregroundStyle(Brand.tabText)
                        .padding(.horizontal, 10).frame(height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).hoverHighlight(cornerRadius: 8)
                Button { dismiss() } label: {
                    Text("닫기").font(Brand.suit(12)).foregroundStyle(Brand.tabText)
                        .padding(.horizontal, 10).frame(height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).hoverHighlight(cornerRadius: 8)
            }.padding(.horizontal, 24).frame(height: 56)
            Rectangle().fill(Brand.line).frame(height: 1)
            LibraryQuickLook(url: library.store.url(for: item))
            if !item.extractionNote.isEmpty { Text(item.extractionNote).font(Brand.suit(10)).foregroundStyle(Brand.gray).padding(12) }
        }.frame(width: 800, height: 600).background(.white)
        }
        }
    }
}

private struct LibraryQuickLook: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true; view.previewItem = url as NSURL; return view
    }
    func updateNSView(_ view: QLPreviewView, context: Context) { view.previewItem = url as NSURL }
}

struct LibraryPicker: View {
    @ObservedObject var library: LibraryState
    var onSelect: (ChatLibraryItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var body: some View {
        VStack(spacing: 0) {
            LibrarySheetHeader(title: "보관함에서 선택", detail: "연결한 자료만 답변에 사용해요.") { dismiss() }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Brand.gray)
                TextField("자료 이름 검색", text: $query).textFieldStyle(.plain).font(Brand.suit(12)).foregroundStyle(Brand.text)
            }.padding(.vertical, 10).overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
                .padding(.horizontal, 27).padding(.top, 8)
            ScrollView {
                LazyVStack(spacing: 0) {
                    let items = library.items.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
                    ForEach(items) { item in
                        Button { onSelect(item); dismiss() } label: {
                            HStack(spacing: 12) {
                                LibraryTile(symbol: "doc.text")
                                Text(item.title).font(Brand.suit(12)).foregroundStyle(Brand.tabText).lineLimit(1)
                                Spacer()
                                Image(systemName: "plus").font(.system(size: 12)).foregroundStyle(Brand.gray)
                            }.padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                                .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).hoverHighlight(cornerRadius: 8)
                    }
                    if items.isEmpty { Text(library.items.isEmpty ? "보관한 자료가 없습니다" : "검색 결과가 없습니다").font(Brand.suit(12)).foregroundStyle(Brand.gray).padding(28) }
                }.padding(.horizontal, 27).padding(.top, 4)
            }
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Text("완료").font(Brand.suit(12, .medium)).foregroundStyle(Brand.ink)
                        .padding(.horizontal, 12).frame(height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).hoverHighlight(cornerRadius: 8)
            }.padding(.horizontal, 24).frame(height: 63)
                .brandGlass()
                .overlay(alignment: .top) { Rectangle().fill(Brand.hairline).frame(height: 1) }
        }.frame(width: 600, height: 480).background(.white)
    }
}

struct ProjectSourcesView: View {
    @ObservedObject var library: LibraryState
    @ObservedObject var projects: ProjectState
    var project: ChatProject
    @State private var picker = false
    @State private var preview: ChatLibraryItem?
    @Binding var kind: String
    @Binding var newestFirst: Bool
    @State private var hoveredSource: String?

    private var sources: [ChatLibraryItem] {
        library.sources(projectID: project.id).filter { kind.isEmpty || $0.kind == kind }
            .sorted { newestFirst ? $0.createdAt > $1.createdAt : $0.createdAt < $1.createdAt }
    }
    private var paths: [String] { kind.isEmpty || kind == "folder" ? project.paths : [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Menu {
                Button("파일 업로드") { library.importFiles(projectID: project.id) }.disabled(library.busy)
                Button("보관함에서 선택") { picker = true }
                Divider()
                Button("이 컴퓨터에서 폴더 연결") { projects.connectFiles(project) }
            } label: {
                Label("소스 추가", systemImage: "plus").font(Brand.suit(12, .medium))
                    .foregroundStyle(Brand.tabText).padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden)
                .disabled(library.busy).accessibilityLabel("소스 추가")
            Rectangle().fill(Brand.line).frame(height: 1)
            if library.busy {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text("소스를 추가하고 있어요").font(Brand.suit(12)).foregroundStyle(Brand.gray) }
                    .padding(16)
            }
            ForEach(sources) { item in sourceRow(item) }
            ForEach(paths, id: \.self) { path in folderRow(path) }
            if sources.isEmpty && paths.isEmpty && !library.busy {
                VStack(alignment: .leading, spacing: 8) {
                    Text(kind.isEmpty ? "프로젝트에 소스를 추가해보세요" : "이 종류의 소스가 없습니다")
                        .font(Brand.suit(14, .medium)).foregroundStyle(Brand.ink)
                    Text("파일을 올리거나 보관함의 자료, 컴퓨터의 폴더를 연결할 수 있습니다.")
                        .font(Brand.suit(12)).foregroundStyle(Brand.gray)
                }.padding(.horizontal, 16).padding(.vertical, 28)
            }
            if let error = library.error { Text(error).foregroundStyle(.red).font(Brand.suit(12)).padding(16) }
        }
        .sheet(isPresented: $picker) { LibraryPicker(library: library) { library.attach($0, projectID: project.id) } }
        .sheet(item: $preview) { LibraryPreview(library: library, item: $0) }
    }

    private func sourceRow(_ item: ChatLibraryItem) -> some View {
        let ext = URL(fileURLWithPath: item.filename).pathExtension.lowercased()
        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { preview = item } label: {
                    HStack(spacing: 12) {
                        VStack(spacing: 2) {
                            Image(systemName: item.kind == "note" ? "text.bubble" : "doc.text").font(.system(size: 14))
                            if item.kind != "note" { Text(String(ext.uppercased().prefix(5))).font(Brand.jost(8)) }
                        }.foregroundStyle(Brand.ink).frame(width: 36, height: 40)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(Brand.suit(12, .medium)).foregroundStyle(Brand.tabText).lineLimit(1)
                            Text(item.kind == "note" ? "저장한 답변" : item.kind == "generated" ? "생성한 파일" : "파일")
                                .font(Brand.suit(10)).foregroundStyle(Brand.gray)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.vertical, 12).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Text(Date(timeIntervalSince1970: item.createdAt), format: .dateTime.month().day())
                    .font(Brand.jost(11)).foregroundStyle(Brand.gray)
                Menu {
                    Button("파일 내보내기") { library.export(item) }
                    Button("프로젝트에서 제거") { library.detach(item, projectID: project.id) }
                } label: { Image(systemName: "ellipsis").foregroundStyle(Brand.gray).frame(width: 24, height: 28) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .opacity(hoveredSource == item.id ? 1 : 0).accessibilityLabel("\(item.title) 소스 메뉴")
            }.padding(.horizontal, 16)
                .background(hoveredSource == item.id ? ChatPalette.soft : .clear, in: RoundedRectangle(cornerRadius: 8))
                .onHover { hoveredSource = $0 ? item.id : nil }
                .contextMenu {
                    Button("파일 내보내기") { library.export(item) }
                    Button("프로젝트에서 제거") { library.detach(item, projectID: project.id) }
                }
            Rectangle().fill(Brand.line).frame(height: 1)
        }
    }

    private func folderRow(_ path: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "folder").font(.system(size: 15)).foregroundStyle(Brand.ink)
                    .frame(width: 36, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(URL(fileURLWithPath: path).lastPathComponent).font(Brand.suit(12, .medium)).foregroundStyle(Brand.tabText).lineLimit(1)
                    Text("원본 연결, 파일을 복사하지 않고 참고합니다").font(Brand.suit(10)).foregroundStyle(Brand.gray)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    Button("Finder에서 보기") { NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "") }
                    Button("프로젝트에서 제거") { projects.disconnect(path, from: project) }
                } label: { Image(systemName: "ellipsis").foregroundStyle(Brand.gray).frame(width: 24, height: 28) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .opacity(hoveredSource == path ? 1 : 0).accessibilityLabel("폴더 소스 메뉴")
            }.padding(.horizontal, 16).padding(.vertical, 12).help(path)
                .background(hoveredSource == path ? ChatPalette.soft : .clear, in: RoundedRectangle(cornerRadius: 8))
                .onHover { hoveredSource = $0 ? path : nil }
                .contextMenu { Button("프로젝트에서 제거") { projects.disconnect(path, from: project) } }
            Rectangle().fill(Brand.line).frame(height: 1)
        }
    }
}
