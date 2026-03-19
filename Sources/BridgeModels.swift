import Foundation

enum BridgeMethod: String, Codable {
    case getState
    case createWorkspace
    case selectWorkspace
    case closeWorkspace
    case createTab
    case closeTab
    case selectTab
    case splitTab
    case toggleSidebar
    case selectNextTab
    case selectPreviousTab
    case selectNextPane
    case selectPreviousPane
}

struct BridgeRequest: Codable {
    let id: String?
    let method: BridgeMethod
    let params: Data?

    init(id: String?, method: BridgeMethod, params: Data? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case method
        case params
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        method = try container.decode(BridgeMethod.self, forKey: .method)

        if container.contains(.params) {
            let nested = try container.superDecoder(forKey: .params)
            let any = try JSONAnyCodable(from: nested)
            params = try JSONEncoder().encode(any)
        } else {
            params = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(method, forKey: .method)

        if let params {
            let object = try JSONDecoder().decode(JSONAnyCodable.self, from: params)
            try container.encode(object, forKey: .params)
        }
    }
}

struct BridgeResponse: Codable {
    let id: String?
    let ok: Bool
    let state: BridgeAppState
    let error: String?
}

enum BridgeEventName: String, Codable {
    case stateChanged
}

struct BridgeEventPayload: Codable {
    let event: BridgeEventName
    let state: BridgeAppState
}

struct BridgeAppState: Codable {
    let windowId: String?
    let sidebarVisible: Bool
    let selectedWorkspaceId: String?
    let workspaces: [BridgeWorkspaceState]

    @MainActor
    static func from(tabManager: TabManager?) -> BridgeAppState {
        BridgeAppState(
            windowId: tabManager?.window?.windowNumber.description,
            sidebarVisible: tabManager?.isSidebarVisible ?? true,
            selectedWorkspaceId: tabManager?.selectedWorkspaceId?.uuidString,
            workspaces: tabManager?.workspaces.map(BridgeWorkspaceState.init(workspace:)) ?? []
        )
    }
}

final class BridgeWorkspaceState: Codable {
    let id: String
    let directory: String
    let displayName: String
    let selectedTabId: String?
    let splitLayout: BridgeSplitNodeState?
    let tabs: [BridgeTabState]

    @MainActor
    init(workspace: Workspace) {
        id = workspace.id.uuidString
        directory = workspace.directory
        displayName = workspace.displayName
        selectedTabId = workspace.selectedTabId?.uuidString
        splitLayout = workspace.splitLayout.map(BridgeSplitNodeState.init(node:))
        tabs = workspace.tabs.map(BridgeTabState.init(tab:))
    }
}

final class BridgeTabState: Codable {
    let id: String
    let title: String
    let currentDirectory: String?
    let initialWorkingDirectory: String?

    @MainActor
    init(tab: Tab) {
        id = tab.id.uuidString
        title = tab.title
        currentDirectory = tab.currentDirectory
        initialWorkingDirectory = tab.initialWorkingDirectory
    }
}

enum BridgeSplitDirection: String, Codable {
    case horizontal
    case vertical

    var splitDirection: SplitNode.SplitDirection {
        switch self {
        case .horizontal: return .horizontal
        case .vertical: return .vertical
        }
    }
}

final class BridgeSplitNodeState: Codable {
    let type: String
    let id: String
    let tabId: String?
    let direction: BridgeSplitDirection?
    let ratio: Double?
    let first: BridgeSplitNodeState?
    let second: BridgeSplitNodeState?

    @MainActor
    init(node: SplitNode) {
        id = node.id.uuidString

        switch node.content {
        case .tab(let tabIdValue):
            type = "tab"
            tabId = tabIdValue.uuidString
            direction = nil
            ratio = nil
            first = nil
            second = nil

        case .split(let splitDirection, let firstNode, let secondNode, let splitRatio):
            type = "split"
            tabId = nil
            direction = splitDirection == .horizontal ? .horizontal : .vertical
            ratio = splitRatio
            first = BridgeSplitNodeState(node: firstNode)
            second = BridgeSplitNodeState(node: secondNode)
        }
    }
}

struct BridgeCreateWorkspaceParams: Codable {
    let directory: String
}

struct BridgeWorkspaceTargetParams: Codable {
    let workspaceId: String
}

struct BridgeOptionalWorkspaceTargetParams: Codable {
    let workspaceId: String?
}

struct BridgeTabTargetParams: Codable {
    let tabId: String
}

struct BridgeSplitTabParams: Codable {
    let tabId: String?
    let direction: BridgeSplitDirection
}

private struct JSONAnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([JSONAnyCodable].self) {
            value = array.map(\.value)
        } else if let object = try? container.decode([String: JSONAnyCodable].self) {
            value = object.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map(JSONAnyCodable.init))
        case let object as [String: Any]:
            try container.encode(object.mapValues(JSONAnyCodable.init))
        default:
            let context = EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported JSON value")
            throw EncodingError.invalidValue(value, context)
        }
    }
}
