import SwiftUI

struct PluginEntry: Identifiable {
    let id: String
    let name: String
    let summary: String
    let description: String
    let examples: [String]

    static let all: [PluginEntry] = [
        .init(id: "gmail", name: "Gmail", summary: "메일 검색과 읽기",
              description: "연결한 계정의 메일을 찾아 읽어요. 메일을 보내거나 수정하지 않아요.",
              examples: ["지난주 받은 메일에서 내가 답해야 할 내용을 정리해 줘.", "최근 프로젝트 관련 메일의 결정 사항을 찾아 줘."]),
        .init(id: "drive", name: "Google Drive", summary: "파일 검색과 문서 읽기",
              description: "Drive에서 파일을 찾고 문서를 읽어요. 파일을 만들거나 수정하지 않아요.",
              examples: ["최근 작성한 기획서를 찾아 핵심 결정을 요약해 줘.", "내 Drive 자료를 바탕으로 발표 개요를 만들어 줘."]),
        .init(id: "github", name: "GitHub", summary: "저장소, 코드와 PR 읽기",
              description: "접근 권한이 있는 저장소의 코드와 PR을 읽어요. 저장소를 변경하지 않아요.",
              examples: ["내가 작업한 저장소의 구조와 주요 기능을 설명해 줘.", "최근 PR을 바탕으로 프로젝트 진행 상황을 정리해 줘."]),
        .init(id: "notion", name: "Notion", summary: "페이지 검색과 읽기",
              description: "통합에 공유한 Notion 페이지를 검색하고 읽어요. 페이지를 수정하지 않아요.",
              examples: ["최근 회의록에서 결정 사항과 다음 할 일을 찾아 줘.", "Notion에 정리한 자료를 바탕으로 계획을 세워줘."])
    ]
}

struct PluginCatalogView: View {
    var onClose: () -> Void
    var showsClose = true                                  // 설정 안에 넣을 때는 닫기 단추를 숨긴다
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
        VStack(spacing: 0) {
            BrandPageHeader(title: "플러그인") {
                if showsClose {
                    Button { onClose() } label: {
                        Image(systemName: "xmark").font(.system(size: 13)).foregroundStyle(Brand.tabText)
                            .frame(width: 28, height: 28).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("닫기")
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let selected { detail(selected) } else { catalog }
                }
                .frame(maxWidth: 800, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32).padding(.vertical, 20)
            }
            .background(.white)
            HStack {
                Spacer()
                Button("완료") { onClose() }.buttonStyle(BrandButtonStyle())
            }
            .padding(.horizontal, 32).frame(height: 56)
            .background(.white)
            .overlay(alignment: .top) { Rectangle().fill(Brand.line).frame(height: 1) }
        }
        .sheet(isPresented: $showGoogleInstall) { googleInstallSheet }
        .alert("플러그인 연결", isPresented: $showNotice) {
            Button("확인", role: .cancel) {}
        } message: { Text(notice ?? "") }
        .onAppear(perform: refresh)
    }

    private static let sky = Color(hex: 0x5E97C8)

