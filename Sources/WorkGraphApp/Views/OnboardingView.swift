import SwiftUI
import WorkGraphCollectors
import WorkGraphCore

/// 온보딩 시트를 띄우는 덮개: 창 전체를 옅게 덮고 카드(760)를 탭 막대 바로 아래에 둔다 (Figma OUT-01~05).
/// 창이 낮아 카드가 다 들어가지 않으면 가운데로 올리고, 그래도 넘치면 스크롤한다.
struct OnboardingOverlay: View {
    let step: OnboardingStep
    @State private var cardHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color(hex: 0x141210, opacity: 0.16)
                ScrollView {
                    OnboardingSheet(step: step)
                        .background(GeometryReader { Color.clear.preference(key: SheetHeightKey.self, value: $0.size.height) })
                        .padding(.top, OnboardingFlow.sheetTop(available: geo.size.height, card: cardHeight))
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .background(ResignFocus())
        .onPreferenceChange(SheetHeightKey.self) { cardHeight = $0 }
    }
}

private struct SheetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// 시트가 뜨는 순간 창의 키보드 포커스를 비운다. 시트 뒤 채팅 입력칸(NSTextView)이나 그래프(WKWebView)가 타이핑을 받지 않게
private struct ResignFocus: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.makeFirstResponder(nil) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// "무엇이 기기 밖으로 나가나요?" 안내. 시트(OUT-01)와 로그인 오류 카드(OUT-W1)가 같이 쓴다.
/// W1 의 Figma 문구는 대표 화면 이미지 전송을 빠뜨려(스크린샷 카드가 기본으로 켜져 있다) 시트 문구로 맞춘다
enum PrivacyNote {
    static let title = "무엇이 기기 밖으로 나가나요?"
    static let body = "기록은 Mac에 저장돼요. 업무를 정리할 때 창 제목, 주소, 화면 텍스트와 대표 화면 이미지가 연결한 AI로 전송돼요. 채팅에서 조회한 원문, 코드, 문서도 전송될 수 있어요. 허용한 웹 검색과 플러그인은 외부 서비스와 통신해요."
}

