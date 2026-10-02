import SwiftUI
import Quartz
import WorkGraphCore

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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("자료 보관함").font(.title2.bold())
                Spacer()
                if library.busy { ProgressView().controlSize(.small) }
                Button("파일 업로드") { library.importFiles() }.disabled(library.busy)
            }
            Text("업로드한 파일, 생성한 결과물과 저장한 답변을 모아 관리합니다. 프로젝트나 대화에 연결한 자료만 답변에 사용합니다.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("자료 이름 검색", text: $query).textFieldStyle(.roundedBorder)
                Picker("종류", selection: $kind) {
                    Text("전체 종류").tag(""); Text("업로드").tag("upload"); Text("생성한 결과물").tag("generated"); Text("저장한 답변").tag("note")
                }.frame(width: 180)
                Picker("프로젝트", selection: $projectID) {
                    Text("전체 프로젝트").tag("")
                    ForEach(projects.projects) { Text($0.title).tag($0.id) }
                }.frame(width: 200)
            }
            if let error = library.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if filtered.isEmpty {
                ContentUnavailableView(library.items.isEmpty ? "보관한 자료가 없습니다" : "검색 결과가 없습니다", systemImage: "tray", description: Text("파일을 업로드하거나 채팅에서 결과물을 만들어보세요."))
            } else {
                List(filtered) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Button { preview = item } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Label(item.title, systemImage: item.kind == "note" ? "text.book.closed" : "doc.text").font(.headline)
                                Text("\(item.filename) · \(Date(timeIntervalSince1970: item.createdAt).formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                                let names = projects.projects.filter { library.projectIDs(item).contains($0.id) }.map(\.title)
                                if !names.isEmpty { Text(names.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                                if !item.extractionNote.isEmpty { Text(item.extractionNote).font(.caption).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
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
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 30)
                    }.padding(.vertical, 8)
                }
            }
        }.padding(24)
        .sheet(item: $preview) { LibraryPreview(library: library, item: $0) }
        .alert("자료를 삭제할까요?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("취소", role: .cancel) { deleting = nil }
            Button("삭제", role: .destructive) { if let deleting { library.delete(deleting) }; deleting = nil }
        } message: { Text("보관함의 복사본과 모든 대화·프로젝트 연결이 삭제됩니다. 업로드한 원본 파일과 기존 채팅 답변은 남습니다.") }
        .onChange(of: projects.projects) { _, values in if !values.contains(where: { $0.id == projectID }) { projectID = "" } }
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
            HStack {
                Text(item.title).font(.headline).lineLimit(1); Spacer()
                Button("파일 내보내기") { library.export(item) }; Button("닫기") { dismiss() }
            }.padding(16)
            Divider()
            LibraryQuickLook(url: library.store.url(for: item))
            if !item.extractionNote.isEmpty { Text(item.extractionNote).font(.caption).foregroundStyle(.secondary).padding(12) }
        }.frame(width: 800, height: 600)
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
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("보관함에서 선택").font(.system(size: 22, weight: .medium)); Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 28, height: 28) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("닫기")
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("자료 이름 검색", text: $query).textFieldStyle(.plain)
            }.padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            ScrollView {
                LazyVStack(spacing: 0) {
                    let items = library.items.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
                    ForEach(items) { item in
                        Button { onSelect(item); dismiss() } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.text").foregroundStyle(.secondary)
                                Text(item.title).font(.system(size: 14)).lineLimit(1)
                                Spacer()
                                Image(systemName: "plus").foregroundStyle(.tertiary)
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Divider().opacity(0.45)
                    }
                    if items.isEmpty { Text(library.items.isEmpty ? "보관한 자료가 없습니다" : "검색 결과가 없습니다").font(.callout).foregroundStyle(.secondary).padding(28) }
                }
            }
        }.padding(24).frame(width: 520, height: 400).background(Color(nsColor: .textBackgroundColor))
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
                Label("소스 추가", systemImage: "plus").font(.system(size: 14))
                    .foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 15)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden)
                .disabled(library.busy).accessibilityLabel("소스 추가")
            Divider().opacity(0.45).padding(.horizontal, 16)
            if library.busy {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text("소스를 추가하고 있어요").font(.system(size: 13)).foregroundStyle(.secondary) }
                    .padding(16)
            }
            ForEach(sources) { item in sourceRow(item) }
            ForEach(paths, id: \.self) { path in folderRow(path) }
            if sources.isEmpty && paths.isEmpty && !library.busy {
                VStack(alignment: .leading, spacing: 8) {
                    Text(kind.isEmpty ? "프로젝트에 소스를 추가해보세요" : "이 종류의 소스가 없습니다")
                        .font(.system(size: 15, weight: .medium))
                    Text("파일을 올리거나 보관함의 자료, 컴퓨터의 폴더를 연결할 수 있습니다.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }.padding(.horizontal, 16).padding(.vertical, 28)
            }
            if let error = library.error { Text(error).foregroundStyle(.red).font(.callout).padding(16) }
        }
        .sheet(isPresented: $picker) { LibraryPicker(library: library) { library.attach($0, projectID: project.id) } }
        .sheet(item: $preview) { LibraryPreview(library: library, item: $0) }
    }

    private func sourceRow(_ item: ChatLibraryItem) -> some View {
        let ext = URL(fileURLWithPath: item.filename).pathExtension.lowercased()
        let color: Color = ext == "pdf" ? .red : .blue
        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { preview = item } label: {
                    HStack(spacing: 14) {
                        VStack(spacing: 3) {
                            Image(systemName: item.kind == "note" ? "text.bubble" : "doc.text").font(.system(size: 17))
                            if item.kind != "note" { Text(String(ext.uppercased().prefix(5))).font(.system(size: 8, weight: .semibold)) }
                        }.foregroundStyle(color).frame(width: 40, height: 44)
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.1)))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                            Text(item.kind == "note" ? "저장한 답변" : item.kind == "generated" ? "생성한 파일" : "파일")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.vertical, 13).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Text(Date(timeIntervalSince1970: item.createdAt), format: .dateTime.month().day())
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
                Menu {
                    Button("파일 내보내기") { library.export(item) }
                    Button("프로젝트에서 제거") { library.detach(item, projectID: project.id) }
                } label: { Image(systemName: "ellipsis").frame(width: 24, height: 28) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .opacity(hoveredSource == item.id ? 1 : 0).accessibilityLabel("\(item.title) 소스 메뉴")
            }.padding(.horizontal, 16)
                .background(hoveredSource == item.id ? Color.primary.opacity(0.025) : .clear, in: RoundedRectangle(cornerRadius: 12))
                .onHover { hoveredSource = $0 ? item.id : nil }
                .contextMenu {
                    Button("파일 내보내기") { library.export(item) }
                    Button("프로젝트에서 제거") { library.detach(item, projectID: project.id) }
                }
            Divider().opacity(0.45).padding(.horizontal, 16)
        }
    }

    private func folderRow(_ path: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "folder").font(.system(size: 19)).foregroundStyle(.secondary)
                    .frame(width: 40, height: 44).overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.1)))
                VStack(alignment: .leading, spacing: 5) {
                    Text(URL(fileURLWithPath: path).lastPathComponent).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    Text("원본 연결 · 파일을 복사하지 않고 참고합니다").font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    Button("Finder에서 보기") { NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "") }
                    Button("프로젝트에서 제거") { projects.disconnect(path, from: project) }
                } label: { Image(systemName: "ellipsis").frame(width: 24, height: 28) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .opacity(hoveredSource == path ? 1 : 0).accessibilityLabel("폴더 소스 메뉴")
            }.padding(.horizontal, 16).padding(.vertical, 13).help(path)
                .background(hoveredSource == path ? Color.primary.opacity(0.025) : .clear, in: RoundedRectangle(cornerRadius: 12))
                .onHover { hoveredSource = $0 ? path : nil }
                .contextMenu { Button("프로젝트에서 제거") { projects.disconnect(path, from: project) } }
            Divider().opacity(0.45).padding(.horizontal, 16)
        }
    }
}
