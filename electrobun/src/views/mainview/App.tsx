import { useCallback, useEffect, useMemo, useState } from "react";
import {
  createTermoBridge,
  termoBridge,
  type BridgeAppState,
  type BridgeResponse,
  type BridgeSplitNodeState,
  type BridgeTabState,
  type BridgeWorkspaceState,
} from "../../shared/bridge";
import type { SplitDirection } from "../../shared/types";

function summarizePath(path: string | null | undefined) {
  if (!path) return "~";
  const home = "/Users/";
  if (path.startsWith(home)) {
    const parts = path.split("/").filter(Boolean);
    return parts.length > 2 ? `~/${parts.slice(2).join("/")}` : "~";
  }
  return path;
}

function countPanes(node: BridgeSplitNodeState | null): number {
  if (!node) return 1;
  if (node.type === "tab") return 1;
  return countPanes(node.first) + countPanes(node.second);
}

function countSplits(node: BridgeSplitNodeState | null): number {
  if (!node || node.type === "tab") return 0;
  return 1 + countSplits(node.first) + countSplits(node.second);
}

function selectedWorkspaceFrom(state: BridgeAppState | null) {
  if (!state) return null;
  return (
    state.workspaces.find((workspace) => workspace.id === state.selectedWorkspaceId) ??
    state.workspaces[0] ??
    null
  );
}

function selectedTabFrom(workspace: BridgeWorkspaceState | null) {
  if (!workspace) return null;
  return (
    workspace.tabs.find((tab) => tab.id === workspace.selectedTabId) ??
    workspace.tabs[0] ??
    null
  );
}

export function App() {
  const bridge = useMemo(() => createTermoBridge(), []);
  const [state, setState] = useState<BridgeAppState | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  const applyResponse = useCallback((response: BridgeResponse) => {
    setState(response.state);
    setError(response.ok ? null : response.error ?? "Bridge request failed");
    setIsLoading(false);
    return response;
  }, []);

  const invoke = useCallback(
    async (request: ReturnType<typeof termoBridge.request>) => {
      try {
        return applyResponse(await bridge.invoke(request));
      } catch (invokeError) {
        setIsLoading(false);
        setError(invokeError instanceof Error ? invokeError.message : "Bridge unavailable");
        return null;
      }
    },
    [applyResponse, bridge]
  );

  useEffect(() => {
    void invoke(termoBridge.getState());

    const unsubscribe = bridge.subscribe?.((payload) => {
      setState(payload.state);
      setIsLoading(false);
    });

    return unsubscribe;
  }, [bridge, invoke]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const meta = event.metaKey || event.ctrlKey;
      if (!meta) return;

      if (event.key === "t" && !event.shiftKey && !event.altKey) {
        event.preventDefault();
        void invoke(termoBridge.createTab(selectedWorkspaceFrom(state)?.id));
      } else if (event.key === "w" && !event.shiftKey && !event.altKey) {
        const selectedTab = selectedTabFrom(selectedWorkspaceFrom(state));
        if (!selectedTab) return;
        event.preventDefault();
        void invoke(termoBridge.closeTab(selectedTab.id));
      } else if (event.key === "d" && !event.shiftKey && !event.altKey) {
        const selectedTab = selectedTabFrom(selectedWorkspaceFrom(state));
        if (!selectedTab) return;
        event.preventDefault();
        void invoke(termoBridge.splitTab("horizontal", selectedTab.id));
      } else if (event.key === "D" && event.shiftKey && !event.altKey) {
        const selectedTab = selectedTabFrom(selectedWorkspaceFrom(state));
        if (!selectedTab) return;
        event.preventDefault();
        void invoke(termoBridge.splitTab("vertical", selectedTab.id));
      }
    };

    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [invoke, state]);

  const selectedWorkspace = selectedWorkspaceFrom(state);
  const selectedTab = selectedTabFrom(selectedWorkspace);
  const paneCount = countPanes(selectedWorkspace?.splitLayout ?? null);
  const splitCount = countSplits(selectedWorkspace?.splitLayout ?? null);

  return (
    <div className="termo-shell">
      <header className="hero">
        <div>
          <p className="eyebrow">Electrobun host</p>
          <h1>Ghostty sessions</h1>
        </div>
        <button className="ghost-button" onClick={() => void invoke(termoBridge.toggleSidebar())}>
          Toggle native workspace rail
        </button>
      </header>

      <section className="overview-card">
        <div>
          <span className="metric-label">Workspaces</span>
          <strong>{state?.workspaces.length ?? 0}</strong>
        </div>
        <div>
          <span className="metric-label">Sessions</span>
          <strong>{selectedWorkspace?.tabs.length ?? 0}</strong>
        </div>
        <div>
          <span className="metric-label">Panes</span>
          <strong>{paneCount}</strong>
        </div>
        <div>
          <span className="metric-label">Splits</span>
          <strong>{splitCount}</strong>
        </div>
      </section>

      <section className="actions-grid">
        <ActionButton
          label="New workspace"
          hint="Home"
          onClick={() =>
            void invoke(
              termoBridge.createWorkspace(selectedWorkspace?.directory || "/")
            )
          }
        />
        <ActionButton label="New session" hint="Cmd+T" onClick={() => void invoke(termoBridge.createTab(selectedWorkspace?.id))} />
        <ActionButton label="Split right" hint="Cmd+D" onClick={() => selectedTab && void invoke(termoBridge.splitTab("horizontal", selectedTab.id))} disabled={!selectedTab} />
        <ActionButton label="Split down" hint="Cmd+Shift+D" onClick={() => selectedTab && void invoke(termoBridge.splitTab("vertical", selectedTab.id))} disabled={!selectedTab} />
        <ActionButton label="Next pane" hint="Cmd+Opt+]" onClick={() => void invoke(termoBridge.selectNextPane())} disabled={paneCount < 2} />
        <ActionButton label="Prev pane" hint="Cmd+Opt+[" onClick={() => void invoke(termoBridge.selectPreviousPane())} disabled={paneCount < 2} />
      </section>

      <div className="panel-grid">
        <section className="panel">
          <div className="panel-header">
            <div>
              <p className="eyebrow">Workspaces</p>
              <h2>Projects</h2>
            </div>
          </div>

          <div className="panel-list">
            {state?.workspaces.map((workspace) => (
              <WorkspaceCard
                key={workspace.id}
                workspace={workspace}
                isSelected={workspace.id === selectedWorkspace?.id}
                onSelect={() => void invoke(termoBridge.selectWorkspace(workspace.id))}
                onClose={() => void invoke(termoBridge.closeWorkspace(workspace.id))}
              />
            ))}
          </div>
        </section>

        <section className="panel panel-sessions">
          <div className="panel-header">
            <div>
              <p className="eyebrow">Sessions</p>
              <h2>{selectedWorkspace?.displayName ?? "No workspace"}</h2>
            </div>
            <button className="ghost-button small" onClick={() => void invoke(termoBridge.createTab(selectedWorkspace?.id))}>
              Add session
            </button>
          </div>

          <div className="panel-list">
            {selectedWorkspace?.tabs.map((tab, index) => (
              <SessionCard
                key={tab.id}
                tab={tab}
                index={index}
                active={tab.id === selectedTab?.id}
                onSelect={() => void invoke(termoBridge.selectTab(tab.id))}
                onClose={() => void invoke(termoBridge.closeTab(tab.id))}
                onSplit={(direction) => void invoke(termoBridge.splitTab(direction, tab.id))}
              />
            ))}
          </div>
        </section>
      </div>

      <footer className="status-bar">
        <span>{isLoading ? "Connecting to native host..." : error ? error : selectedTab ? `Focused: ${selectedTab.title || "Terminal"}` : "Ready"}</span>
        <span>{selectedTab ? summarizePath(selectedTab.currentDirectory ?? selectedTab.initialWorkingDirectory) : "No active session"}</span>
      </footer>
    </div>
  );
}

