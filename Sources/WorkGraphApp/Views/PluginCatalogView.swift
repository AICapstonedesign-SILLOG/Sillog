import SwiftUI

private struct PluginEntry: Identifiable {
    let id: String
    let name: String
    let summary: String
    let description: String
    let examples: [String]

    static let all: [PluginEntry] = [
        .init(id: "gmail", name: "Gmail", summary: "메일 검색과 읽기",
              description: "연결한 계정의 메일을 찾아 읽습니다. 메일을 보내거나 수정하지 않습니다.",
              examples: ["지난주 받은 메일에서 내가 답해야 할 내용을 정리해줘.", "최근 프로젝트 관련 메일의 결정 사항을 찾아줘."]),
        .init(id: "drive", name: "Google Drive", summary: "파일 검색과 문서 읽기",
              description: "Drive에서 파일을 찾고 문서를 읽습니다. 파일을 만들거나 수정하지 않습니다.",
              examples: ["최근 작성한 기획서를 찾아 핵심 결정을 요약해줘.", "내 Drive 자료를 바탕으로 발표 개요를 만들어줘."]),
        .init(id: "github", name: "GitHub", summary: "저장소, 코드와 PR 읽기",
              description: "접근 권한이 있는 저장소의 코드와 PR을 읽습니다. 저장소를 변경하지 않습니다.",
              examples: ["내가 작업한 저장소의 구조와 주요 기능을 설명해줘.", "최근 PR을 바탕으로 프로젝트 진행 상황을 정리해줘."]),
        .init(id: "notion", name: "Notion", summary: "페이지 검색과 읽기",
              description: "통합에 공유한 Notion 페이지를 검색하고 읽습니다. 페이지를 수정하지 않습니다.",
              examples: ["최근 회의록에서 결정 사항과 다음 할 일을 찾아줘.", "Notion에 정리한 자료를 바탕으로 계획을 세워줘."])
    ]
}

struct PluginCatalogView: View {
    var onClose: () -> Void
    var onUseInChat: (String, String) -> Void

    @State private var query = ""
    @State private var selectedID: String?
    @State private var connected: Set<String> = []
    @State private var googleSelection: Set<String> = []
    @State private var showGoogleInstall = false
    @State private var connecting = false
    @State private var verificationCode: String?
    @State private var notice: String?
    @State private var showNotice = false

