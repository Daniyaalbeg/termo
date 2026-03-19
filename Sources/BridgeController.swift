import Combine
import Foundation

@MainActor
final class BridgeController {
    static let shared = BridgeController()

    private var tabManagerSubs: [ObjectIdentifier: AnyCancellable] = [:]
    private var listeners: [UUID: BridgeListener] = [:]

    private init() {}

    func register(tabManager: TabManager) {
        let key = ObjectIdentifier(tabManager)
        guard tabManagerSubs[key] == nil else { return }

        tabManagerSubs[key] = tabManager.objectWillChange.sink { [weak self, weak tabManager] _ in
            guard let self, let tabManager else { return }
            DispatchQueue.main.async {
                Task { @MainActor in
                    self.broadcastState(for: tabManager)
                }
            }
        }

        broadcastState(for: tabManager)
    }

    func unregister(tabManager: TabManager) {
        let key = ObjectIdentifier(tabManager)
        tabManagerSubs.removeValue(forKey: key)?.cancel()
        listeners = listeners.filter { $0.value.tabManager !== tabManager }
    }

    @discardableResult
    func addListener(for tabManager: TabManager, listener: @escaping (String) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = BridgeListener(tabManager: tabManager, callback: listener)

        if let payload = try? encode(eventPayload(for: currentBridgeState(for: tabManager))) {
            listener(payload)
        }

        return id
    }

    func removeListener(_ id: UUID) {
        listeners.removeValue(forKey: id)
    }

    func currentBridgeState() -> BridgeAppState {
        let manager = AppDelegate.shared?.focusedTabManager ?? AppDelegate.shared?.tabManagers.first
        return BridgeAppState.from(tabManager: manager)
    }

    func currentBridgeState(for tabManager: TabManager) -> BridgeAppState {
        BridgeAppState.from(tabManager: tabManager)
    }

    func handle(_ request: BridgeRequest) -> BridgeResponse {
        guard let manager = AppDelegate.shared?.focusedTabManager ?? AppDelegate.shared?.tabManagers.first else {
            return BridgeResponse(id: request.id, ok: false, state: currentBridgeState(), error: "No active window")
        }

        return handle(request, for: manager)
    }

    func handle(_ request: BridgeRequest, for tabManager: TabManager) -> BridgeResponse {
        let state = currentBridgeState(for: tabManager)

        do {
            try execute(request: request, on: tabManager)
            return BridgeResponse(id: request.id, ok: true, state: currentBridgeState(for: tabManager), error: nil)
        } catch {
            return BridgeResponse(id: request.id, ok: false, state: state, error: error.localizedDescription)
        }
    }

    func handle(json: String) -> String {
        guard let manager = AppDelegate.shared?.focusedTabManager ?? AppDelegate.shared?.tabManagers.first else {
            let response = BridgeResponse(id: nil, ok: false, state: currentBridgeState(), error: "No active window")
            return (try? encode(response)) ?? "{\"ok\":false,\"error\":\"Bridge encoding failure\"}"
        }

        return handle(json: json, for: manager)
    }

    func handle(json: String, for tabManager: TabManager) -> String {
        do {
            let request = try JSONDecoder().decode(BridgeRequest.self, from: Data(json.utf8))
            let response = handle(request, for: tabManager)
            return try encode(response)
        } catch {
            let response = BridgeResponse(id: nil, ok: false, state: currentBridgeState(for: tabManager), error: error.localizedDescription)
            return (try? encode(response)) ?? "{\"ok\":false,\"error\":\"Bridge encoding failure\"}"
        }
    }

