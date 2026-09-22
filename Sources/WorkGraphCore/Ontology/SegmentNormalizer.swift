import Foundation

/// LLM 이 나눈 구간을 그래프에 반영하기 전에 다듬는다. 목적은 업무가 잘게 쪼개지는 것을 막는 것.
/// 개입하는 대상은 "3분 미만인데 새 업무를 만들려는 구간"뿐이고, 긴 구간과 기존 업무 매칭은 그대로 둔다.
///   1. 짧은 구간끼리 비슷하면 묶는다. 묶음의 합이 3분을 넘으면 하나의 진짜 업무로 승격 (메신저 확인 4번 → 업무 1개)
///   2. 남은 짧은 구간은 비슷한 기존 업무가 있으면 그쪽으로 돌린다
///   3. 같은 업무 사이에 낀 짧은 끼어들기는 그 업무에 흡수한다
///   4. 어디에도 안 맞으면 공용 업무("자잘한 확인" / "짧은 딴짓")에 모은다 (배치에 구간이 하나뿐이면 그대로 둔다)
public struct SegmentNormalizer: Sendable {
    public static let catchAllTitle = "자잘한 확인"
    public static let driftTitle = "짧은 딴짓"
    static let stopwords: Set<String> = ["및", "확인", "작업", "관련", "정보", "the", "and", "of"]

    public var minNewTaskSeconds = 180
    public var reuseThreshold = 0.5

    public init() {}

    struct Features {
        var identity: String            // "id:<업무 키>" 또는 "title:<정규화한 제목>"
        var title: String
        var type: String
        var titleTokens: Set<String>
        var topics: Set<String>
        var resources: Set<String>
        var hosts: Set<String>
        var apps: Set<String>
    }