/// 온보딩 카드: 머리(눈썹 글씨, 제목, 닫기), 본문(1 로그인 / 2 권한), 바닥(단계 표시, 다음 버튼)
struct OnboardingSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismissWindow) private var dismissWindow
    let step: OnboardingStep
    @State private var deviceHelpOpen = false

    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var loggedIn: Bool { state.phase != .login }

    var body: some View {
        VStack(spacing: 0) {
            header
            if step == .login { loginBody } else { permissionBody }
            footer
        }
        .frame(width: 760)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: 0x141210, opacity: 0.12)))
        .shadow(color: Color(hex: 0x141210, opacity: 0.15), radius: 21, y: 14)
        .onAppear { state.refreshPermissionGrants() }
        .onReceive(poll) { _ in if step == .permissions { state.refreshPermissionGrants() } }
    }

    // MARK: 머리 (105)

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(step == .login ? "GET STARTED / 01" : "GET STARTED / 02").frame(height: 17, alignment: .leading)
            Text(step == .login ? "당신의 일을 기억하는 시작" : "기록을 위한 두 가지 권한")
                .font(Brand.suit(22)).tracking(-0.77).foregroundStyle(Brand.ink)
                .padding(.top, 9)
        }
        .padding(.leading, 28).padding(.top, 26)
        .frame(maxWidth: .infinity, minHeight: 105, maxHeight: 105, alignment: .topLeading)
        .background(.white.opacity(0.95))
        .overlay(alignment: .topTrailing) {
            // 닫기: 창만 닫는다. 메뉴 막대는 준비 전(W2)으로 남고, 거기서 다시 열 수 있다
            Button {
                state.closeOnboarding()
                dismissWindow(id: "main")
            } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .light)).foregroundStyle(Brand.tabText)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("닫기").accessibilityLabel("닫기")
            .padding(.top, 19).padding(.trailing, 18)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.hairline).frame(height: 1) }
    }

    // MARK: 1. 로그인

    private var loginBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                brandColumn
                    .frame(width: 260).frame(maxHeight: .infinity)
                    .overlay(alignment: .trailing) { Rectangle().fill(Brand.line).frame(width: 1) }
                loginColumn.frame(maxHeight: .infinity, alignment: .top)
            }
            .fixedSize(horizontal: false, vertical: true)
            privacyNote
        }
    }

    private var brandColumn: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit().frame(width: 112, height: 112)
            Group {
                if let mark = Brand.wordmark {
                    Image(nsImage: mark).resizable().scaledToFit().frame(height: 26).accessibilityLabel("SILLOG")
                } else {
                    Text("SILLOG").font(Brand.suit(18, .semibold)).foregroundStyle(Brand.ink)
                }
            }
            .padding(.top, 33)
            Text("흩어진 기록을 모아,\n다음 일의 맥락으로.")
                .font(Brand.suit(13)).foregroundStyle(Brand.gray).multilineTextAlignment(.center).lineSpacing(8)
                .padding(.top, 34)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loginColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("내 ChatGPT 계정으로 연결해요.").font(Brand.suit(17, .medium)).foregroundStyle(Brand.ink)
            Text("별도의 Sillog 계정 없이 시작할 수 있어요.\n로그인 토큰은 이 기기에만 저장돼요.")
                .font(Brand.suit(12)).foregroundStyle(Brand.gray).lineSpacing(8)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 13)
            if loggedIn {
                signedInBox.padding(.top, 21)
            } else {
                Button { loginAction() } label: {
                    HStack(spacing: 8) {
                        Text("ChatGPT로 로그인")
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(OnboardingPrimaryStyle(height: 42))
                .keyboardShortcut(.defaultAction)
                .padding(.top, 21)
                if let code = state.deviceCode { deviceCodeBox(code).padding(.top, 15) }
            }
            apiKeyRow.padding(.top, 16)
            if !loggedIn, let message = state.codexMessage { errorBox(message).padding(.top, 14) }
            deviceHelp.padding(.top, 15)
        }
        .padding(.horizontal, 31).padding(.vertical, 30)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// 코드를 받기 전에는 로그인을 시작하고, 받은 뒤에는 승인 페이지를 다시 연다
    private func loginAction() {
        if let code = state.deviceCode { NSWorkspace.shared.open(code.verificationURL) } else { state.startCodexLogin() }
    }

    private func deviceCodeBox(_ code: DeviceCode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("DEVICE CODE").frame(height: 17, alignment: .leading)
            HStack {
                Text(code.userCode).font(Brand.jost(23)).tracking(2.99).foregroundStyle(Brand.ink).textSelection(.enabled)
                Spacer()
                Button { state.copyDeviceCode() } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 13)).foregroundStyle(Brand.tabText)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("기기 코드 복사").accessibilityLabel("기기 코드 복사")
            }
            .frame(height: 38)
            .padding(.top, 5)
            Text("15분 안에 브라우저에서 승인해요.").font(Brand.suit(10)).foregroundStyle(Brand.gray).padding(.top, 5)
        }
        .padding(.horizontal, 17).padding(.top, 15).padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
    }

    /// 로그인을 마친 뒤: 로그인 버튼 자리에 연결한 계정 (Figma 에 없는 상태)
    private var signedInBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("SIGNED IN").frame(height: 17, alignment: .leading)
            HStack(spacing: 8) {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .medium))
                Text(signedInName).font(Brand.suit(15, .medium)).lineLimit(1)
            }
            .foregroundStyle(Brand.ink)
            .padding(.top, 9)
            Text("로그인을 마쳤어요. 아래 버튼으로 다음 단계로 넘어가요.").font(Brand.suit(10)).foregroundStyle(Brand.gray).padding(.top, 8)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
    }

    private var signedInName: String {
        if case .loggedIn(let email, _, _) = state.codexStatus, let email, !email.isEmpty { return email }
        return "ChatGPT 계정"
    }

    /// API 키 로그인은 아직 없다: '예정' 표시만, 누를 수 없다
    private var apiKeyRow: some View {
        HStack(spacing: 7) {
            Text("API 키로 시작").font(Brand.suit(11)).foregroundStyle(Brand.tabText)
            Text("예정").font(Brand.suit(10, .medium)).foregroundStyle(Brand.gray)
                .frame(width: 31, height: 20)
                .background(RoundedRectangle(cornerRadius: 4).fill(Brand.paper))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Brand.line))
        }
        .padding(.leading, 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("API 키로 시작, 예정")
    }

    private func errorBox(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle").font(.system(size: 13)).foregroundStyle(Brand.gray)
            Text(message).font(Brand.suit(11)).foregroundStyle(Brand.text).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Brand.paper))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
    }

    private var deviceHelp: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { deviceHelpOpen.toggle() } label: {
                HStack(spacing: 6) {
                    Text(deviceHelpOpen ? "▾" : "▸").font(.system(size: 8))
                    Text("기기 코드 로그인이 꺼져 있나요?").font(Brand.suit(10))
                }
                .foregroundStyle(Brand.gray)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if deviceHelpOpen {
                Text("ChatGPT 계정에서 기기 코드 로그인을 켠 뒤 다시 시도해 주세요.").font(Brand.suit(10)).foregroundStyle(Brand.gray)
            }
        }
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "checkmark.shield").font(.system(size: 15)).foregroundStyle(Brand.ink).frame(width: 15)
            VStack(alignment: .leading, spacing: 8) {
                Text(PrivacyNote.title).font(Brand.suit(12, .medium)).foregroundStyle(Brand.ink)
                Text(PrivacyNote.body)
                    .font(Brand.suit(11)).foregroundStyle(Brand.gray).lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 40).padding(.trailing, 31).padding(.top, 31).padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Brand.line).frame(height: 1) }
    }

    // MARK: 2. 권한

    private var permissionBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("기록할 범위를 직접 정할 수 있어요.\n권한은 언제든 macOS 설정에서 바꿀 수 있어요.")
                .font(Brand.suit(13)).foregroundStyle(Brand.gray).lineSpacing(8)
                .padding(.bottom, 16)
            permissionRow("location", mirrored: true, "손쉬운 사용", detail: "앱 이름, 창 제목과 화면 텍스트를 읽어요.",
                          granted: state.permissionGrants.accessibility) {
                _ = Permissions.accessibility(prompt: true)
                Permissions.openSettings(.accessibility)
            }
            permissionRow("display", "화면 기록", detail: "활성 창의 스크린샷과 화면 내용을 기록해요.",
                          granted: state.permissionGrants.screenRecording) {
                Permissions.requestScreenRecording()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { Permissions.openSettings(.screenRecording) }
                state.askedScreenRecording = true
            }
            if state.askedScreenRecording { relaunchRow }       // OUT-05: 허용 여부와 상관없이 이번 실행에서 요청했으면
        }
        .padding(.horizontal, 30).padding(.top, 32).padding(.bottom, 43)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 아이콘은 Figma 처럼 외곽선: 손쉬운 사용은 왼쪽 위를 가리키는 화살표(location 을 좌우로 뒤집음), 화면 기록은 단색 모니터
    private func permissionRow(_ icon: String, mirrored: Bool = false, _ title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Image(systemName: icon).symbolRenderingMode(.monochrome).font(.system(size: 22, weight: .light)).foregroundStyle(Brand.tabText)
                .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                .frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(Brand.suit(15, .medium)).foregroundStyle(Brand.ink)
                Text(detail).font(Brand.suit(12)).foregroundStyle(Brand.gray)
            }
            .padding(.leading, 20)
            Spacer()
            if granted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .medium))
                    Text("허용됨")
                }
                .font(Brand.suit(11, .medium)).foregroundStyle(Brand.tabText)
                .padding(.horizontal, 12).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
            } else {
                Button("허용하기", action: action).buttonStyle(OnboardingSecondaryStyle())
            }
        }
        .frame(height: 105)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
    }

    private var relaunchRow: some View {
        HStack {
            Text("화면 기록 권한은 앱을 다시 실행해야 적용돼요.").font(Brand.suit(11)).foregroundStyle(Brand.gray)
            Spacer()
            Button { state.relaunch() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 11))
                    Text("다시 실행")
                }
            }
            .buttonStyle(OnboardingSecondaryStyle())
        }
        .frame(height: 68)
    }

    // MARK: 바닥 (73)

    private var footer: some View {
        HStack {
            HStack(spacing: 0) {
                stepLabel("01 로그인", on: step == .login)
                Rectangle().fill(Brand.line).frame(width: 24, height: 1).padding(.leading, 15).padding(.trailing, 12)
                stepLabel("02 권한", on: step == .permissions)
            }
            Spacer()
            if step == .login {
                let canGo = OnboardingFlow.canAdvance(from: .login, phase: state.phase)
                Button { state.advanceOnboarding() } label: { arrowLabel("로그인 완료, 다음") }
                    .buttonStyle(OnboardingPrimaryStyle(height: 38))
                    .fixedSize()
                    .opacity(canGo ? 1 : 0.38)
                    .disabled(!canGo)
                    .keyboardShortcut(canGo ? .defaultAction : nil)
            } else {
                // 권한이 없어도 시작할 수 있어야 해서 누르는 것은 늘 되고, 준비되지 않았으면 흐리게만 보인다
                Button { state.completeOnboarding() } label: { arrowLabel("수집 시작") }
                    .buttonStyle(OnboardingPrimaryStyle(height: 38))
                    .fixedSize()
                    .opacity(OnboardingFlow.startLooksReady(state.permissionGrants, askedScreenRecording: state.askedScreenRecording) ? 1 : 0.38)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 25)
        .frame(height: 73)
        .background(.white.opacity(0.95))
        .overlay(alignment: .top) { Rectangle().fill(Brand.hairline).frame(height: 1) }
    }

    private func stepLabel(_ text: String, on: Bool) -> some View {
        Text(text).font(Brand.suit(10, on ? .semibold : .regular)).foregroundStyle(on ? Brand.ink : Brand.gray)
    }

    private func arrowLabel(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text)
            Image(systemName: "arrow.right").font(.system(size: 11, weight: .medium))
        }
    }
}