    private func execute(request: BridgeRequest, on tabManager: TabManager) throws {
        switch request.method {
        case .getState:
            return

        case .createWorkspace:
            let params = try decode(BridgeCreateWorkspaceParams.self, from: request.params)
            _ = tabManager.createWorkspace(directory: params.directory)

        case .selectWorkspace:
            let params = try decode(BridgeWorkspaceTargetParams.self, from: request.params)
            guard let workspaceId = UUID(uuidString: params.workspaceId) else { throw BridgeError.invalidIdentifier("workspaceId") }
            tabManager.selectWorkspace(workspaceId)

        case .closeWorkspace:
            let params = try decode(BridgeWorkspaceTargetParams.self, from: request.params)
            guard let workspaceId = UUID(uuidString: params.workspaceId) else { throw BridgeError.invalidIdentifier("workspaceId") }
            tabManager.closeWorkspace(workspaceId)

        case .createTab:
            if let paramsData = request.params,
               let params = try? JSONDecoder().decode(BridgeOptionalWorkspaceTargetParams.self, from: paramsData),
               let workspaceIdString = params.workspaceId,
               let workspaceId = UUID(uuidString: workspaceIdString) {
                tabManager.selectWorkspace(workspaceId)
            }
            _ = tabManager.createTab()

        case .closeTab:
            let params = try decode(BridgeTabTargetParams.self, from: request.params)
            guard let tabId = UUID(uuidString: params.tabId) else { throw BridgeError.invalidIdentifier("tabId") }
            tabManager.closeTab(tabId)

        case .selectTab:
            let params = try decode(BridgeTabTargetParams.self, from: request.params)
            guard let tabId = UUID(uuidString: params.tabId) else { throw BridgeError.invalidIdentifier("tabId") }
            tabManager.selectTab(tabId)

        case .splitTab:
            let params = try decode(BridgeSplitTabParams.self, from: request.params)
            let targetTab: Tab?
            if let tabIdString = params.tabId {
                guard let tabId = UUID(uuidString: tabIdString) else { throw BridgeError.invalidIdentifier("tabId") }
                targetTab = tabManager.tabs.first(where: { $0.id == tabId })
                tabManager.selectTab(tabId)
            } else {
                targetTab = tabManager.selectedTab
            }
            guard let tab = targetTab,
                  let workspace = tabManager.selectedWorkspace else { throw BridgeError.noSelectedTab }
            workspace.createSplitTab(nextTo: tab.id, direction: params.direction.splitDirection)

        case .toggleSidebar:
            tabManager.isSidebarVisible.toggle()

        case .selectNextTab:
            tabManager.selectNextTab()

        case .selectPreviousTab:
            tabManager.selectPreviousTab()

        case .selectNextPane:
            guard let workspace = tabManager.selectedWorkspace,
                  let layout = workspace.splitLayout else { throw BridgeError.noSplitLayout }
            let tabIds = layout.allTabIds
            guard tabIds.count > 1,
                  let currentId = workspace.selectedTabId,
                  let index = tabIds.firstIndex(of: currentId) else { throw BridgeError.noSplitLayout }
            workspace.selectedTabId = tabIds[(index + 1) % tabIds.count]

        case .selectPreviousPane:
            guard let workspace = tabManager.selectedWorkspace,
                  let layout = workspace.splitLayout else { throw BridgeError.noSplitLayout }
            let tabIds = layout.allTabIds
            guard tabIds.count > 1,
                  let currentId = workspace.selectedTabId,
                  let index = tabIds.firstIndex(of: currentId) else { throw BridgeError.noSplitLayout }
            workspace.selectedTabId = tabIds[(index - 1 + tabIds.count) % tabIds.count]
        }
    }

    private func broadcastState(for tabManager: TabManager) {
        let matching = listeners.values.filter { $0.tabManager === tabManager }
        guard !matching.isEmpty,
              let payload = try? encode(eventPayload(for: currentBridgeState(for: tabManager))) else { return }
        for listener in matching {
            listener.callback(payload)
        }
    }

    private func eventPayload(for state: BridgeAppState) -> BridgeEventPayload {
        BridgeEventPayload(event: .stateChanged, state: state)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data?) throws -> T {
        guard let data else { throw BridgeError.missingParams }
        return try JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw BridgeError.encodingFailure
        }
        return string
    }
}

private final class BridgeListener {
    weak var tabManager: TabManager?
    let callback: (String) -> Void

    init(tabManager: TabManager, callback: @escaping (String) -> Void) {
        self.tabManager = tabManager
        self.callback = callback
    }
}

enum BridgeError: LocalizedError {
    case missingParams
    case invalidIdentifier(String)
    case noSelectedTab
    case noSplitLayout
    case encodingFailure

    var errorDescription: String? {
        switch self {
        case .missingParams:
            return "Missing bridge params"
        case .invalidIdentifier(let field):
            return "Invalid identifier for \(field)"
        case .noSelectedTab:
            return "No selected tab"
        case .noSplitLayout:
            return "No split layout available"
        case .encodingFailure:
            return "Failed to encode bridge payload"
        }
    }
}
