import SwiftUI
import WorkGraphCore

/// 기기 코드 로그인이 꺼진 계정이라 로그인을 시작하지 못했을 때 (Figma OUT-W1, 예전 스타일 카드 그대로).
/// "ChatGPT로 로그인"을 다시 누르면 오류가 지워지고 탭과 온보딩 시트로 돌아간다.
struct LoginBlockedView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                card
                    .frame(width: 1000)
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
        }
        .background(Brand.paper)
    }

    private var card: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                brand
                    .frame(width: 340).frame(maxHeight: .infinity)
                    .overlay(alignment: .trailing) { Rectangle().fill(Brand.line).frame(width: 1) }
                login.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 351)
            privacy
            footer
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Brand.line))
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("GET STARTED / 01").font(Brand.jost(11)).tracking(1.6).foregroundStyle(Brand.gray)
            Text("ChatGPT 계정으로 시작하기").font(Brand.suit(26, .bold)).foregroundStyle(Brand.ink).padding(.top, 7)
        }
        .padding(.leading, 40).padding(.top, 30)
        .frame(maxWidth: .infinity, minHeight: 104, maxHeight: 104, alignment: .topLeading)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
    }

    private var brand: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit().frame(width: 78, height: 78)
            if let mark = Brand.wordmark {
                Image(nsImage: mark).resizable().scaledToFit().frame(height: 27).padding(.top, 33).accessibilityLabel("SILLOG")
            }
        }
    }

    private var login: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Mac에서 한 일을 기록하고 업무 단위로 정리해요.\n시작하려면 로그인해 주세요.")
                .font(Brand.suit(14)).foregroundStyle(Brand.gray).lineSpacing(6)
            Button { state.startCodexLogin() } label: {
                HStack(spacing: 8) {
                    Text("ChatGPT로 로그인")
                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .medium))
                }
                .font(Brand.suit(14, .medium)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 46)
                .background(RoundedRectangle(cornerRadius: 8).fill(Brand.ink))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 32)
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.circle").font(.system(size: 14)).foregroundStyle(Brand.gray)
                Text(CodexAuthError.deviceLoginNotEnabled.description).font(Brand.suit(13)).foregroundStyle(Brand.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).frame(minHeight: 46)
            .background(RoundedRectangle(cornerRadius: 8).fill(Brand.paper))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Brand.line))
            .padding(.top, 20)
        }
        .frame(width: 563)
    }

    private var privacy: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield").font(.system(size: 14)).foregroundStyle(Brand.ink).frame(width: 14)
            VStack(alignment: .leading, spacing: 13) {
                Text(PrivacyNote.title).font(Brand.suit(14, .medium)).foregroundStyle(Brand.ink)
                Text(PrivacyNote.body)                                   // Figma W1 문구 대신 사실대로 (PrivacyNote 참고)
                    .font(Brand.suit(12)).foregroundStyle(Brand.gray).lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 48).padding(.trailing, 48).padding(.top, 29).padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Brand.line).frame(height: 1) }
    }

    /// 예전 스타일 단계 표시: ① 로그인 —— ② 권한
    private var footer: some View {
        HStack(spacing: 0) {
            stepDot("1", on: true)
            Text("로그인").font(Brand.suit(13, .medium)).foregroundStyle(Brand.ink).padding(.leading, 11)
            Rectangle().fill(Brand.line).frame(width: 28, height: 1).padding(.horizontal, 12)
            stepDot("2", on: false)
            Text("권한").font(Brand.suit(13)).foregroundStyle(Brand.sub).padding(.leading, 11)
            Spacer()
        }
        .padding(.leading, 39)
        .frame(height: 63)
        .background(Brand.paper)
    }

    private func stepDot(_ number: String, on: Bool) -> some View {
        Text(number).font(Brand.suit(11, .medium)).foregroundStyle(on ? Color.white : Brand.sub)
            .frame(width: 18, height: 18)
            .background(Circle().fill(on ? Brand.ink : Color.clear))
            .overlay(Circle().strokeBorder(on ? Brand.ink : Brand.sub))
    }
}