    private var catalog: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Brand.gray)
                TextField("플러그인 검색", text: $query).textFieldStyle(.plain).font(Brand.suit(12)).foregroundStyle(Brand.text)
            }
            .frame(height: 32)
            .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
            if !connected.isEmpty {
                sectionLabel("설치됨")
                ForEach(PluginEntry.all.filter { connected.contains($0.id) }) { row($0) }
            }
            sectionLabel(query.isEmpty ? "플러그인 둘러보기" : "검색 결과")
            ForEach(filtered) { row($0) }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(Brand.suit(11, .medium)).foregroundStyle(Brand.gray).padding(.top, 20).padding(.bottom, 4)
    }

    /// 연결됨 표시: 작은 하늘색 점과 회색 글씨.
    private var connectedMark: some View {
        HStack(spacing: 5) {
            Circle().fill(Self.sky).frame(width: 5, height: 5)
            Text("연결됨").font(Brand.suit(11)).foregroundStyle(Brand.gray)
        }
    }

    /// 배경 없는 글자 단추.
    private func textButton(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Brand.suit(11, .medium)).foregroundStyle(Brand.tabText)
                .padding(.horizontal, 8).frame(height: 26).hoverHighlight(cornerRadius: 6).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.4 : 1)
    }

    /// Args: plugin은 목록에 표시할 서비스이다.
    /// Returns: 아이콘, 이름, 요약, 연결 상태가 있는 한 줄. 누르면 상세로 이동한다.
    /// Raises: 없음.
    private func row(_ plugin: PluginEntry) -> some View {
        HStack(spacing: 8) {
            Button { selectedID = plugin.id } label: {
                HStack(spacing: 12) {
                    pluginIcon(plugin, size: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plugin.name).font(Brand.suit(13)).foregroundStyle(Brand.ink)
                        Text(plugin.summary).font(Brand.suit(11)).foregroundStyle(Brand.gray)
                    }
                    Spacer(minLength: 8)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if connected.contains(plugin.id) {
                connectedMark
            } else {
                textButton("연결") { install(plugin) }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 10)
        .hoverHighlight(cornerRadius: 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
    }

    /// Args: plugin은 상세 화면에 표시할 서비스이다.
    /// Returns: 설치 상태, 사용 예시와 계정 연결 동작이 있는 상세 화면.
    /// Raises: 없음.
    private func detail(_ plugin: PluginEntry) -> some View {
        let on = connected.contains(plugin.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button { selectedID = nil } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left").font(.system(size: 10))
                    Text("플러그인").font(Brand.suit(12))
                }.foregroundStyle(Brand.gray).padding(.horizontal, 6).frame(height: 26).hoverHighlight(cornerRadius: 6).contentShape(Rectangle())
            }.buttonStyle(.plain)
            HStack(alignment: .center, spacing: 14) {
                pluginIcon(plugin, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(plugin.name).font(Brand.suit(22, .bold)).foregroundStyle(Brand.ink)
                    Text(plugin.summary).font(Brand.suit(12)).foregroundStyle(Brand.gray)
                }
                Spacer()
                if on {
                    connectedMark
                } else {
                    textButton(connecting ? "연결 중…" : "플러그인 설치", disabled: connecting) { install(plugin) }
                }
            }.padding(.top, 16)
            Text(plugin.description).font(Brand.suit(13)).foregroundStyle(Brand.gray).padding(.top, 20)
            Text("이렇게 활용할 수 있어요").font(Brand.suit(11, .medium)).foregroundStyle(Brand.gray).padding(.top, 28).padding(.bottom, 4)
            ForEach(plugin.examples, id: \.self) { example in
                HStack(spacing: 12) {
                    Text(example).font(Brand.suit(13)).foregroundStyle(Brand.ink).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    textButton(on ? "채팅에서 써 보기" : "연결하고 써 보기") {
                        if on { onUseInChat(plugin.id, example) } else { install(plugin) }
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 8)
                .hoverHighlight(cornerRadius: 6)
                .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
            }
            if let verificationCode, plugin.id == "github" {
                VStack(alignment: .leading, spacing: 6) {
                    Text("GitHub 승인 코드").font(Brand.suit(11, .medium)).foregroundStyle(Brand.gray)
                    Text(verificationCode).font(Brand.jost(32)).foregroundStyle(Brand.ink).textSelection(.enabled)
                }.padding(.top, 24).padding(.horizontal, 8)
            }
            if on {
                HStack(spacing: 4) {
                    textButton("다시 연결", disabled: connecting) { install(plugin) }
                    textButton("연결 해제") { disconnect(plugin.id) }
                }.padding(.top, 20)
            }
        }
    }

    /// Args: plugin은 아이콘을 표시할 서비스, size는 아이콘 영역의 한 변이다.
    /// Returns: 앱에 포함된 서비스 공식 아이콘. 바탕과 테두리 없이 그린다.
    /// Raises: 없음.
    private func pluginIcon(_ plugin: PluginEntry, size: CGFloat) -> some View {
        let url = Bundle.main.url(forResource: plugin.id, withExtension: "png", subdirectory: "PluginIcons")
            ?? Bundle.module.url(forResource: plugin.id, withExtension: "png", subdirectory: "PluginIcons")
        let image = url.flatMap { NSImage(contentsOf: $0) } ?? NSImage()
        return Image(nsImage: image).resizable().scaledToFit()
            .frame(width: size * 0.8, height: size * 0.8)
            .frame(width: size, height: size)
    }

    private var googleInstallSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandPageHeader(title: "설치할 Google 플러그인 선택", detail: "승인할 자료만 골라 주세요. 연결한 뒤에도 각 플러그인을 해제할 수 있어요.") {
                Button { showGoogleInstall = false } label: {
                    Image(systemName: "xmark").font(.system(size: 13)).foregroundStyle(Brand.tabText)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("닫기")
            }
            VStack(spacing: 0) {
                ForEach(PluginEntry.all.filter { ["gmail", "drive"].contains($0.id) }) { plugin in
                    let picked = googleSelection.contains(plugin.id)
                    Button {
                        if picked { googleSelection.remove(plugin.id) } else { googleSelection.insert(plugin.id) }
                    } label: {
                        HStack(spacing: 12) {
                            pluginIcon(plugin, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plugin.name).font(Brand.suit(13)).foregroundStyle(Brand.ink)
                                Text(plugin.summary).font(Brand.suit(11)).foregroundStyle(Brand.gray)
                            }
                            Spacer()
                            if picked { Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Self.sky) }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 12).contentShape(Rectangle())
                        .hoverHighlight(cornerRadius: 6)
                        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 32).padding(.top, 4)
            HStack {
                Spacer()
                Button("Google에서 계속") { showGoogleInstall = false; connectGoogle() }
                    .buttonStyle(BrandButtonStyle(kind: .primary)).disabled(googleSelection.isEmpty)
            }.padding(.horizontal, 32).frame(height: 56).background(.white)
                .overlay(alignment: .top) { Rectangle().fill(Brand.line).frame(height: 1) }
        }.frame(width: 560).background(.white)
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
