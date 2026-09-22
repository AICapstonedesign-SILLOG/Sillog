import SwiftUI
import WorkGraphCollectors
import WorkGraphCore

/// 처음 실행했을 때(그리고 로그아웃했을 때) 보이는 화면. ChatGPT 로그인을 해야 앱을 쓸 수 있다.
///   1. 로그인 (필수)  2. 권한 안내 (한 번만)  → 수집 시작
struct OnboardingView: View {
    @EnvironmentObject private var state: AppState
    @State private var accessibility = Permissions.accessibility(prompt: false)
    @State private var screenRecording = Permissions.screenRecording()
    @State private var askedScreenRecording = false

    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Group {
                if state.phase == .login { loginStep } else { permissionStep }
            }
            .padding(.top, 28)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(poll) { _ in
            accessibility = Permissions.accessibility(prompt: false)
            screenRecording = Permissions.screenRecording()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.tint)
            HStack(spacing: 8) {
                stepBadge(1, title: "로그인", active: state.phase == .login, done: state.phase != .login)
                Rectangle().fill(.quaternary).frame(width: 28, height: 1)
                stepBadge(2, title: "권한", active: state.phase == .permissions, done: false)
            }
        }
    }

    private func stepBadge(_ number: Int, title: String, active: Bool, done: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle\(active ? ".fill" : "")")
                .foregroundStyle(done ? AnyShapeStyle(.green) : active ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            Text(title).font(.callout).foregroundStyle(active || done ? .primary : .tertiary)
        }
    }

    // MARK: 1. 로그인

    private var loginStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ChatGPT 계정으로 시작하기").font(.title).fontWeight(.semibold)
            Text("Mac 에서 한 일을 기록하고 업무 단위로 정리합니다. 시작하려면 로그인하세요.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let code = state.deviceCode {
                VStack(alignment: .leading, spacing: 10) {
                    Text("열린 브라우저에 이 코드를 입력하세요").font(.callout)
                    Text(code.userCode)
                        .font(.system(size: 34, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                    HStack {
                        Button("코드 복사") { state.copyDeviceCode() }
                        Button("브라우저 다시 열기") { NSWorkspace.shared.open(code.verificationURL) }
                        Button("취소") { state.cancelCodexLogin() }
                        ProgressView().controlSize(.small).padding(.leading, 4)
                    }
                    Text("코드는 복사돼 있습니다. 브라우저에 붙여 넣으세요.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            } else {
                Button("ChatGPT 로 로그인") { state.startCodexLogin() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }

            if let message = state.codexMessage, state.phase == .login {
                Text(message).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }

            Text("기록과 스크린샷은 이 Mac 에 저장됩니다. 정리할 때 창 제목, 주소, 화면 텍스트 일부가 ChatGPT 로 전송됩니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }

    // MARK: 2. 권한

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("화면을 읽을 권한 주기").font(.title).fontWeight(.semibold)
            Text("허용하면 무엇을 보고 있었는지까지 기록됩니다. 없어도 앱 이름은 기록됩니다.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                permissionRow("손쉬운 사용", detail: "창 제목, 주소, 문서 경로, 화면의 글자를 읽습니다", granted: accessibility) {
                    _ = Permissions.accessibility(prompt: true)
                    Permissions.openSettings(.accessibility)
                }
                Divider()
                permissionRow("화면 기록", detail: "스크린샷을 남기고, 글자를 읽을 수 없는 화면은 OCR 로 읽습니다", granted: screenRecording) {
                    Permissions.requestScreenRecording()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { Permissions.openSettings(.screenRecording) }
                    askedScreenRecording = true
                }
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            if askedScreenRecording, !screenRecording {
                HStack {
                    Text("화면 기록은 허용한 뒤 앱을 다시 켜야 적용됩니다.").font(.callout).foregroundStyle(.secondary)
                    Button("앱 다시 실행") { state.relaunch() }
                }
            }

            HStack {
                Button(accessibility && screenRecording ? "수집 시작" : "이대로 수집 시작") { state.completeOnboarding() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                if !(accessibility && screenRecording) {
                    Text("나중에 설정에서도 가능").font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
    }

    private func permissionRow(_ title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("허용됨", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("허용하기", action: action)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
