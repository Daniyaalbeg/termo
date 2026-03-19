import AppKit
import SwiftUI

/// Main window content: workspace sidebar + vertical session rail + terminal.
struct ContentView: View {
    @ObservedObject var tabManager: TabManager
    @State private var sidebarWidth: CGFloat = 196
    @State private var sessionRailWidth: CGFloat = 248

    private var bgColor: Color { Color(nsColor: GhosttyManager.shared.backgroundColor) }

    var body: some View {
        HStack(spacing: 0) {
            if tabManager.isSidebarVisible {
                WorkspaceSidebar(tabManager: tabManager)
                    .frame(width: sidebarWidth)

                VerticalResizeDivider(width: $sidebarWidth, minWidth: 140, maxWidth: 360)
            }

            SessionSidebar(tabManager: tabManager)
                .frame(width: sessionRailWidth)

            VerticalResizeDivider(width: $sessionRailWidth, minWidth: 180, maxWidth: 340)

            SplitDropTargetView(tabManager: tabManager) {
                TerminalContainerView(tabManager: tabManager)
            }
        }
        .background(bgColor)
    }
}

struct VerticalResizeDivider: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(width: 1)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        width = min(max(width + value.translation.width, minWidth), maxWidth)
                    }
            )
    }
}

// MARK: - Workspace sidebar

struct WorkspaceSidebar: View {
    @ObservedObject var tabManager: TabManager

    private var bgColor: Color { Color(nsColor: GhosttyManager.shared.backgroundColor) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 8)

            Text("Workspaces")
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.28))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)

            Button(action: {
                let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
                let ws = tabManager.createWorkspace(directory: homeDir)
                ws.createTab()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                    Text("New workspace")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.05))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(tabManager.workspaces) { workspace in
                        WorkspaceItemView(
                            workspace: workspace,
                            isSelected: workspace.id == tabManager.selectedWorkspaceId,
                            onSelect: { tabManager.selectWorkspace(workspace.id) },
                            onClose: { tabManager.closeWorkspace(workspace.id) }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()
        }
        .background(bgColor)
    }
}

struct WorkspaceItemView: View {
    @ObservedObject var workspace: Workspace
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var isHovering = false
    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var isTextFieldFocused: Bool

    /// The selected tab's title, used for the subtitle line.
    private var activeTabTitle: String {
        workspace.selectedTab?.title ?? ""
    }

    /// Short directory path for display (e.g. "~/Projects/termo").
    private var directoryLabel: String {
        let dir = workspace.selectedTab?.currentDirectory ?? workspace.directory
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if dir.hasPrefix(home) {
            let rel = String(dir.dropFirst(home.count))
            return rel.isEmpty ? "~" : "~" + rel
        }
        return dir
    }

    private func commitEdit() {
        let trimmed = editText.trimmingCharacters(in: .whitespaces)
        workspace.customName = trimmed.isEmpty ? nil : trimmed
        isEditing = false
    }

    private func cancelEdit() {
        isEditing = false
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    TextField("Workspace name", text: $editText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .focused($isTextFieldFocused)
                        .onSubmit { commitEdit() }
                        .onExitCommand { cancelEdit() }
                } else {
                    Text(workspace.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .foregroundColor(isSelected ? .white.opacity(0.9) : .white.opacity(0.5))
                }

                Text(directoryLabel)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(isSelected ? .white.opacity(0.4) : .white.opacity(0.2))
            }

            Spacer()

            if isHovering {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text("\(workspace.tabs.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.white.opacity(0.06) : isHovering ? Color.white.opacity(0.03) : Color.clear)
        )
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) {
            editText = workspace.customName ?? workspace.displayName
            isEditing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isTextFieldFocused = true
            }
        }
        .onTapGesture(count: 1) {
            if isEditing {
                commitEdit()
            } else {
                onSelect()
            }
        }
    }
}

// MARK: - Session sidebar

struct SessionSidebar: View {
    @ObservedObject var tabManager: TabManager