/// 온보딩 카드 안 주색 버튼 (주색 바탕, 흰 글씨 12 Medium, 모서리 6)
struct OnboardingPrimaryStyle: ButtonStyle {
    var height: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Brand.suit(12, .medium)).foregroundStyle(.white)
            .padding(.horizontal, 20).frame(height: height)
            .background(RoundedRectangle(cornerRadius: 6).fill(Brand.ink))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

/// 흰 바탕 테두리 버튼 (허용하기, 다시 실행)
struct OnboardingSecondaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Brand.suit(11, .medium)).foregroundStyle(Brand.tabText)
            .padding(.horizontal, 12).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 6).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

// MARK: 시작 상태 화면 (Figma OUT-W4, OUT-W3)

/// 불러오는 중: 흰 바탕 가운데 회전 표시
struct BrandLoadingView: View {
    var body: some View {
        ProgressView().controlSize(.regular)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white)
    }
}

/// 시작 실패: 경고 아이콘, 제목, 원인 문장
struct BrandStartupErrorView: View {
    let message: String
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 30, weight: .light)).foregroundStyle(Brand.gray)
            Text("시작하지 못했어요").font(Brand.suit(22, .bold)).foregroundStyle(Brand.ink).padding(.top, 30)
            Text(message).font(Brand.suit(14)).foregroundStyle(Brand.gray).multilineTextAlignment(.center)
                .textSelection(.enabled).padding(.top, 17)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white)
    }
}
