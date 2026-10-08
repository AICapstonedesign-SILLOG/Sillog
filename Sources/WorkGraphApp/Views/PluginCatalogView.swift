import SwiftUI

private struct PluginEntry: Identifiable {
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

    private static let soft = Color(hex: 0xF6F5F4)

    private var selected: PluginEntry? { PluginEntry.all.first { $0.id == selectedID } }
    private var filtered: [PluginEntry] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? PluginEntry.all : PluginEntry.all.filter {
            $0.name.localizedCaseInsensitiveContains(text) || $0.summary.localizedCaseInsensitiveContains(text)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            BrandPageHeader(eyebrow: "CONNECTED SOURCES", title: "플러그인", detail: "외부 서비스를 연결해 채팅에서 내 자료를 활용해요.") {
                Button { onClose() } label: {
                    Image(systemName: "xmark").font(.system(size: 13)).foregroundStyle(Brand.tabText)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("닫기")
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
            .padding(.horizontal, 32).frame(height: 63)
            .background(Self.soft)
            .overlay(alignment: .top) { Rectangle().fill(Brand.line).frame(height: 1) }
        }
        .sheet(isPresented: $showGoogleInstall) { googleInstallSheet }
        .alert("플러그인 연결", isPresented: $showNotice) {
            Button("확인", role: .cancel) {}
        } message: { Text(notice ?? "") }
        .onAppear(perform: refresh)
    }

    private var catalog: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Brand.gray)
                TextField("플러그인 검색", text: $query).textFieldStyle(.plain).font(Brand.suit(12)).foregroundStyle(Brand.text)
            }.brandField().padding(.bottom, 8)
            if !connected.isEmpty {
                sectionLabel("설치됨")
                ForEach(PluginEntry.all.filter { connected.contains($0.id) }) { row($0) }
            }
            sectionLabel(query.isEmpty ? "플러그인 둘러보기" : "검색 결과")
            ForEach(filtered) { row($0) }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(Brand.suit(11, .medium)).foregroundStyle(Brand.gray).padding(.top, 16).padding(.bottom, 4)
    }

    /// Args: plugin은 목록에 표시할 서비스이다.
    /// Returns: 아이콘, 이름, 요약, 연결 상태가 있는 한 줄. 누르면 상세로 이동한다.
    /// Raises: 없음.
    private func row(_ plugin: PluginEntry) -> some View {
        let on = connected.contains(plugin.id)
        return Button { selectedID = plugin.id } label: {
            HStack(spacing: 12) {
                pluginIcon(plugin, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.name).font(Brand.suit(12, .medium)).foregroundStyle(Brand.tabText)
                    Text(plugin.summary).font(Brand.suit(10)).foregroundStyle(Brand.gray)
                }
                Spacer(minLength: 8)
                if on {
                    Text("설치됨").font(Brand.suit(10, .medium)).foregroundStyle(Brand.gray)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Self.soft))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Brand.line))
                } else {
                    Text("연결").font(Brand.suit(11, .medium)).foregroundStyle(Brand.tabText)
                        .padding(.horizontal, 12).frame(height: 30)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
                }
            }
            .padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    /// Args: plugin은 상세 화면에 표시할 서비스이다.
    /// Returns: 설치 상태, 사용 예시와 계정 연결 동작이 있는 상세 화면.
    /// Raises: 없음.
    private func detail(_ plugin: PluginEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { selectedID = nil } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left").font(.system(size: 10))
                    Text("플러그인").font(Brand.suit(13))
                }.foregroundStyle(Brand.gray)
            }.buttonStyle(.plain)
            HStack(alignment: .center, spacing: 16) {
                pluginIcon(plugin, size: 60)
                VStack(alignment: .leading, spacing: 5) {
                    Text(plugin.name).font(Brand.suit(22, .bold)).foregroundStyle(Brand.ink)
                    Text(plugin.summary).font(Brand.suit(13)).foregroundStyle(Brand.gray)
                }
                Spacer()
                if connected.contains(plugin.id) {
                    Button("채팅에서 사용해 보기") { onUseInChat(plugin.id, plugin.examples[0]) }
                        .buttonStyle(BrandButtonStyle(kind: .primary))
                } else {
                    Button(connecting ? "연결 중…" : "플러그인 설치") { install(plugin) }
                        .buttonStyle(BrandButtonStyle(kind: .primary)).disabled(connecting)
                }
            }.padding(.top, 16)
            Text(plugin.description).font(Brand.suit(14)).foregroundStyle(Brand.gray).padding(.top, 24)
            Text("이렇게 활용할 수 있어요").font(Brand.suit(14, .medium)).foregroundStyle(Brand.ink).padding(.top, 28)
            VStack(spacing: 8) {
                ForEach(plugin.examples, id: \.self) { example in
                    Button { if connected.contains(plugin.id) { onUseInChat(plugin.id, example) } else { install(plugin) } } label: {
                        HStack(spacing: 12) {
                            Text(example).font(Brand.suit(13)).foregroundStyle(Brand.ink).multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(Brand.gray)
                        }.padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .background(Self.soft, in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }.padding(.top, 12)
            if let verificationCode, plugin.id == "github" {
                Text("GitHub 승인 코드: \(verificationCode)")
                    .font(.system(size: 14, design: .monospaced)).foregroundStyle(Brand.ink).textSelection(.enabled)
                    .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .background(Self.soft, in: RoundedRectangle(cornerRadius: 10)).padding(.top, 16)
            }
            if connected.contains(plugin.id) {
                Rectangle().fill(Brand.line).frame(height: 1).padding(.top, 16)
                HStack(spacing: 8) {
                    Button("다시 연결") { install(plugin) }.buttonStyle(BrandButtonStyle()).disabled(connecting)
                    Button("연결 해제") { disconnect(plugin.id) }.buttonStyle(BrandButtonStyle())
                }.padding(.top, 16)
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
            .frame(width: size * 0.55, height: size * 0.55)
            .frame(width: size, height: size)
            .background(Self.soft, in: RoundedRectangle(cornerRadius: size * 0.23))
            .overlay(RoundedRectangle(cornerRadius: size * 0.23).strokeBorder(Brand.line))
    }

    private var googleInstallSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandPageHeader(eyebrow: "CONNECTED SOURCES", title: "설치할 Google 플러그인 선택", detail: "승인할 자료만 골라 주세요. 연결한 뒤에도 각 플러그인을 해제할 수 있어요.") {
                Button { showGoogleInstall = false } label: {
                    Image(systemName: "xmark").font(.system(size: 13)).foregroundStyle(Brand.tabText)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("닫기")
            }
            VStack(spacing: 0) {
                ForEach(PluginEntry.all.filter { ["gmail", "drive"].contains($0.id) }) { plugin in
                    HStack(spacing: 12) {
                        pluginIcon(plugin, size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(plugin.name).font(Brand.suit(13, .medium)).foregroundStyle(Brand.ink)
                            Text(plugin.summary).font(Brand.suit(10)).foregroundStyle(Brand.gray)
                        }
                        Spacer()
                        Toggle("", isOn: googleBinding(plugin.id)).toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }.padding(.vertical, 16)
                        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
                }
            }.padding(.horizontal, 32).padding(.top, 4)
            HStack {
                Spacer()
                Button("Google에서 계속") { showGoogleInstall = false; connectGoogle() }
                    .buttonStyle(BrandButtonStyle(kind: .primary)).disabled(googleSelection.isEmpty)
            }.padding(.horizontal, 32).frame(height: 63).background(Self.soft)
                .overlay(alignment: .top) { Rectangle().fill(Brand.line).frame(height: 1) }
        }.frame(width: 560).background(.white)
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
