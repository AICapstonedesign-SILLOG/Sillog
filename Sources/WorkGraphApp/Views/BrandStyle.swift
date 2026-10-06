import SwiftUI
import AppKit

/// Figma 화면 모음(358:1535) 공용 값. 모든 탭이 이 파일의 색, 글꼴, 유리 표면을 쓴다.
enum Brand {
    static let ink = Color(hex: 0x24150F)          // 주색: 제목, 강조 버튼
    static let text = Color(hex: 0x141210)         // 먹: 본문, 입력값
    static let gray = Color(hex: 0x736D68)         // 회색: 보조 글씨, 눈썹 글씨
    static let tabText = Color(hex: 0x4A4541)      // 선택 안 된 탭, 보조 버튼 글씨
    static let line = Color(hex: 0xE5E2DF)         // 구분선, 입력칸 테두리
    static let sky = Color(hex: 0xB4D0E4)          // 보조색 하늘: 배지 테두리, 세션 고리
    static let sub = Color(hex: 0xAAAAAA)          // 자리표시 글씨
    static let hairline = Color(red: 20 / 255, green: 18 / 255, blue: 16 / 255).opacity(0.08)

    enum Weight: String { case regular = "Regular", medium = "Medium", semibold = "SemiBold", bold = "Bold" }
    /// 한글 본문 글꼴 SUIT (없으면 시스템 글꼴로 대체된다)
    static func suit(_ size: CGFloat, _ weight: Weight = .regular) -> Font { .custom("SUIT-\(weight.rawValue)", size: size) }
    /// 영문 눈썹 글씨와 숫자 Jost
    static func jost(_ size: CGFloat) -> Font { .custom("Jost", size: size) }

    static let wordmark: NSImage? = {
        let url = Bundle.main.url(forResource: "wordmark", withExtension: "png", subdirectory: "Brand")
            ?? Bundle.module.url(forResource: "wordmark", withExtension: "png", subdirectory: "Brand")
        return url.flatMap(NSImage.init(contentsOf:))
    }()
}

/// 창 뒤(바탕화면)를 흐리게 비추는 유리 바탕. Finder 사이드바와 같은 방식이라, 마누스 시제품처럼
/// 탭 막대와 사이드바 뒤로 바탕화면이 비친다. 그 위에 흰색 30%를 얹어 쓴다(머티리얼이 이미 흰빛을 섞으므로 72%를 얹으면 거의 비치지 않는다).
struct BehindWindowGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// 영문 눈썹 글씨: CONNECTED CONTEXT, NODE DETAIL 같은 작은 제목
struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(Brand.jost(12)).tracking(1.44).foregroundStyle(Brand.gray)
    }
}

/// 탭 첫머리: 눈썹 글씨, 그 아래 한 줄에 제목(22)과 설명(12), 오른쪽 추가 요소. 아래 구분선.
struct BrandPageHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    var detail: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(eyebrow)
                HStack(alignment: .firstTextBaseline, spacing: 14) {           // 제목과 설명은 한 줄
                    Text(title).font(Brand.suit(22, .semibold)).tracking(-0.66).foregroundStyle(Brand.ink)
                    if let detail { Text(detail).font(Brand.suit(12)).foregroundStyle(Brand.gray).lineLimit(1) }
                }
            }
            Spacer(minLength: 16)
            trailing()
        }
        .padding(.horizontal, 34)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
    }
}

extension BrandPageHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String, detail: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, detail: detail, trailing: { EmptyView() })
    }
}

/// 상세 판 배지: 하늘색 옅은 바탕과 테두리
struct BrandBadge: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Brand.suit(10, .medium)).foregroundStyle(Brand.ink)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Brand.sky.opacity(0.13)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Brand.sky))
    }
}

/// 버튼: primary는 주색 바탕에 흰 글씨, secondary는 흰 바탕에 테두리
struct BrandButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    var kind: Kind = .secondary
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Brand.suit(11, .medium))
            .foregroundStyle(kind == .primary ? Color.white : Brand.tabText)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 6).fill(kind == .primary ? Brand.ink : .white))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(kind == .primary ? Brand.ink : Brand.line))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

extension View {
    /// 유리 판: 창 뒤 바탕화면을 흐리게 비추고 흰색 30%와 얇은 테두리를 얹는다 (사이드바, 떠 있는 판)
    func glassPanel(cornerRadius: CGFloat = 10) -> some View {
        background(RoundedRectangle(cornerRadius: cornerRadius).fill(.white.opacity(0.3)))
            .background(BehindWindowGlass().clipShape(RoundedRectangle(cornerRadius: cornerRadius)))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Brand.hairline))
    }

    /// 유리 알약: 선택한 탭과 선택한 항목 (흰색 78%, 얇은 테두리, 옅은 그림자)
    @ViewBuilder func glassPill(_ on: Bool, cornerRadius: CGFloat = 8) -> some View {
        if on {
            background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.white.opacity(0.78))
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.black.opacity(0.06)))
                    .shadow(color: .black.opacity(0.04), radius: 6, y: 4)
                    .shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
            )
        } else {
            self
        }
    }

    /// 입력칸과 선택 상자 바탕: 흰 바탕, 1px 테두리, 모서리 5
    func brandField(height: CGFloat = 35) -> some View {
        frame(height: height)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 5).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Brand.line))
    }
}