function ActionButton({
  label,
  hint,
  onClick,
  disabled,
}: {
  label: string;
  hint: string;
  onClick: () => void;
  disabled?: boolean;
}) {
  return (
    <button className="action-button" onClick={onClick} disabled={disabled}>
      <span>{label}</span>
      <small>{hint}</small>
    </button>
  );
}

function WorkspaceCard({
  workspace,
  isSelected,
  onSelect,
  onClose,
}: {
  workspace: BridgeWorkspaceState;
  isSelected: boolean;
  onSelect: () => void;
  onClose: () => void;
}) {
  const activate = () => onSelect();

  return (
    <div
      className={`workspace-card ${isSelected ? "selected" : ""}`}
      onClick={activate}
      onKeyDown={(event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          activate();
        }
      }}
      role="button"
      tabIndex={0}
    >
      <div>
        <strong>{workspace.displayName}</strong>
        <span>{summarizePath(workspace.directory)}</span>
      </div>
      <div className="card-meta">
        <span>{workspace.tabs.length}</span>
        <button
          className="icon-button"
          onClick={(event) => {
            event.stopPropagation();
            onClose();
          }}
        >
          x
        </button>
      </div>
    </div>
  );
}

function SessionCard({
  tab,
  index,
  active,
  onSelect,
  onClose,
  onSplit,
}: {
  tab: BridgeTabState;
  index: number;
  active: boolean;
  onSelect: () => void;
  onClose: () => void;
  onSplit: (direction: SplitDirection) => void;
}) {
  const activate = () => onSelect();

  return (
    <div
      className={`session-card ${active ? "active" : ""}`}
      onClick={activate}
      onKeyDown={(event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          activate();
        }
      }}
      role="button"
      tabIndex={0}
    >
      <div className="session-index">{index + 1}</div>
      <div className="session-copy">
        <strong>{tab.title || "Terminal"}</strong>
        <span>{summarizePath(tab.currentDirectory ?? tab.initialWorkingDirectory)}</span>
      </div>
      <div className="session-actions">
        <button
          className="mini-button"
          onClick={(event) => {
            event.stopPropagation();
            onSplit("horizontal");
          }}
        >
          split x
        </button>
        <button
          className="mini-button"
          onClick={(event) => {
            event.stopPropagation();
            onSplit("vertical");
          }}
        >
          split y
        </button>
        <button
          className="icon-button"
          onClick={(event) => {
            event.stopPropagation();
            onClose();
          }}
        >
          x
        </button>
      </div>
    </div>
  );
}
