import SwiftUI
import AppKit
import WorkGraphCore

/// Figma 화면 모음(358:1535) 공용 값. 모든 탭이 이 파일의 색, 글꼴, 유리 표면을 쓴다.
enum Brand {
    static let ink = Color(hex: 0x24150F)          // 주색: 제목, 강조 버튼
    static let text = Color(hex: 0x141210)         // 먹: 본문, 입력값
    static let gray = Color(hex: 0x736D68)         // 회색: 보조 글씨, 눈썹 글씨
    static let tabText = Color(hex: 0x4A4541)      // 선택 안 된 탭, 보조 버튼 글씨
    static let line = Color(hex: 0xE5E2DF)         // 구분선, 입력칸 테두리
    static let sky = Color(hex: 0xB4D0E4)          // 보조색 하늘: 배지 테두리, 세션 고리
    static let sub = Color(hex: 0xAAAAAA)          // 자리표시 글씨
    /// 유리 바탕(창 뒤 바탕화면 흐림) 위에 얹는 흰색 양. 낮을수록 바탕화면이 더 비친다
    static let glassTint = 0.08
    /// 유리: 창 뒤를 흐리는 반경과 그 위 흰 막. 흐림이 클수록 뒤 글씨가 뭉개지고, 흰 막이 낮을수록 뒤 색이 진하게 비친다
    /// (흰 막을 0.5 아래로 내리면 어두운 창이 뒤에 올 때 바탕이 짙은 회색이 돼 글씨가 탁해진다)
    static let glassBlur = 30
    static let glassWhite = 0.6
    static let hairline = Color(red: 20 / 255, green: 18 / 255, blue: 16 / 255).opacity(0.08)

    enum Weight: String { case regular = "Regular", medium = "Medium", semibold = "SemiBold", bold = "Bold" }
    /// 한글 본문 글꼴 SUIT (없으면 시스템 글꼴로 대체된다)
    static func suit(_ size: CGFloat, _ weight: Weight = .regular) -> Font { .custom("SUIT-\(weight.rawValue)", size: size) }
    static let paper = Color(hex: 0xF6F5F4)        // 칩과 오류 상자 바탕, 예전 스타일 창 바탕 (OUT-W1)

    /// 영문 눈썹 글씨와 숫자 Jost 400. 앱에 넣은 Jost* 판에서 400 의 이름은 "Jost-Book" (FontRegistryTests 가 확인)
    static func jost(_ size: CGFloat) -> Font { .custom("Jost-Book", size: size) }
    /// 큰 숫자 Jost 200 (Figma 의 ExtraLight, 앱에 넣은 판의 이름은 "Jost-Thin")
    static func jostLight(_ size: CGFloat) -> Font { .custom("Jost-Thin", size: size) }

    static let wordmark: NSImage? = {
        let url = BundledResources.url(forResource: "wordmark", withExtension: "png", subdirectory: "Brand", main: .main) { .module }
        return url.flatMap(NSImage.init(contentsOf:))
    }()
}

/// 앱에 넣은 SUIT·Jost 글꼴(Resources/Brand/Fonts)을 이 프로세스에만 등록한다. 못 찾으면 시스템 글꼴로 그려진다.
enum BrandFonts {
    @discardableResult
    static func register() -> [String] {
        // .app 은 Contents/Resources/Brand 만 본다 (.app 에서 Bundle.module 을 부르면 리소스 번들이 없어 앱이 끝난다)
        let directory = BundledResources.url(forResource: "Fonts", withExtension: nil, subdirectory: "Brand", main: .main) { .module }
        return directory.map { FontRegistry.register(directory: $0) } ?? []
    }
}

/// macOS 기본 유리 (Finder 사이드바 재질). 떠 있는 판과, 창 뒤 흐림을 쓸 수 없을 때의 창 바탕에 쓴다.
/// 창 바탕 유리는 MainWindow 의 WindowGlassBackground 가 맡는다 (창 뒤 흐림 Brand.glassBlur + 흰 막 Brand.glassWhite)
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
    /// 유리 막대 바탕 (탭 막대, 사이드바): 창 바탕의 유리가 그대로 보이게 하고 흰색만 조금(Brand.glassTint) 얹는다.
    /// 여기서 유리를 한 겹 더 깔면 두 겹이 돼 뒤가 비치지 않는다
    func brandGlass() -> some View {
        background(.white.opacity(Brand.glassTint))
    }

    /// 유리 판: 내용 위에 떠 있는 판 (자기 유리를 깔고 흰색 조금과 얇은 테두리를 얹는다). 창 가장자리 사이드바는 brandGlass 를 쓴다
    func glassPanel(cornerRadius: CGFloat = 10) -> some View {
        background(RoundedRectangle(cornerRadius: cornerRadius).fill(.white.opacity(Brand.glassTint)))
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