    public func normalize(_ patch: OntologyPatch, rows: [ActivityRow], openTasks: [TaskDigest]) -> OntologyPatch {
        let byNumber = Dictionary(rows.map { ($0.row, $0) }, uniquingKeysWith: { first, _ in first })
        let lastRow = rows.map(\.row).max() ?? 0
        var segments = patch.segments.sorted { $0.fromRow < $1.fromRow }
        let openIds = Set(openTasks.map(\.id))

        // 구간별 특징과 활동 시간
        var active: [Int] = [], features: [Features] = []
        for segment in segments {
            let low = max(1, segment.fromRow), high = min(lastRow, segment.toRow)
            let segmentRows = low <= high ? (low...high).compactMap { byNumber[$0] } : []
            active.append(segmentRows.reduce(0) { $0 + $1.dwell })
            var dwellByApp: [String: Int] = [:]
            for row in segmentRows { dwellByApp[row.appBundle, default: 0] += row.dwell }
            let dominant = dwellByApp.max { $0.value < $1.value }?.key
            features.append(Self.features(identity: Self.identity(of: segment.task, openIds: openIds), title: segment.task.title,
                                          type: segment.task.taskType, topics: segment.topics,
                                          resources: segmentRows.compactMap(\.uri), apps: dominant.map { [$0] } ?? []))
        }
        // 배치 전체가 구간 하나뿐이면 쪼개짐이 아니라 막 시작한 업무일 수 있다. 그때는 공용 업무로 보내지 않는다.
        let fragmented = active.filter { $0 > 0 }.count > 1
        func isShortNew(_ index: Int) -> Bool {
            active[index] > 0 && active[index] < minNewTaskSeconds && !features[index].identity.hasPrefix("id:")
        }

        // 1. 짧은 구간끼리 묶어서, 합이 기준을 넘는 묶음은 가장 긴 구간의 이름으로 승격
        var clusters: [[Int]] = []
        for index in segments.indices where isShortNew(index) {
            if let target = clusters.firstIndex(where: { Self.similarity(features[index], features[$0[0]]) >= reuseThreshold }) {
                clusters[target].append(index)
            } else {
                clusters.append([index])
            }
        }
        var promoted = Set<Int>()
        for cluster in clusters where cluster.reduce(0, { $0 + active[$1] }) >= minNewTaskSeconds {
            let lead = cluster.max { (active[$0], -$0) < (active[$1], -$1) } ?? cluster[0]
            for index in cluster {
                segments[index].task = segments[lead].task
                features[index].identity = features[lead].identity
                promoted.insert(index)
            }
        }

        // 기준이 되는 업무들: 열려 있는 업무 + 이번 배치의 긴 새 업무 + 승격된 묶음
        var known: [Features] = openTasks.map {
            Self.features(identity: "id:\($0.id)", title: $0.title, type: $0.taskType ?? TBox.fallbackTaskType,
                          topics: $0.topics, resources: $0.resourceKeys, apps: $0.apps)
        }
        var refs: [OntologyPatch.TaskRef] = openTasks.map {
            OntologyPatch.TaskRef(match: "existing", id: $0.id, title: $0.title, taskType: $0.taskType ?? TBox.fallbackTaskType)
        }
        for index in segments.indices where active[index] > 0 && (!isShortNew(index) || promoted.contains(index)) {
            guard !features[index].identity.hasPrefix("id:") else { continue }
            if let existing = known.firstIndex(where: { $0.identity == features[index].identity }) {
                known[existing].resources.formUnion(features[index].resources)
                known[existing].hosts.formUnion(features[index].hosts)
                known[existing].apps.formUnion(features[index].apps)
                known[existing].topics.formUnion(features[index].topics)
            } else {
                known.append(features[index]); refs.append(segments[index].task)
            }
        }

        // 2~4. 남은 짧은 구간 처리
        for index in segments.indices where isShortNew(index) && !promoted.contains(index) {
            let isDrift = segments[index].switchKind == "drift"
            let best = known.indices.max { Self.similarity(features[index], known[$0]) < Self.similarity(features[index], known[$1]) }
            if let best, Self.similarity(features[index], known[best]) >= reuseThreshold {
                segments[index].task = refs[best]
                features[index].identity = known[best].identity
            } else if !isDrift, index > 0, index + 1 < segments.count, active[index - 1] > 0,
                      features[index - 1].identity == features[index + 1].identity {
                segments[index].task = segments[index - 1].task
                features[index].identity = features[index - 1].identity
            } else if fragmented {
                let title = isDrift ? Self.driftTitle : Self.catchAllTitle
                segments[index].task = OntologyPatch.TaskRef(match: "new", id: nil, title: title, taskType: TBox.fallbackTaskType)
                segments[index].topics = []
                features[index].identity = "title:\(title)"
            }
        }

        // 같은 업무가 된 이웃 구간은 하나로 합친다 (행이 이어져 있을 때만)
        var merged: [OntologyPatch.Segment] = [], mergedActive: [Int] = [], mergedIdentity: [String] = []
        for index in segments.indices {
            if let last = merged.indices.last, mergedIdentity[last] == features[index].identity, active[index] > 0,
               merged[last].toRow + 1 == segments[index].fromRow {
                if active[index] > mergedActive[last] {                    // 요약은 더 긴 쪽 것을 쓴다
                    merged[last].summary = segments[index].summary
                    mergedActive[last] = active[index]
                }
                merged[last].toRow = segments[index].toRow
                for topic in segments[index].topics where !merged[last].topics.contains(topic) { merged[last].topics.append(topic) }
                if let more = segments[index].problems { merged[last].problems = (merged[last].problems ?? []) + more }
                if let more = segments[index].laterItems { merged[last].laterItems = (merged[last].laterItems ?? []) + more }
            } else {
                merged.append(segments[index]); mergedActive.append(active[index]); mergedIdentity.append(features[index].identity)
            }
        }
        return OntologyPatch(segments: merged)
    }

    // MARK: 비슷함 판단

    static func identity(of task: OntologyPatch.TaskRef, openIds: Set<String>) -> String {
        if task.match == "existing", let id = task.id, openIds.contains(id) { return "id:\(id)" }
        return "title:" + OntologyApplier.normalizeTitle(task.title).lowercased()
    }

    static func features(identity: String, title: String, type: String, topics: [String], resources: [String], apps: [String]) -> Features {
        let tokens = title.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init).filter { !stopwords.contains($0) }
        let hosts = resources.compactMap { URLComponents(string: $0)?.host }
        return Features(identity: identity, title: title, type: type, titleTokens: Set(tokens),
                        topics: Set(topics.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }),
                        resources: Set(resources), hosts: Set(hosts), apps: Set(apps))
    }

    /// 0 ~ 1.15. 업무 종류, 제목 단어, 주제, 본 자료가 겹치는 정도. 자료가 없는 구간(메신저 등)은 쓴 앱으로 본다.
    static func similarity(_ a: Features, _ b: Features) -> Double {
        var score = a.type == b.type ? 0.25 : 0
        score += 0.30 * jaccard(a.titleTokens, b.titleTokens)
        score += 0.25 * jaccard(a.topics, b.topics)
        if !a.resources.isEmpty {
            let overlap = Double(a.resources.intersection(b.resources).count) / Double(a.resources.count)
            score += 0.35 * overlap
            if overlap == 0, !a.hosts.isDisjoint(with: b.hosts) { score += 0.15 }
        } else if !a.apps.isDisjoint(with: b.apps) {
            score += 0.25
        }
        return score
    }

    static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(a.union(b).count)
    }
}
