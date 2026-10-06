import AppKit
import SwiftUI
import WorkGraphCore

private let logFill = Color(hex: 0xF6F5F4)   // 표 머리 줄, 선택 줄, 원문 상자 바탕

/// 원시 데이터(관측 행)와 LLM 이 받고 돌려준 것을 그대로 들여다보는 화면.
/// 수집 기록 표(행을 누르면 원문 시트), 정리 기록 표(행을 누르면 표 아래에 보낸 내용과 받은 응답).
/// 정리 기록에서는 위 표만 스크롤되고 아래 LLM 교환 카드는 제자리에 있다 (정리가 쌓여도 카드가 표 끝으로 밀려나지 않게).
struct ActivityLogView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedObservation: Int64?
    @State private var selectedBatch: Int64?
    @State private var section: Section
    @State private var loaded = false

    enum Section { case collected, batches }
    private let receivedFirst: Bool

    /// section·showReceived: 처음 보일 구역과 정리 카드의 보기 (스냅샷·테스트용, 앱에서는 기본값)
    init(section: Section = .collected, showReceived: Bool = false) {
        _section = State(initialValue: section)
        receivedFirst = showReceived
    }

    private struct ObservationRow: Identifiable {
        let id: Int64
        let observation: Observation
    }

    private struct BatchRow: Identifiable {
        let id: Int64
        let batch: BatchRecord
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    private static let today: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "오늘, M월 d일"
        return formatter
    }()

    @State private var observationRows: [ObservationRow] = []
    @State private var batchRows: [BatchRow] = []

    private func rebuildRows() {
        observationRows = state.recent.compactMap { observation in observation.id.map { ObservationRow(id: $0, observation: observation) } }
        batchRows = state.batches.compactMap { batch in batch.id.map { BatchRow(id: $0, batch: batch) } }
        if section == .batches, selectedBatch == nil { selectedBatch = batchRows.first?.id }
        loaded = true
    }

    var body: some View {
        VStack(spacing: 0) {
            BrandPageHeader(eyebrow: "Transparent by design", title: "활동 로그",
                            detail: loaded && (!observationRows.isEmpty || !batchRows.isEmpty)
                                ? "기록한 내용과 AI에 보낸 내용을 그대로 확인해요."
                                : "수집한 기록과, 정리할 때 AI에 보낸 내용과 받은 응답을 확인해요.")
            VStack(spacing: 0) {
                sectionTabs
                switch section {
                case .collected: collectedSection
                case .batches: batchSection
                }
            }
            .padding(.horizontal, 34)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.white)
        .onAppear(perform: rebuildRows)
        .onChange(of: state.recent) { _, _ in rebuildRows() }
        .onChange(of: state.batches) { _, _ in rebuildRows() }
        .onChange(of: section) { _, value in
            if value == .batches, selectedBatch == nil { selectedBatch = batchRows.first?.id }
        }
        .sheet(isPresented: Binding(get: { selectedObservation != nil }, set: { if !$0 { selectedObservation = nil } })) {
            if let row = observationRows.first(where: { $0.id == selectedObservation }) {
                ObservationDetail(observation: row.observation, onClose: { selectedObservation = nil })
            }
        }
    }

    // MARK: 구역 탭

    private var sectionTabs: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                sectionTab("수집 기록", .collected)
                sectionTab("정리 기록", .batches)
                Spacer()
            }
            Rectangle().fill(Brand.line).frame(height: 1)
        }
        .padding(.top, 6)
    }

    private func sectionTab(_ title: String, _ value: Section) -> some View {
        let on = section == value
        return Button { section = value } label: {
            Text(title)
                .font(Brand.suit(12, on ? .medium : .regular))
                .foregroundStyle(on ? Brand.ink : Brand.gray)
                .frame(height: 47)
                .overlay(alignment: .bottom) { if on { Rectangle().fill(Brand.ink).frame(height: 2).offset(y: 1) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 수집 기록

    private var collectedSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("최근 수집 기록").font(Brand.suit(14)).foregroundStyle(Brand.ink)
                Spacer()
                Text(Self.today.string(from: Date())).font(Brand.suit(10)).foregroundStyle(Brand.gray)
            }
            .padding(.top, 29).padding(.bottom, 11)

            if !loaded {
                stateView(icon: nil, title: nil, message: "기록을 불러오는 중이에요")
            } else if observationRows.isEmpty {
                stateView(icon: "list.bullet", title: "아직 수집한 기록이 없어요",
                          message: "앱을 오가며 작업하면 앱, 창 제목, 기록 종류가 시간 순서로 여기에 쌓여요.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        SwiftUI.Section {
                            ForEach(observationRows) { row in
                                let o = row.observation
                                LogRow(cells: [
                                    LogCell(Self.time.string(from: Date(timeIntervalSince1970: o.ts)), 130),
                                    LogCell(o.appName, 120),
                                    LogCell(o.windowTitle ?? ""),
                                    LogCell(o.url ?? o.docPath ?? "", color: Brand.gray),
                                    LogCell(Self.triggerName(o.trigger), 80),
                                    LogCell(o.textId == nil ? "" : "있음", 56, color: Brand.gray),
                                    LogCell(o.screenshotPath == nil ? "" : "있음", 56, color: Brand.gray),
                                    LogCell(o.batchId.map { "#\($0)" } ?? "대기", 64, color: o.batchId == nil ? Brand.ink : Brand.gray),
                                ], selected: selectedObservation == row.id) { selectedObservation = row.id }
                            }
                        } header: {
                            LogRow(cells: [
                                LogCell("시각", 130), LogCell("앱", 120), LogCell("창 제목"), LogCell("URL / 문서"),
                                LogCell("계기", 80), LogCell("텍스트", 56), LogCell("캡처", 56), LogCell("정리", 64),
                            ], header: true)
                        }
                    }
                }
            }

            HStack(spacing: 9) {
                Image(systemName: "info.circle").font(.system(size: 13)).foregroundStyle(Brand.gray)
                Text("비공개 창의 URL과 비밀번호 입력칸은 기록하지 않아요. 제외 앱은 이름과 시간만 남겨요.")
                    .font(Brand.suit(12)).foregroundStyle(Brand.gray)
                Spacer()
            }
            .padding(.vertical, 15)
        }
    }

    // MARK: 정리 기록

    private var batchSection: some View {
        Group {
            if !loaded {
                stateView(icon: nil, title: nil, message: "기록을 불러오는 중이에요")
            } else if batchRows.isEmpty {
                stateView(icon: "list.bullet", title: "아직 정리한 기록이 없어요",
                          message: "정리가 끝나면 AI에 보낸 내용과 받은 응답이 여기에 쌓여요.")
            } else {
                GeometryReader { geo in
                    let listMin = min(geo.size.height, max(150, geo.size.height * 0.36))     // 표는 머리 줄과 세 줄 이상
                    VStack(spacing: 16) {
                        ScrollView {
                            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                                SwiftUI.Section {
                                    ForEach(batchRows) { row in
                                        LogRow(cells: batchCells(row.batch), height: 40, selected: selectedBatch == row.id) { selectedBatch = row.id }
                                    }
                                } header: {
                                    LogRow(cells: batchCells(nil), header: true)
                                }
                            }
                        }
                        .frame(minHeight: listMin, maxHeight: .infinity)
                        if let row = batchRows.first(where: { $0.id == selectedBatch }) {
                            BatchDetail(batch: row.batch, maxHeight: max(200, geo.size.height - listMin - 16), showReceived: receivedFirst)
                                .layoutPriority(1)                                               // 카드가 먼저(내용 높이, 한도 안), 표는 남은 자리
                        } else {
                            Text("정리 기록을 선택하면 보낸 내용과 받은 응답이 보여요")
                                .font(Brand.suit(12)).foregroundStyle(Brand.gray).frame(height: 60)
                        }
                    }
                }
                .padding(.top, 16).padding(.bottom, 20)
            }
        }
    }

    private func batchCells(_ batch: BatchRecord?) -> [LogCell] {
        guard let batch else {
            return [LogCell("#", 54), LogCell("정리 시각", 160), LogCell("결과", 80), LogCell("기록 수", 90),
                    LogCell("모델", 180), LogCell("토큰", 160), LogCell("오류")]
        }
        let ok = batch.status == "ok"
        return [
            LogCell("\(batch.id ?? 0)", 54),
            LogCell(Self.time.string(from: Date(timeIntervalSince1970: batch.startedAt)), 160),
            LogCell(ok ? "성공" : "실패", 80, weight: ok ? .regular : .medium),
            LogCell("\(batch.rowCount)", 90),
            LogCell(batch.model ?? "", 180),
            LogCell("\(batch.promptTokens.formatted()) + \(batch.completionTokens.formatted())", 160, color: Brand.gray),
            LogCell(batch.error ?? ""),
        ]
    }

    // MARK: 빈 상태, 불러오는 중

    private func stateView(icon: String?, title: String?, message: String) -> some View {
        VStack(spacing: 0) {
            if let icon {
                Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(Brand.sub)
            } else {
                ProgressView().controlSize(.regular)
            }
            if let title {
                Text(title).font(Brand.suit(20, .bold)).foregroundStyle(Brand.ink).padding(.top, 16)
            }
            Text(message).font(Brand.suit(14)).foregroundStyle(Brand.gray).padding(.top, title == nil ? 14 : 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
    }

    static func triggerName(_ trigger: String) -> String {
        switch trigger {
        case "app_activate": return "앱 전환"
        case "window_change": return "창 변경"
        case "periodic": return "유지"
        case "demo": return "데모"
        default: return trigger
        }
    }
}

// MARK: 표 부품

private struct LogCell {
    let text: String
    var width: CGFloat?
    var color: Color = Brand.ink
    var weight: Brand.Weight = .regular

    init(_ text: String, _ width: CGFloat? = nil, color: Color = Brand.ink, weight: Brand.Weight = .regular) {
        self.text = text
        self.width = width
        self.color = color
        self.weight = weight
    }
}

/// 표 한 줄: 머리 줄은 옅은 바탕 11 회색, 본문 줄은 12 먹, 아래 구분선, 선택 줄은 옅은 바탕.
private struct LogRow: View {
    let cells: [LogCell]
    var header = false
    var height: CGFloat = 44
    var selected = false
    var onTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(cells.indices, id: \.self) { i in
                let cell = cells[i]
                Text(cell.text)
                    .font(Brand.suit(header ? 11 : 12, cell.weight))
                    .foregroundStyle(header ? Brand.gray : cell.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
                    .frame(minWidth: cell.width, maxWidth: cell.width ?? .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: header ? 36 : height)
        .background(header || selected ? logFill : Color.clear)
        .overlay(alignment: .bottom) { if !header { Rectangle().fill(Brand.line).frame(height: 1) } }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}

// MARK: 수집 기록 원문 시트

/// 관측 행 하나: 모든 필드, 화면 텍스트 전문, 스크린샷.
struct ObservationDetail: View {
    @EnvironmentObject private var state: AppState
    let observation: Observation
    var onClose: () -> Void = {}
    @State private var text: String?
    @State private var image: NSImage?
    @State private var imageLoading = false

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow("Collected record")
                    Text("수집 기록 원문").font(Brand.suit(22, .bold)).foregroundStyle(Brand.ink).padding(.top, 8)
                    Text("관측 행 #\(observation.id ?? 0)").font(Brand.suit(12)).foregroundStyle(Brand.gray).padding(.top, 10)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .regular)).foregroundStyle(Brand.tabText)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32).padding(.top, 26).padding(.bottom, 22)
            Rectangle().fill(Brand.line).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    field("시각", Self.time.string(from: Date(timeIntervalSince1970: observation.ts)))
                    field("계기", ActivityLogView.triggerName(observation.trigger), medium: true)
                    field("앱", "\(observation.appName)  (\(observation.appBundle))")
                    if let title = observation.windowTitle { field("창 제목", title) }
                    if let url = observation.url { field("URL", url) }
                    if let path = observation.docPath { field("문서", path) }
                    field("정리", observation.batchId.map { "배치 #\($0)" } ?? "아직 정리 안 됨")

                    Group {
                        if let text {
                            TextBlock(title: "화면 텍스트 (\(text.count.formatted())자)", text: text, height: 200)
                        } else {
                            Text("화면 텍스트 없음").font(Brand.suit(12)).foregroundStyle(Brand.gray)
                        }
                    }
                    .padding(.top, 16)

                    if let path = observation.screenshotPath {
                        HStack(spacing: 14) {
                            Text("스크린샷").font(Brand.suit(12)).foregroundStyle(Brand.gray)
                            Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                                .buttonStyle(.plain).font(Brand.suit(12, .medium)).foregroundStyle(Brand.ink)
                        }
                        .padding(.top, 16)
                        Group {
                            if let image {
                                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
                            } else if imageLoading {
                                ProgressView().controlSize(.small)
                                    .frame(maxWidth: .infinity).frame(height: 110)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(logFill))
                            } else {
                                Text("파일이 없어요 (보관 기간이 지나 지워졌을 수 있어요)").font(Brand.suit(12)).foregroundStyle(Brand.gray)
                            }
                        }
                        .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 32).padding(.vertical, 8).padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Rectangle().fill(Brand.line).frame(height: 1)
            HStack {
                Spacer()
                Button("닫기", action: onClose).buttonStyle(BrandButtonStyle(kind: .secondary)).keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 32).frame(height: 62).background(logFill)
        }
        .frame(width: 720, height: 600)
        .background(Color.white)
        .onChange(of: observation.id, initial: true) { _, _ in
            let started = Date()
            text = observation.textId.flatMap { state.observationText($0) }        // DB 읽기 1ms 미만: 바로, 깜빡임 없이
            Self.logIfSlow("관측 행 #\(observation.id ?? 0) 텍스트 읽기", since: started)
            image = nil
            guard let path = observation.screenshotPath else { imageLoading = false; return }
            imageLoading = true
            let id = observation.id
            Task.detached(priority: .userInitiated) {                              // JPEG 디코드는 메인 스레드 밖에서, 표시 크기로 축소
                let decodeStarted = Date()
                let thumbnail = Self.thumbnail(path: path, maxPixels: 1000)
                Self.logIfSlow("관측 행 #\(id ?? 0) 스크린샷 썸네일", since: decodeStarted)
                await MainActor.run {
                    guard id == observation.id else { return }
                    image = thumbnail
                    imageLoading = false
                }
            }
        }
    }

    /// 100ms 넘게 걸린 로딩만 app.log 에 남긴다 (느리다는 보고가 오면 원인을 바로 볼 수 있게).
    nonisolated static func logIfSlow(_ what: String, since started: Date) {
        let ms = Date().timeIntervalSince(started) * 1000
        if ms > 100 { AppLog.write("느림: \(what) \(Int(ms))ms") }
    }

    /// 원본을 통째로 디코드하지 않고 표시 크기의 썸네일만 만든다.
    nonisolated static func thumbnail(path: String, maxPixels: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                                        kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCache: false]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func field(_ name: String, _ value: String, medium: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(name).font(Brand.suit(12)).foregroundStyle(Brand.gray).frame(width: 120, alignment: .leading)
            Text(value).font(Brand.suit(12, medium ? .medium : .regular)).foregroundStyle(Brand.ink)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
    }
}