    private var selected: PluginEntry? { PluginEntry.all.first { $0.id == selectedID } }
    private var filtered: [PluginEntry] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? PluginEntry.all : PluginEntry.all.filter {
            $0.name.localizedCaseInsensitiveContains(text) || $0.summary.localizedCaseInsensitiveContains(text)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Button { if selectedID == nil { onClose() } else { selectedID = nil } } label: {
                    Label(selectedID == nil ? "채팅" : "플러그인", systemImage: "chevron.left")
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                if let selected { detail(selected) } else { catalog }
            }
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40).padding(.vertical, 28)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .sheet(isPresented: $showGoogleInstall) { googleInstallSheet }
        .alert("플러그인 연결", isPresented: $showNotice) {
            Button("확인", role: .cancel) {}
        } message: { Text(notice ?? "") }
        .onAppear(perform: refresh)
    }

    private var catalog: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 7) {
                Text("플러그인").font(.system(size: 30, weight: .semibold))
                Text("외부 서비스를 연결해 채팅에서 내 자료를 활용하세요.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("플러그인 검색", text: $query).textFieldStyle(.plain)
            }.padding(14).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12)))
            if !connected.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("설치됨").font(.system(size: 16, weight: .semibold))
                    HStack(spacing: 12) {
                        ForEach(PluginEntry.all.filter { connected.contains($0.id) }) { plugin in
                            Button { selectedID = plugin.id } label: { pluginIcon(plugin, size: 42) }
                                .buttonStyle(.plain).help(plugin.name)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                Text(query.isEmpty ? "플러그인 둘러보기" : "검색 결과")
                    .font(.system(size: 16, weight: .semibold))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(filtered) { plugin in
                        Button { selectedID = plugin.id } label: {
                            HStack(spacing: 13) {
                                pluginIcon(plugin, size: 44)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(plugin.name).font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
                                    Text(plugin.summary).font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: connected.contains(plugin.id) ? "checkmark.circle.fill" : "plus")
                                    .foregroundStyle(connected.contains(plugin.id) ? Color.green : Color.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(15)
                            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.09)))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Args: plugin은 상세 화면에 표시할 서비스이다.
    /// Returns: 설치 상태, 사용 예시와 계정 연결 동작이 있는 상세 화면.
    /// Raises: 없음.
    private func detail(_ plugin: PluginEntry) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center, spacing: 16) {
                pluginIcon(plugin, size: 68)
                VStack(alignment: .leading, spacing: 5) {
                    Text(plugin.name).font(.system(size: 29, weight: .semibold))
                    Text(plugin.summary).font(.system(size: 14)).foregroundStyle(.secondary)
                }
                Spacer()
                if connected.contains(plugin.id) {
                    Button { onUseInChat(plugin.id, plugin.examples[0]) } label: {
                        Text("채팅에서 사용해 보기").foregroundStyle(Color(nsColor: .textBackgroundColor))
                    }
                    .buttonStyle(.borderedProminent).tint(Color.primary)
                } else {
                    Button { install(plugin) } label: {
                        Text(connecting ? "연결 중…" : "플러그인 설치")
                            .foregroundStyle(Color(nsColor: .textBackgroundColor))
                    }
                    .buttonStyle(.borderedProminent).tint(Color.primary).disabled(connecting)
                }
            }
            Text(plugin.description).font(.system(size: 15)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 13) {
                Text("이렇게 활용할 수 있어요").font(.system(size: 15, weight: .semibold))
                ForEach(plugin.examples, id: \.self) { example in
                    Button { if connected.contains(plugin.id) { onUseInChat(plugin.id, example) } else { install(plugin) } } label: {
                        HStack(spacing: 12) {
                            Text(example).foregroundStyle(.primary).multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(15)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            if let verificationCode, plugin.id == "github" {
                Text("GitHub 승인 코드: \(verificationCode)")
                    .font(.system(.body, design: .monospaced)).textSelection(.enabled)
            }
            if connected.contains(plugin.id) {
                Divider()
                HStack(spacing: 18) {
                    Button("다시 연결") { install(plugin) }.disabled(connecting)
                    Button("연결 해제") { disconnect(plugin.id) }.foregroundStyle(.red)
                }
            }
        }
    }

    /// Args: plugin은 아이콘을 표시할 서비스, size는 아이콘 영역의 한 변이다.
    /// Returns: 앱에 포함된 서비스 공식 아이콘.
    /// Raises: 없음.
    private func pluginIcon(_ plugin: PluginEntry, size: CGFloat) -> some View {
        let url = Bundle.main.url(forResource: plugin.id, withExtension: "png", subdirectory: "PluginIcons")
            ?? Bundle.module.url(forResource: plugin.id, withExtension: "png", subdirectory: "PluginIcons")
        let image = url.flatMap { NSImage(contentsOf: $0) } ?? NSImage()
        return Image(nsImage: image).resizable().scaledToFit()
            .frame(width: size * 0.62, height: size * 0.62)
            .frame(width: size, height: size)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: size * 0.23))
            .overlay(RoundedRectangle(cornerRadius: size * 0.23).stroke(Color.primary.opacity(0.1)))
    }

    private var googleInstallSheet: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("설치할 Google 플러그인 선택").font(.title2.bold())
                Spacer()
                Button { showGoogleInstall = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
            Text("승인할 자료만 선택하세요. 연결 후에도 각 플러그인을 해제할 수 있습니다.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(PluginEntry.all.filter { ["gmail", "drive"].contains($0.id) }) { plugin in
                Toggle(isOn: googleBinding(plugin.id)) {
                    HStack(spacing: 12) {
                        pluginIcon(plugin, size: 38)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(plugin.name).fontWeight(.medium)
                            Text(plugin.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.toggleStyle(.switch)
            }
            Button("Google에서 계속") { showGoogleInstall = false; connectGoogle() }
                .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                .disabled(googleSelection.isEmpty)
        }.padding(28).frame(width: 500)
    }

    /// Args: id는 Google 플러그인 ID이다.
    /// Returns: 설치 선택 상태 바인딩.
    /// Raises: 없음.
    private func googleBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { googleSelection.contains(id) }, set: { enabled in
            if enabled { googleSelection.insert(id) } else { googleSelection.remove(id) }
        })
    }

    /// Args: plugin은 설치할 서비스이다.
    /// Returns: 없음. Google은 권한 선택을 보여주고 나머지는 공급자 승인을 시작한다.
    /// Raises: 없음. 오류는 화면에 표시한다.
    private func install(_ plugin: PluginEntry) {
        if ["gmail", "drive"].contains(plugin.id) {
            googleSelection = [plugin.id]
            showGoogleInstall = true
            return
        }
        do {
            guard try PluginAuth.isAvailable(plugin.id) else {
                notify("이 빌드에는 \(plugin.name) 연결 정보가 아직 없습니다. 앱 제공자가 OAuth 앱을 등록해야 사용할 수 있습니다.")
                return
            }
        } catch { notify(error.localizedDescription); return }
        connecting = true
        Task {
            do {
                if plugin.id == "github" {
                    let client = try PluginAuth.configuration("github-client", environment: "WORKGRAPH_GITHUB_CLIENT_ID")
                    try await PluginAuth.connectGitHub(clientID: client) { verificationCode = $0 }
                } else {
                    let client = try PluginAuth.configuration("notion-client", environment: "WORKGRAPH_NOTION_CLIENT_ID")
                    let secret = try PluginAuth.configuration("notion-secret", environment: "WORKGRAPH_NOTION_CLIENT_SECRET")
                    try await PluginAuth.connectNotion(clientID: client, clientSecret: secret)
                }
                connected.insert(plugin.id)
            } catch { notify(error.localizedDescription) }
            verificationCode = nil
            connecting = false
        }
    }

    /// Args: 없음. 사용자가 선택한 Google 플러그인을 승인한다.
    /// Returns: 없음. 승인 성공 시 설치됨 상태를 갱신한다.
    /// Raises: 없음. OAuth 오류는 화면에 표시한다.
    private func connectGoogle() {
        let ids = googleSelection
        do {
            guard try PluginAuth.isAvailable("gmail") else {
                notify("이 빌드에는 Google 연결 정보가 아직 없습니다. 앱 제공자가 OAuth 앱을 등록해야 사용할 수 있습니다.")
                return
            }
        } catch { notify(error.localizedDescription); return }
        connecting = true
        Task {
            do {
                let client = try PluginAuth.configuration("google-client", environment: "WORKGRAPH_GOOGLE_CLIENT_ID")
                try await PluginAuth.connectGoogle(ids, clientID: client)
                connected.formUnion(ids)
            } catch { notify(error.localizedDescription) }
            connecting = false
        }
    }

    /// Args: id는 연결을 해제할 서비스이다.
    /// Returns: 없음. 저장된 OAuth 토큰을 제거한다.
    /// Raises: 없음. Keychain 오류는 화면에 표시한다.
    private func disconnect(_ id: String) {
        do { try PluginAuth.disconnect(id); connected.remove(id) }
        catch { notify(error.localizedDescription) }
    }

    /// Args: 없음.
    /// Returns: 없음. Keychain에서 설치 상태를 다시 읽는다.
    /// Raises: 없음. Keychain 오류는 화면에 표시한다.
    private func refresh() {
        do { connected = Set(try PluginEntry.all.filter { try PluginAuth.isConnected($0.id) }.map(\.id)) }
        catch { notify(error.localizedDescription) }
    }

    /// Args: message는 사용자에게 보여줄 연결 상태나 오류이다.
    /// Returns: 없음. 알림을 표시한다.
    /// Raises: 없음.
    private func notify(_ message: String) { notice = message; showNotice = true }
}
