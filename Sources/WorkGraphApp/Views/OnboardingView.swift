import SwiftUI
import WorkGraphCollectors
import WorkGraphCore

/// 처음 실행했을 때(그리고 로그아웃했을 때) 보이는 화면. ChatGPT 로그인을 해야 앱을 쓸 수 있다.
///   1. 로그인 (필수)  2. 권한 안내 (한 번만)  → 수집 시작
/// Figma OUT-01~05, OUT-W1: 흰 카드 하나(머리, 본문, 바닥 단계 표시)를 창 가운데에 둔다.
struct OnboardingView: View {
    @EnvironmentObject private var state: AppState
    @State private var accessibility = Permissions.accessibility(prompt: false)
    @State private var screenRecording = Permissions.screenRecording()
    @State private var askedScreenRecording = false
    @State private var deviceHelpOpen = false

    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var isLogin: Bool { state.phase == .login }
    private var allGranted: Bool { accessibility && screenRecording }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                card
                    .frame(width: 760)
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
        }
        .background(Color(hex: 0xF6F5F4))
        .onReceive(poll) { _ in
            accessibility = Permissions.accessibility(prompt: false)
            screenRecording = Permissions.screenRecording()
        }
    }

    // MARK: 카드

    private var card: some View {
        VStack(spacing: 0) {
            cardHeader
            if isLogin { loginBody } else { permissionBody }
            cardFooter
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(red: 20 / 255, green: 18 / 255, blue: 16 / 255).opacity(0.12)))
        .shadow(color: Color(red: 20 / 255, green: 18 / 255, blue: 16 / 255).opacity(0.15), radius: 21, y: 14)
    }

    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(isLogin ? "GET STARTED / 01" : "GET STARTED / 02")
            Text(isLogin ? "ChatGPT 계정으로 시작하기" : "기록을 위한 두 가지 권한")
                .font(Brand.suit(22)).tracking(-0.77).foregroundStyle(Brand.ink)
                .padding(.top, 10)
        }
        .padding(.horizontal, 27).padding(.top, 25).padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.95))
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.hairline).frame(height: 1) }
    }

    private var cardFooter: some View {
        HStack {
            HStack(spacing: 12) {
                Text("01 로그인").font(Brand.suit(10, isLogin ? .semibold : .regular)).foregroundStyle(isLogin ? Brand.ink : Brand.gray)
                Rectangle().fill(Brand.line).frame(width: 24, height: 1)
                Text("02 권한").font(Brand.suit(10, isLogin ? .regular : .semibold)).foregroundStyle(isLogin ? Brand.gray : Brand.ink)
            }
            Spacer()
            if !isLogin {
                // ponytail: 권한이 없어도 시작할 수 있어야 해서 눌림은 유지하고, Figma처럼 흐리게만 보인다.
                Button { state.completeOnboarding() } label: {
                    HStack(spacing: 8) {
                        Text("수집 시작")
                        Image(systemName: "arrow.right").font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(OnboardingPrimaryStyle(height: 38))
                .fixedSize()
                .opacity(allGranted ? 1 : 0.38)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 73)
        .background(.white.opacity(0.95))
        .overlay(alignment: .top) { Rectangle().fill(Brand.hairline).frame(height: 1) }
    }

    // MARK: 1. 로그인

    private var loginBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                brandColumn
                    .frame(width: 260)
                    .overlay(alignment: .trailing) { Rectangle().fill(Brand.line).frame(width: 1) }
                loginColumn
            }
            privacyNote
        }
    }

    private var brandColumn: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit().frame(width: 140, height: 140)
            Group {
                if let mark = Brand.wordmark {
                    Image(nsImage: mark).resizable().scaledToFit().frame(height: 26).accessibilityLabel("SILLOG")
                } else {
                    Text("SILLOG").font(Brand.suit(18, .semibold)).foregroundStyle(Brand.ink)
                }
            }
            .padding(.top, 16)
            Text("흩어진 기록을 모아,\n다음 일의 맥락으로.")
                .font(Brand.suit(13)).foregroundStyle(Brand.gray).multilineTextAlignment(.center).lineSpacing(6)
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 30)
    }

    private var loginColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Mac에서 한 일을 기록하고 업무 단위로 정리해요.\n시작하려면 로그인해 주세요.")
                .font(Brand.suit(12)).foregroundStyle(Brand.gray).lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)

            if let code = state.deviceCode {
                deviceCodeBox(code).padding(.top, 22)
                Button { NSWorkspace.shared.open(code.verificationURL) } label: {
                    HStack(spacing: 8) {
                        Text("브라우저 다시 열기")
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(OnboardingPrimaryStyle(height: 42))
                .padding(.top, 18)
            } else {
                Button { state.startCodexLogin() } label: {
                    HStack(spacing: 8) {
                        Text("ChatGPT로 로그인")
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(OnboardingPrimaryStyle(height: 42))
                .keyboardShortcut(.defaultAction)
                .padding(.top, 22)
            }

            if let message = state.codexMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 13)).foregroundStyle(Brand.gray)
                    Text(message).font(Brand.suit(11)).foregroundStyle(Brand.text).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0xF6F5F4)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
                .padding(.top, 16)
            } else {
                deviceHelp.padding(.top, 14)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func deviceCodeBox(_ code: DeviceCode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("DEVICE CODE")
            HStack {
                Text(code.userCode).font(Brand.jost(23)).tracking(2.99).foregroundStyle(Brand.ink).textSelection(.enabled)
                Spacer()
                Button { state.copyDeviceCode() } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 13)).foregroundStyle(Brand.tabText).frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("기기 코드 복사")
                .accessibilityLabel("기기 코드 복사")
            }
            .padding(.top, 6)
            HStack(spacing: 10) {
                Text("코드는 복사돼 있어요. 브라우저에 붙여 넣어 승인해요.")
                    .font(Brand.suit(10)).foregroundStyle(Brand.gray)
                Spacer()
                ProgressView().controlSize(.small)
                Button("취소") { state.cancelCodexLogin() }
                    .buttonStyle(.plain).font(Brand.suit(11)).foregroundStyle(Brand.tabText)
            }
            .padding(.top, 6)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
    }

    private var deviceHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { deviceHelpOpen.toggle() } label: {
                HStack(spacing: 4) {
                    Text(deviceHelpOpen ? "▾" : "▸")
                    Text("기기 코드 로그인이 꺼져 있나요?")
                }
                .font(Brand.suit(10)).foregroundStyle(Brand.gray)
            }
            .buttonStyle(.plain)
            if deviceHelpOpen {
                Text("ChatGPT 계정에서 기기 코드 로그인을 켠 뒤 다시 시도해 주세요.")
                    .font(Brand.suit(10)).foregroundStyle(Brand.gray)
            }
        }
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield").font(.system(size: 15)).foregroundStyle(Brand.ink).padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text("무엇이 기기 밖으로 나가나요?").font(Brand.suit(12, .medium)).foregroundStyle(Brand.ink)
                Text("기록과 스크린샷은 이 Mac에 저장돼요. 정리할 때 창 제목, 주소, 화면 텍스트 일부가 ChatGPT로 전송돼요.")
                    .font(Brand.suit(11)).foregroundStyle(Brand.gray).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 30).padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Brand.line).frame(height: 1) }
    }

    // MARK: 2. 권한

    private var permissionBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("기록할 범위를 직접 정할 수 있어요.\n권한은 언제든 macOS 설정에서 바꿀 수 있어요.")
                .font(Brand.suit(13)).foregroundStyle(Brand.gray).lineSpacing(8)
                .padding(.bottom, 20)
            permissionRow("cursorarrow", "손쉬운 사용", detail: "앱 이름, 창 제목과 화면 텍스트를 읽어요.", granted: accessibility) {
                _ = Permissions.accessibility(prompt: true)
                Permissions.openSettings(.accessibility)
            }
            permissionRow("display", "화면 기록", detail: "활성 창의 스크린샷과 화면 내용을 기록해요.", granted: screenRecording) {
                Permissions.requestScreenRecording()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { Permissions.openSettings(.screenRecording) }
                askedScreenRecording = true
            }
            if askedScreenRecording, !screenRecording {
                HStack {
                    Text("화면 기록 권한은 앱을 다시 실행해야 적용돼요.").font(Brand.suit(11)).foregroundStyle(Brand.gray)
                    Spacer()
                    Button { state.relaunch() } label: {
                        HStack(spacing: 6) { Image(systemName: "arrow.counterclockwise").font(.system(size: 11)); Text("다시 실행") }
                    }
                    .buttonStyle(OnboardingSecondaryStyle())
                }
                .padding(.vertical, 19)
            }
        }
        .padding(.horizontal, 30).padding(.vertical, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func permissionRow(_ icon: String, _ title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 18) {
            Image(systemName: icon).font(.system(size: 22, weight: .light)).foregroundStyle(Brand.tabText).frame(width: 27)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Brand.suit(15, .medium)).foregroundStyle(Brand.ink)
                Text(detail).font(Brand.suit(12)).foregroundStyle(Brand.gray)
            }
            Spacer()
            if granted {
                HStack(spacing: 6) { Image(systemName: "checkmark").font(.system(size: 10, weight: .medium)); Text("허용됨") }
                    .font(Brand.suit(11, .medium)).foregroundStyle(Brand.tabText)
                    .padding(.horizontal, 12).frame(height: 30)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
            } else {
                Button("허용하기", action: action).buttonStyle(OnboardingSecondaryStyle())
            }
        }
        .frame(height: 105)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
    }
}

/// 온보딩 카드 안 주색 버튼 (Figma: 주색 바탕, 흰 글씨 12 Medium, 모서리 6)
private struct OnboardingPrimaryStyle: ButtonStyle {
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
private struct OnboardingSecondaryStyle: ButtonStyle {
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

// MARK: 시작 상태 화면 (Figma OUT-W4, OUT-W3). MainWindow에서 ProgressView와 ContentUnavailableView 자리에 쓴다.

/// 불러오는 중: 흰 바탕 가운데 작은 회전 표시
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
            Image(systemName: "exclamationmark.triangle").font(.system(size: 28, weight: .ultraLight)).foregroundStyle(Brand.gray)
            Text("시작하지 못했어요").font(Brand.suit(17, .semibold)).foregroundStyle(Brand.ink).padding(.top, 20)
            Text(message).font(Brand.suit(11)).foregroundStyle(Brand.gray).multilineTextAlignment(.center)
                .textSelection(.enabled).padding(.top, 12)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white)
    }
}