// MARK: 정리 기록 상세 (LLM 교환 판)

/// 배치 하나: LLM 이 받은 것, 돌려준 것, 반영한 것, 원본 응답. 큰 열은 선택했을 때만 읽는다.
/// 높이는 maxHeight 안에서 내용에 맞추고, 넘치면(펼친 시스템 프롬프트 등) 머리는 두고 아래만 카드 안에서 스크롤한다.
private struct BatchDetail: View {
    @EnvironmentObject private var state: AppState
    let batch: BatchRecord
    var maxHeight: CGFloat = .infinity
    @State private var full: BatchRecord?
    @State private var showReceived: Bool
    @State private var showSystem = false
    @State private var showRaw = false
    @State private var headerHeight: CGFloat = 120
    @State private var patchText: String?
    @State private var appliedText: String?

    init(batch: BatchRecord, maxHeight: CGFloat = .infinity, showReceived: Bool = false) {
        self.batch = batch
        self.maxHeight = maxHeight
        _showReceived = State(initialValue: showReceived)
    }

    /// 글 상자 높이: 접힌 상태에서 카드가 스크롤 없이 들어가게 (상자 제목·여백·펼침 줄 몫 92)
    private var boxHeight: CGFloat { min(300, max(120, maxHeight - headerHeight - 1 - 92)) }