    private var bgColor: Color { Color(nsColor: GhosttyManager.shared.backgroundColor) }

    var body: some View {
        VStack(spacing: 0) {
            SessionControls(tabManager: tabManager)

            if let ws = tabManager.selectedWorkspace {
                SessionListView(workspace: ws, tabManager: tabManager)
            } else {
                Spacer()
            }
        }
        .background(bgColor)
    }
}

struct SessionControls: View {
    @ObservedObject var tabManager: TabManager

    private var hasSelection: Bool {
        tabManager.selectedWorkspace?.selectedTab != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ControlChip(
                    icon: tabManager.isSidebarVisible ? "sidebar.left" : "sidebar.right",
                    title: tabManager.isSidebarVisible ? "Hide workspaces" : "Show workspaces"
                ) {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        tabManager.isSidebarVisible.toggle()
                    }
                }

                ControlChip(icon: "plus", title: "New session") {
                    tabManager.selectedWorkspace?.createTab()
                }
            }

            HStack(spacing: 8) {
                ControlChip(icon: "rectangle.split.2x1", title: "Split right", isEnabled: hasSelection) {
                    if let ws = tabManager.selectedWorkspace, let tab = ws.selectedTab {
                        ws.createSplitTab(nextTo: tab.id, direction: .horizontal)
                    }
                }

                ControlChip(icon: "rectangle.split.1x2", title: "Split down", isEnabled: hasSelection) {
                    if let ws = tabManager.selectedWorkspace, let tab = ws.selectedTab {
                        ws.createSplitTab(nextTo: tab.id, direction: .vertical)
                    }
                }

                ControlChip(icon: "xmark", title: "Close session", isEnabled: hasSelection) {
                    if let tab = tabManager.selectedWorkspace?.selectedTab {
                        tabManager.closeTab(tab.id)
                    }
                }
            }

            Text("Sessions")
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.28))
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

struct ControlChip: View {
    let icon: String
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(.white.opacity(isEnabled ? 0.78 : 0.24))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(isHovering && isEnabled ? 0.08 : 0.04))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovering = $0 }
    }
}

