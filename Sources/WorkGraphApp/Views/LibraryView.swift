import SwiftUI
import Quartz
import WorkGraphCore

/// 시트 머리: 눈썹 글씨, 제목(22), 설명(12), 닫기 버튼. 유리 판 바탕에 아래 구분선 (Figma 자료 연결 시트)
struct LibrarySheetHeader: View {
    let eyebrow: String
    let title: String
    var detail: String? = nil
    var onClose: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(eyebrow)
                Text(title).font(Brand.suit(22)).tracking(-0.77).foregroundStyle(Brand.ink).padding(.top, 8)
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
        .background(.white.opacity(0.3)).background(BehindWindowGlass())
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.hairline).frame(height: 1) }
    }
}

/// 자료 한 줄에 쓰는 작은 아이콘 칸 (회백 바탕, 얇은 테두리, 모서리 5)
private struct LibraryTile: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(Brand.ink)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color(hex: 0xF6F5F4)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Brand.line))
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

    private var filtered: [ChatLibraryItem] {
        library.items.filter { item in
            (query.isEmpty || item.title.localizedCaseInsensitiveContains(query)) && (kind.isEmpty || item.kind == kind)
                && (projectID.isEmpty || library.projectIDs(item).contains(projectID))
        }
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Brand.hairline).frame(width: 1)
            content
        }
        .sheet(item: $preview) { LibraryPreview(library: library, item: $0) }
        .alert("자료를 삭제할까요?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("취소", role: .cancel) { deleting = nil }
            Button("삭제", role: .destructive) { if let deleting { library.delete(deleting) }; deleting = nil }
        } message: { Text("보관함의 복사본과 모든 대화·프로젝트 연결이 삭제됩니다. 업로드한 원본 파일과 기존 채팅 답변은 남습니다.") }
        .onChange(of: projects.projects) { _, values in if !values.contains(where: { $0.id == projectID }) { projectID = "" } }
    }

    /// 채팅 화면과 같은 유리 사이드바: 눈썹 글씨, 제목, 파일 올리기 버튼, 종류와 프로젝트 필터
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("YOUR LIBRARY").padding(.top, 27)
            Text("보관함").font(Brand.suit(23, .semibold)).tracking(-0.805).foregroundStyle(Brand.ink).padding(.top, 8)
            Button { library.importFiles() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 12))
                    Text("파일 업로드").font(Brand.suit(12, .medium))
                }.foregroundStyle(Brand.tabText).frame(maxWidth: .infinity).frame(height: 38)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.33)))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
            }.buttonStyle(.plain).disabled(library.busy).padding(.top, 18)
            Eyebrow("KIND").padding(.top, 26).padding(.leading, 12)
            VStack(spacing: 2) {
                filterRow("전체 종류", kind.isEmpty) { kind = "" }
                filterRow("업로드", kind == "upload") { kind = "upload" }
                filterRow("생성한 결과물", kind == "generated") { kind = "generated" }
                filterRow("저장한 답변", kind == "note") { kind = "note" }
            }.padding(.top, 8)
            Eyebrow("PROJECT").padding(.top, 22).padding(.leading, 12)
            ScrollView {
                VStack(spacing: 2) {
                    filterRow("전체 프로젝트", projectID.isEmpty) { projectID = "" }
                    ForEach(projects.projects) { project in
                        filterRow(project.title, projectID == project.id) { projectID = project.id }
                    }
                }
            }.padding(.top, 8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(width: 249).frame(maxHeight: .infinity)
        .background(.white.opacity(0.3)).background(BehindWindowGlass())
    }

    private func filterRow(_ title: String, _ on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Brand.suit(11, on ? .medium : .regular)).foregroundStyle(on ? Brand.ink : Brand.tabText).lineLimit(1)
                .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .glassPill(on, cornerRadius: 5).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandPageHeader(eyebrow: "LIBRARY", title: "자료 보관함",
                            detail: "업로드한 파일, 생성한 결과물과 저장한 답변을 모아 관리합니다. 프로젝트나 대화에 연결한 자료만 답변에 사용합니다.") {
                if library.busy { ProgressView().controlSize(.small) }
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Brand.gray)
                TextField("자료 이름 검색", text: $query).textFieldStyle(.plain).font(Brand.suit(12)).foregroundStyle(Brand.text)
            }.brandField().padding(.horizontal, 34).padding(.top, 16)
            if let error = library.error {
                Text(error).font(Brand.suit(12)).foregroundStyle(.red).textSelection(.enabled).padding(.horizontal, 34).padding(.top, 10)
            }
            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray").font(.system(size: 26, weight: .light)).foregroundStyle(Brand.sub)
                    Text(library.items.isEmpty ? "보관한 자료가 없습니다" : "검색 결과가 없습니다").font(Brand.suit(14, .medium)).foregroundStyle(Brand.ink)
                    Text("파일을 업로드하거나 채팅에서 결과물을 만들어보세요.").font(Brand.suit(12)).foregroundStyle(Brand.gray)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) { ForEach(filtered) { row($0) } }.padding(.horizontal, 34).padding(.top, 6)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.white)
    }

    private func row(_ item: ChatLibraryItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button { preview = item } label: {
                HStack(spacing: 12) {
                    LibraryTile(symbol: item.kind == "note" ? "text.book.closed" : "doc.text")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).font(Brand.suit(12, .medium)).foregroundStyle(Brand.tabText).lineLimit(1)
                        Text("\(item.filename)  \(Date(timeIntervalSince1970: item.createdAt).formatted(date: .abbreviated, time: .shortened))")
                            .font(Brand.suit(10)).foregroundStyle(Brand.gray)
                        let names = projects.projects.filter { library.projectIDs(item).contains($0.id) }.map(\.title)
                        if !names.isEmpty { Text(names.joined(separator: ", ")).font(Brand.suit(10)).foregroundStyle(Brand.gray) }
                        if !item.extractionNote.isEmpty { Text(item.extractionNote).font(Brand.suit(10)).foregroundStyle(Brand.gray) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Menu {
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
            } label: { Image(systemName: "ellipsis").foregroundStyle(Brand.gray) }.menuStyle(.borderlessButton).frame(width: 30)
        }.padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
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
                Button("파일 내보내기") { library.export(item) }.buttonStyle(BrandButtonStyle())
                Button("닫기") { dismiss() }.buttonStyle(BrandButtonStyle())
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
            LibrarySheetHeader(eyebrow: "CONTEXT SOURCES", title: "보관함에서 선택", detail: "연결한 자료만 답변에 사용해요.") { dismiss() }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Brand.gray)
                TextField("자료 이름 검색", text: $query).textFieldStyle(.plain).font(Brand.suit(12)).foregroundStyle(Brand.text)
            }.brandField().padding(.horizontal, 27).padding(.top, 16)
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
                        }.buttonStyle(.plain)
                    }
                    if items.isEmpty { Text(library.items.isEmpty ? "보관한 자료가 없습니다" : "검색 결과가 없습니다").font(Brand.suit(12)).foregroundStyle(Brand.gray).padding(28) }
                }.padding(.horizontal, 27).padding(.top, 4)
            }
            HStack {
                Spacer()
                Button("완료") { dismiss() }.buttonStyle(BrandButtonStyle(kind: .primary))
            }.padding(.horizontal, 24).frame(height: 63)
                .background(.white.opacity(0.3)).background(BehindWindowGlass())
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
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color(hex: 0xF6F5F4)))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Brand.line))
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
                .background(hoveredSource == item.id ? Color(hex: 0xF6F5F4) : .clear, in: RoundedRectangle(cornerRadius: 8))
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
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(hex: 0xF6F5F4)))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Brand.line))
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
                .background(hoveredSource == path ? Color(hex: 0xF6F5F4) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .onHover { hoveredSource = $0 ? path : nil }
                .contextMenu { Button("프로젝트에서 제거") { projects.disconnect(path, from: project) } }
            Rectangle().fill(Brand.line).frame(height: 1)
        }
    }
}
