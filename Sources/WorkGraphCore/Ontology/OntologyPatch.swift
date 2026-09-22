import Foundation
import CryptoKit

/// LLM이 함수 호출 `record_activity` 로 돌려주는 결과.
/// 작은 모델도 쓸 수 있게 디코딩은 관대하게 한다 (숫자가 문자열로 와도, 선택 필드가 빠져도 받는다).
public struct OntologyPatch: Codable, Equatable, Sendable {
    public var segments: [Segment]

    public init(segments: [Segment]) { self.segments = segments }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        segments = (try? c.decodeIfPresent([Segment].self, forKey: .segments)) ?? []
    }

    public struct Segment: Codable, Equatable, Sendable {
        public var fromRow: Int
        public var toRow: Int
        public var task: TaskRef
        public var summary: String
        public var topics: [String]
        public var problems: [ProblemRef]?
        public var laterItems: [LaterRef]?
        /// planned | drift | blocked
        public var switchKind: String?

        enum CodingKeys: String, CodingKey {
            case fromRow = "from_row", toRow = "to_row", task, summary, topics, problems
            case laterItems = "later_items", switchKind = "switch_kind"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            fromRow = try c.lenientInt(.fromRow) ?? 1
            toRow = try c.lenientInt(.toRow) ?? fromRow
            task = (try? c.decodeIfPresent(TaskRef.self, forKey: .task)) ?? TaskRef(match: "new", id: nil, title: "", taskType: TBox.fallbackTaskType)
            summary = (try? c.decodeIfPresent(String.self, forKey: .summary)) ?? ""
            topics = (try? c.decodeIfPresent([String].self, forKey: .topics)) ?? []
            problems = try? c.decodeIfPresent([ProblemRef].self, forKey: .problems)
            laterItems = try? c.decodeIfPresent([LaterRef].self, forKey: .laterItems)
            switchKind = try? c.decodeIfPresent(String.self, forKey: .switchKind)
        }
    }

    public struct TaskRef: Codable, Equatable, Sendable {
        /// existing | new
        public var match: String
        public var id: String?
        public var title: String
        public var taskType: String

        enum CodingKeys: String, CodingKey { case match, id, title, taskType = "task_type" }

        public init(match: String, id: String?, title: String, taskType: String) {
            self.match = match; self.id = id; self.title = title; self.taskType = taskType
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            match = (try? c.decodeIfPresent(String.self, forKey: .match)) ?? "new"
            id = try? c.decodeIfPresent(String.self, forKey: .id)
            title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
            taskType = (try? c.decodeIfPresent(String.self, forKey: .taskType)) ?? TBox.fallbackTaskType
        }
    }

    public struct ProblemRef: Codable, Equatable, Sendable {
        public var row: Int
        public var kind: String
        public var message: String
        public var resolvedByRow: Int?

        enum CodingKeys: String, CodingKey { case row, kind, message, resolvedByRow = "resolved_by_row" }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            row = try c.lenientInt(.row) ?? 0
            kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "error"
            message = (try? c.decodeIfPresent(String.self, forKey: .message)) ?? ""
            resolvedByRow = try c.lenientInt(.resolvedByRow)
        }
    }

    public struct LaterRef: Codable, Equatable, Sendable {
        public var row: Int
        public var text: String

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            row = try c.lenientInt(.row) ?? 0
            text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        }
    }
}

extension OntologyPatch {
    /// 사람이 읽는 용도의 JSON (들여쓰기, 키 정렬, 한글 그대로).
    public var prettyJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// 작은 모델이 자주 내는 두 가지 흔들림을 바로잡고 디코딩한다.
    /// 1) `segments` 없이 세그먼트 하나(또는 배열)를 최상위에 둔 경우
    /// 2) 중첩 값을 JSON 문자열로 한 번 더 감싼 경우 ("task": "{...}", "topics": "[...]")
    public static func decodeLenient(from data: Data) -> OntologyPatch? {
        guard let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        var root = unwrapStrings(parsed)
        if let list = root as? [Any] {
            root = ["segments": list]
        } else if let dict = root as? [String: Any], dict["segments"] == nil, dict["from_row"] != nil || dict["task"] != nil {
            root = ["segments": [dict]]
        } else if let dict = root as? [String: Any], let single = dict["segments"] as? [String: Any] {
            root = ["segments": [single]]
        }
        guard JSONSerialization.isValidJSONObject(root),
              let normalized = try? JSONSerialization.data(withJSONObject: root) else { return nil }
        return try? JSONDecoder().decode(OntologyPatch.self, from: normalized)
    }

    private static func unwrapStrings(_ value: Any) -> Any {
        if let dict = value as? [String: Any] { return dict.mapValues(unwrapStrings) }
        if let list = value as? [Any] { return list.map(unwrapStrings) }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let first = trimmed.first, first == "{" || first == "[", let data = trimmed.data(using: .utf8),
               let inner = try? JSONSerialization.jsonObject(with: data) {
                return unwrapStrings(inner)
            }
        }
        return value
    }
}

extension KeyedDecodingContainer {
    /// 3, 3.0, "3" 모두 3 으로 읽는다.
    func lenientInt(_ key: Key) throws -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Int(value.trimmingCharacters(in: .whitespaces)) }
        return nil
    }
}

enum StableHash {
    /// 키로 쓰는 짧은 결정적 해시 (SHA256 앞 8자리).
    static func short(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}

public enum OntologySchema {
    public static let functionName = "record_activity"

    public static var tool: ToolSpec {
        let row: JSONValue = .object(["type": "integer", "description": "ROWS의 행 번호"])
        let segment: JSONValue = .object([
            "type": "object",
            "properties": .object([
                "from_row": row, "to_row": row,
                "task": .object([
                    "type": "object",
                    "properties": .object([
                        "match": .object(["type": "string", "enum": .array(["existing", "new"])]),
                        "id": .object(["type": "string", "description": "match=existing 일 때 OPEN_TASKS 의 id"]),
                        "title": .object(["type": "string", "description": "짧고 구체적인 한국어 업무 제목"]),
                        "task_type": .object(["type": "string", "enum": .array(TBox.leafTaskTypes.map { .string($0) })]),
                    ]),
                    "required": .array(["match", "title", "task_type"]),
                ]),
                "summary": .object(["type": "string", "description": "이 구간에서 한 일, 한국어 한 문장"]),
                "topics": .object(["type": "array", "items": .object(["type": "string"]), "description": "주제 태그 1~4개"]),
                "problems": .object(["type": "array", "items": .object([
                    "type": "object",
                    "properties": .object([
                        "row": row,
                        "kind": .object(["type": "string", "description": "build, runtime, network, config 등"]),
                        "message": .object(["type": "string"]),
                        "resolved_by_row": row,
                    ]),
                    "required": .array(["row", "kind", "message"]),
                ])]),
                "later_items": .object(["type": "array", "items": .object([
                    "type": "object",
                    "properties": .object(["row": row, "text": .object(["type": "string"])]),
                    "required": .array(["row", "text"]),
                ])]),
                "switch_kind": .object(["type": "string", "enum": .array(["planned", "drift", "blocked"])]),
            ]),
            "required": .array(["from_row", "to_row", "task", "summary", "topics"]),
        ])
        return ToolSpec(name: functionName,
                        description: "Record how the activity rows split into work segments and what each segment is about.",
                        parameters: .object([
                            "type": "object",
                            "properties": .object(["segments": .object(["type": "array", "items": segment])]),
                            "required": .array(["segments"]),
                        ]))
    }
}