    private struct HeaderHeight: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow("LLM exchange")
                    Text("정리 #\(batch.id ?? 0), \(batch.status == "ok" ? "성공" : "실패")")
                        .font(Brand.suit(16, .bold)).foregroundStyle(Brand.ink).padding(.top, 6)
                    Text("\(Self.time.string(from: Date(timeIntervalSince1970: batch.startedAt))), \(batch.model ?? "-"), 행 \(batch.rowCount)개, 토큰 \(batch.promptTokens.formatted()) + \(batch.completionTokens.formatted())")
                        .font(Brand.suit(12)).foregroundStyle(Brand.gray).padding(.top, 10)
                    if let error = batch.error { summaryLine("오류", error) }
                    if let stats = batch.stats { summaryLine("반영 결과", ApplyStats.summary(json: stats) ?? stats) }
                }
                Spacer(minLength: 16)
                viewToggle
            }
            .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 14)
            .background(GeometryReader { g in Color.clear.preference(key: HeaderHeight.self, value: g.size.height) })
            Rectangle().fill(Brand.line).frame(height: 1)

            ViewThatFits(in: .vertical) {
                content
                ScrollView { content }
            }
        }
        .frame(maxHeight: maxHeight)
        .onPreferenceChange(HeaderHeight.self) { if $0 > 0 { headerHeight = $0 } }
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Brand.line))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onChange(of: batch.id, initial: true) { _, _ in
            let started = Date()
            full = batch.id.flatMap { state.batchDetail($0) }
            patchText = full?.llmPatch.map(Self.pretty)
            appliedText = full?.appliedPatch.flatMap { $0 == full?.llmPatch ? nil : Self.pretty($0) }
            ObservationDetail.logIfSlow("정리 #\(batch.id ?? 0) 상세 읽기", since: started)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let full {
                if showReceived { received(full) } else { sent(full) }
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryLine(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(name).font(Brand.suit(12)).foregroundStyle(Brand.gray)
            Text(value).font(Brand.suit(12)).foregroundStyle(Brand.ink).textSelection(.enabled)
        }
        .padding(.top, 6)
    }

    /// 보낸 내용, 받은 응답 전환 (Figma 보기 전환)
    private var viewToggle: some View {
        HStack(spacing: 0) {
            toggleItem("보낸 내용", on: !showReceived) { showReceived = false }
            toggleItem("받은 응답", on: showReceived) { showReceived = true }
        }
        .padding(2)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Brand.line))
    }

    private func toggleItem(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Brand.suit(12, on ? .medium : .regular)).foregroundStyle(on ? Brand.ink : Brand.gray)
                .frame(width: 88, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(on ? logFill : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func sent(_ full: BatchRecord) -> some View {
        if let user = full.userPrompt {
            TextBlock(title: "LLM이 받은 것 (이 배치의 활동 행)", text: user, height: boxHeight)
            disclosure("시스템 프롬프트 (고정 지시문)", isOn: $showSystem) {
                ReadOnlyTextView(text: full.systemPrompt ?? OntologyPrompt.system).frame(height: 260)
                    .background(RoundedRectangle(cornerRadius: 6).fill(logFill))
            }
        } else {
            Text("이 배치는 프롬프트를 저장하기 전에 실행됐어요").font(Brand.suit(12)).foregroundStyle(Brand.gray)
        }
    }

    @ViewBuilder private func received(_ full: BatchRecord) -> some View {
        if full.llmPatch == nil, full.rawResponse == nil {
            Text("받은 응답이 없어요").font(Brand.suit(12)).foregroundStyle(Brand.gray)
        }
        // 돌려준 것과 반영한 것을 나란히 (Figma LG-W4). 반영한 것이 돌려준 것과 같으면 하나만
        if patchText != nil || appliedText != nil {
            HStack(alignment: .top, spacing: 16) {
                if let patchText { TextBlock(title: "LLM이 돌려준 것 (구조화 결과)", text: patchText, height: boxHeight, monospaced: true) }
                if let appliedText { TextBlock(title: "짧은 구간을 다듬은 뒤 반영한 것", text: appliedText, height: boxHeight, monospaced: true) }
            }
        }
        if let raw = full.rawResponse {
            disclosure("원본 응답 (\(raw.count.formatted())자)", isOn: $showRaw) {
                ReadOnlyTextView(text: raw, monospaced: true).frame(height: 260)
                    .background(RoundedRectangle(cornerRadius: 6).fill(logFill))
            }
        }
    }

    /// 한 줄 JSON 은 줄을 나눠 보여 준다 (좁은 상자에서도 읽히게, 상자 높이도 줄 수로 정해진다). JSON 이 아니면 그대로
    static func pretty(_ text: String) -> String {
        guard let data = text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data),
              let out = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let string = String(data: out, encoding: .utf8) else { return text }
        return string
    }

    /// 펼침 줄: 화살표와 Medium 12 제목, 펼치면 아래에 상자
    private func disclosure<Content: View>(_ title: String, isOn: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { isOn.wrappedValue.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: isOn.wrappedValue ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .medium))
                    Text(title).font(Brand.suit(12, .medium))
                }
                .foregroundStyle(Brand.ink).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOn.wrappedValue { content() }
        }
    }
}
