import AppKit
import SwiftUI
import WorkGraphCore

/// 원시 데이터(관측 행)와 LLM 이 받고 돌려준 것을 그대로 들여다보는 화면.
/// 왼쪽 위: 관측 행, 왼쪽 아래: 정리 기록, 오른쪽: 선택한 것의 상세.
struct ActivityLogView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedObservation: Int64?
    @State private var selectedBatch: Int64?
    @State private var focus: Focus = .none

    private enum Focus { case none, observation, batch }

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

    @State private var observationRows: [ObservationRow] = []
    @State private var batchRows: [BatchRow] = []

    private func rebuildRows() {
        observationRows = state.recent.compactMap { observation in observation.id.map { ObservationRow(id: $0, observation: observation) } }
        batchRows = state.batches.compactMap { batch in batch.id.map { BatchRow(id: $0, batch: batch) } }
    }

    var body: some View {
        HSplitView {
            VSplitView {
                observationTable.frame(minHeight: 200)
                VStack(alignment: .leading, spacing: 0) {
                    Text("정리 기록").font(.headline).padding(.horizontal, 12).padding(.vertical, 8)
                    batchTable
                }
                .frame(minHeight: 160)
            }
            .frame(minWidth: 560)

            inspector
                .frame(minWidth: 340, idealWidth: 460)
        }
        .onAppear(perform: rebuildRows)
        .onChange(of: state.recent) { _, _ in rebuildRows() }
        .onChange(of: state.batches) { _, _ in rebuildRows() }
    }

    // MARK: 표

    private var observationTable: some View {
        Table(observationRows, selection: $selectedObservation) {
            TableColumn("시각") { Text(Self.time.string(from: Date(timeIntervalSince1970: $0.observation.ts))).monospacedDigit() }.width(118)
            TableColumn("앱") { Text($0.observation.appName) }.width(min: 90, ideal: 130)
            TableColumn("창 제목") { Text($0.observation.windowTitle ?? "").lineLimit(1) }
            TableColumn("URL / 문서") { Text($0.observation.url ?? $0.observation.docPath ?? "").lineLimit(1).foregroundStyle(.secondary) }
            TableColumn("계기") { Text(Self.triggerName($0.observation.trigger)) }.width(70)
            TableColumn("텍스트") { Text($0.observation.textId == nil ? "" : "있음").foregroundStyle(.secondary) }.width(44)
            TableColumn("캡처") { Text($0.observation.screenshotPath == nil ? "" : "있음").foregroundStyle(.secondary) }.width(40)
            TableColumn("정리") { Text($0.observation.batchId == nil ? "대기" : "#\($0.observation.batchId!)").foregroundStyle($0.observation.batchId == nil ? .orange : .secondary) }.width(50)
        }
        .onChange(of: selectedObservation) { _, value in if value != nil { focus = .observation } }
    }

    private var batchTable: some View {
        Table(batchRows, selection: $selectedBatch) {
            TableColumn("#") { Text("\($0.id)").monospacedDigit() }.width(40)
            TableColumn("시각") { Text(Self.time.string(from: Date(timeIntervalSince1970: $0.batch.startedAt))).monospacedDigit() }.width(118)
            TableColumn("결과") { Text($0.batch.status == "ok" ? "성공" : "실패").foregroundStyle($0.batch.status == "ok" ? .green : .red) }.width(44)
            TableColumn("행") { Text("\($0.batch.rowCount)").monospacedDigit() }.width(40)
            TableColumn("모델") { Text($0.batch.model ?? "") }.width(min: 100, ideal: 150)
            TableColumn("토큰") { Text("\($0.batch.promptTokens) + \($0.batch.completionTokens)").monospacedDigit() }.width(100)
            TableColumn("오류") { Text($0.batch.error ?? "").lineLimit(2).foregroundStyle(.secondary) }
        }
        .onChange(of: selectedBatch) { _, value in if value != nil { focus = .batch } }
    }

    // MARK: 상세

    @ViewBuilder private var inspector: some View {
        switch focus {
        case .observation:
            if let row = observationRows.first(where: { $0.id == selectedObservation }) { ObservationDetail(observation: row.observation) }
            else { placeholder }
        case .batch:
            if let row = batchRows.first(where: { $0.id == selectedBatch }) { BatchDetail(batch: row.batch) }
            else { placeholder }
        case .none:
            placeholder
        }
    }

    private var placeholder: some View {
        Text("행이나 정리 기록을 선택하면 원문이 보입니다")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// 관측 행 하나: 모든 필드, 화면 텍스트 전문, 스크린샷.
struct ObservationDetail: View {
    @EnvironmentObject private var state: AppState
    let observation: Observation
    @State private var text: String?
    @State private var image: NSImage?
    @State private var imageLoading = false

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("관측 행 #\(observation.id ?? 0)").font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    field("시각", Self.time.string(from: Date(timeIntervalSince1970: observation.ts)))
                    field("계기", ActivityLogView.triggerName(observation.trigger))
                    field("앱", "\(observation.appName)  (\(observation.appBundle))")
                    if let title = observation.windowTitle { field("창 제목", title) }
                    if let url = observation.url { field("URL", url) }
                    if let path = observation.docPath { field("문서", path) }
                    field("정리", observation.batchId.map { "배치 #\($0)" } ?? "아직 정리 안 됨")
                }
                if let text {
                    TextBlock(title: "화면 텍스트 (\(text.count)자)", text: text, height: 320)
                } else {
                    Text("화면 텍스트 없음").font(.subheadline).foregroundStyle(.secondary)
                }
                if let path = observation.screenshotPath {
                    HStack {
                        Text("스크린샷").font(.subheadline).foregroundStyle(.secondary)
                        Button("Finder 에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }.buttonStyle(.link)
                    }
                    if let image {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    } else if imageLoading {
                        Color.clear.frame(height: 120)
                    } else {
                        Text("파일이 없음 (보관 기간이 지나 지워졌을 수 있음)").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    private func field(_ name: String, _ value: String) -> some View {
        GridRow {
            Text(name).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 배치 하나: LLM 이 받은 것, 돌려준 것, 반영한 것, 원본 응답. 큰 열은 선택했을 때만 읽는다.
private struct BatchDetail: View {
    @EnvironmentObject private var state: AppState
    let batch: BatchRecord
    @State private var full: BatchRecord?
    @State private var showSystem = false
    @State private var showRaw = false

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("정리 #\(batch.id ?? 0)  \(batch.status == "ok" ? "성공" : "실패")").font(.headline)
                Text("\(Self.time.string(from: Date(timeIntervalSince1970: batch.startedAt)))  ·  \(batch.model ?? "-")  ·  행 \(batch.rowCount)개  ·  토큰 \(batch.promptTokens) + \(batch.completionTokens)")
                    .font(.callout).foregroundStyle(.secondary)
                if let error = batch.error { TextBlock(title: "오류", text: error, height: 120) }
                if let stats = batch.stats { TextBlock(title: "반영 결과", text: stats, height: 80) }

                if let full {
                    if let user = full.userPrompt {
                        TextBlock(title: "LLM 이 받은 것 (이 배치의 활동 행)", text: user, height: 300)
                        DisclosureGroup("시스템 프롬프트 (고정 지시문)", isExpanded: $showSystem) {
                            ReadOnlyTextView(text: full.systemPrompt ?? OntologyPrompt.system).frame(height: 260)
                                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                        }
                    } else {
                        Text("이 배치는 프롬프트를 저장하기 전에 실행됐습니다").font(.callout).foregroundStyle(.secondary)
                    }
                    if let patch = full.llmPatch { TextBlock(title: "LLM 이 돌려준 것 (구조화 결과)", text: patch, height: 300) }
                    if let applied = full.appliedPatch, applied != full.llmPatch { TextBlock(title: "짧은 구간을 다듬은 뒤 반영한 것", text: applied, height: 300) }
                    if let raw = full.rawResponse {
                        DisclosureGroup("원본 응답 (\(raw.count)자)", isExpanded: $showRaw) {
                            ReadOnlyTextView(text: raw).frame(height: 260)
                                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: batch.id, initial: true) { _, _ in
            let started = Date()
            full = batch.id.flatMap { state.batchDetail($0) }
            ObservationDetail.logIfSlow("정리 #\(batch.id ?? 0) 상세 읽기", since: started)
        }
    }
}