struct SessionListView: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var tabManager: TabManager
    @State private var draggedTabId: UUID?

    var body: some View {
        let tabs = Array(workspace.tabs.enumerated())

        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(tabs, id: \.element.id) { index, tab in
                    SessionItemView(
                        tab: tab,
                        index: index,
                        isSelected: tab.id == workspace.selectedTabId,
                        isOnly: workspace.tabs.count == 1,
                        onClose: { tabManager.closeTab(tab.id) }
                    )
                    .onTapGesture { workspace.selectTab(tab.id) }
                    .onDrag {
                        draggedTabId = tab.id
                        return NSItemProvider(object: tab.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: TabDropDelegate(
                        targetId: tab.id,
                        workspace: workspace,
                        draggedTabId: $draggedTabId
                    ))
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }
}

struct SessionItemView: View {
    @ObservedObject var tab: Tab
    let index: Int
    let isSelected: Bool
    let isOnly: Bool
    let onClose: () -> Void
    @State private var isHovering = false

    private var directoryLabel: String {
        let dir = tab.currentDirectory ?? tab.initialWorkingDirectory ?? "~"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if dir.hasPrefix(home) {
            let rel = String(dir.dropFirst(home.count))
            return rel.isEmpty ? "~" : "~" + rel
        }
        return dir
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 6) {
                Circle()
                    .fill(isSelected ? Color.white.opacity(0.85) : Color.white.opacity(0.18))
                    .frame(width: 7, height: 7)

                if index < 9 {
                    Text("\(index + 1)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.24))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(tab.title.isEmpty ? "Terminal" : tab.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(isSelected ? .white.opacity(0.92) : .white.opacity(0.54))

                Text(directoryLabel)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(isSelected ? .white.opacity(0.42) : .white.opacity(0.24))
            }

            Spacer(minLength: 6)

            if isHovering && !isOnly {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.44))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.white.opacity(0.07) : isHovering ? Color.white.opacity(0.035) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

// MARK: - Tab drag & drop

// MARK: - Split drop target

struct SplitDropTargetView<Content: View>: View {
    @ObservedObject var tabManager: TabManager
    let content: () -> Content
    @State private var dropEdge: Edge?

    init(tabManager: TabManager, @ViewBuilder content: @escaping () -> Content) {
        self.tabManager = tabManager
        self.content = content
    }

    var body: some View {
        content()
            .onDrop(of: [.text], delegate: SplitDropDelegate(
                tabManager: tabManager,
                size: .zero,
                dropEdge: $dropEdge
            ))
            .overlay(
                GeometryReader { geo in
                    // Drop zone overlay — only visible when dragging
                    if let edge = dropEdge {
                        dropHighlight(edge: edge, size: geo.size)
                    }
                }
            )
    }

    @ViewBuilder
    private func dropHighlight(edge: Edge, size: CGSize) -> some View {
        let halfW = size.width / 2
        let halfH = size.height / 2
        switch edge {
        case .leading:
            Rectangle().fill(Color.blue.opacity(0.15))
                .frame(width: halfW, height: size.height)
                .position(x: halfW / 2, y: size.height / 2)
        case .trailing:
            Rectangle().fill(Color.blue.opacity(0.15))
                .frame(width: halfW, height: size.height)
                .position(x: size.width - halfW / 2, y: size.height / 2)
        case .top:
            Rectangle().fill(Color.blue.opacity(0.15))
                .frame(width: size.width, height: halfH)
                .position(x: size.width / 2, y: halfH / 2)
        case .bottom:
            Rectangle().fill(Color.blue.opacity(0.15))
                .frame(width: size.width, height: halfH)
                .position(x: size.width / 2, y: size.height - halfH / 2)
        }
    }
}

struct SplitDropDelegate: DropDelegate {
    let tabManager: TabManager
    let size: CGSize
    @Binding var dropEdge: Edge?

    private var effectiveSize: CGSize {
        if size == .zero,
           let frame = tabManager.window?.contentView?.bounds.size,
           frame.width > 0,
           frame.height > 0 {
            return frame
        }
        return size
    }

    private func edgeForLocation(_ location: CGPoint) -> Edge {
        let currentSize = effectiveSize
        let relX = location.x / max(currentSize.width, 1)
        let relY = location.y / max(currentSize.height, 1)
        // Check which edge is closest
        let distances: [(Edge, CGFloat)] = [
            (.leading, relX),
            (.trailing, 1 - relX),
            (.top, relY),
            (.bottom, 1 - relY),
        ]
        return distances.min(by: { $0.1 < $1.1 })!.0
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        dropEdge = edgeForLocation(info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        dropEdge = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        dropEdge = nil
        guard let ws = tabManager.selectedWorkspace,
              let currentTab = ws.selectedTab else { return false }

        // Get the dropped tab ID from the drag data
        guard let item = info.itemProviders(for: [.text]).first else { return false }
        item.loadObject(ofClass: NSString.self) { string, _ in
            guard let uuidString = string as? String,
                  let droppedTabId = UUID(uuidString: uuidString) else { return }

            DispatchQueue.main.async {
                // Don't split with self
                guard droppedTabId != currentTab.id else { return }
                // Must be a tab in this workspace
                guard ws.tabs.contains(where: { $0.id == droppedTabId }) else { return }

                let edge = self.edgeForLocation(info.location)
                let direction: SplitNode.SplitDirection = (edge == .leading || edge == .trailing) ? .horizontal : .vertical

                // Create split layout
                if let layout = ws.splitLayout {
                    // Already split — add to the tree next to the current tab
                    if !layout.allTabIds.contains(droppedTabId) {
                        layout.splitTab(currentTab.id, with: droppedTabId, direction: direction)
                    }
                } else {
                    let root = SplitNode(tabId: currentTab.id)
                    if edge == .leading || edge == .top {
                        // Dropped tab goes first
                        root.splitTab(currentTab.id, with: droppedTabId, direction: direction)
                        // Swap: we need dropped tab on the left/top
                        // Actually splitTab puts droppedTabId as second, so for leading/top we swap
                        if case .split(let dir, let first, let second, let ratio) = root.content {
                            root.content = .split(direction: dir, first: second, second: first, ratio: 1 - ratio)
                        }
                    } else {
                        root.splitTab(currentTab.id, with: droppedTabId, direction: direction)
                    }
                    ws.splitLayout = root
                }
                ws.selectedTabId = droppedTabId
            }
        }
        return true
    }
}

struct TabDropDelegate: DropDelegate {
    let targetId: UUID
    let workspace: Workspace
    @Binding var draggedTabId: UUID?

    func performDrop(info: DropInfo) -> Bool {
        draggedTabId = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedId = draggedTabId, draggedId != targetId else { return }
        withAnimation(.easeInOut(duration: 0.1)) {
            workspace.moveTab(from: draggedId, to: targetId)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - Terminal container

struct TerminalContainerView: NSViewRepresentable {
    @ObservedObject var tabManager: TabManager

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let ws = tabManager.selectedWorkspace,
              let selectedTab = tabManager.selectedTab else {
            container.subviews.forEach { $0.isHidden = true }
            return
        }

        let tabLookup: (UUID) -> Tab? = { id in ws.tabs.first { $0.id == id } }

        // Clean up stale tab IDs from split layout
        if let layout = ws.splitLayout {
            let tabIds = Set(ws.tabs.map { $0.id })
            for splitTabId in layout.allTabIds where !tabIds.contains(splitTabId) {
                layout.removeTab(splitTabId)
            }
            if layout.allTabIds.count <= 1 {
                ws.splitLayout = nil
            }
        }

        if let layout = ws.splitLayout,
           layout.allTabIds.count > 1,
           layout.allTabIds.contains(selectedTab.id) {
            // Split mode: show multiple tabs via SplitContainerView
            let splitContainer: SplitContainerView
            if let existing = container.subviews.compactMap({ $0 as? SplitContainerView }).first {
                splitContainer = existing
            } else {
                splitContainer = SplitContainerView(frame: container.bounds)
                splitContainer.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(splitContainer)
                NSLayoutConstraint.activate([
                    splitContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    splitContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    splitContainer.topAnchor.constraint(equalTo: container.topAnchor),
                    splitContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                ])
            }

            splitContainer.isHidden = false
            splitContainer.update(with: layout, tabLookup: tabLookup)

            // Refresh visible surfaces
            for tabId in layout.allTabIds {
                if let tab = tabLookup(tabId), let tv = tab.terminalView, let surface = tv.surface {
                    ghostty_surface_refresh(surface)
                    tv.needsDisplay = true
                }
            }
        } else {
            // Single tab mode — hide split container but don't remove it
            for subview in container.subviews where subview is SplitContainerView {
                subview.isHidden = true
            }

            let terminalView = selectedTab.makeTerminalView(frame: container.bounds)

            if terminalView.superview is SplitContainerView {
                // Move out of the split container back to the main container
                terminalView.removeFromSuperview()
            }

            if terminalView.superview !== container {
                terminalView.removeFromSuperview()
                terminalView.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(terminalView)
                NSLayoutConstraint.activate([
                    terminalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    terminalView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    terminalView.topAnchor.constraint(equalTo: container.topAnchor),
                    terminalView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                ])
            }

            // Hide other direct terminal views
            for subview in container.subviews where subview is TerminalView {
                subview.isHidden = (subview !== terminalView)
            }
            terminalView.isHidden = false

            if let surface = terminalView.surface {
                ghostty_surface_refresh(surface)
            }
            terminalView.needsDisplay = true

            DispatchQueue.main.async {
                selectedTab.focus()
            }
        }
    }
}
