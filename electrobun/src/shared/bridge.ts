import type { SplitDirection } from "./types";

export type BridgeMethod =
  | "getState"
  | "createWorkspace"
  | "selectWorkspace"
  | "closeWorkspace"
  | "createTab"
  | "closeTab"
  | "selectTab"
  | "splitTab"
  | "toggleSidebar"
  | "selectNextTab"
  | "selectPreviousTab"
  | "selectNextPane"
  | "selectPreviousPane";

export interface BridgeRequest<T = unknown> {
  id?: string;
  method: BridgeMethod;
  params?: T;
}

export interface BridgeTabState {
  id: string;
  title: string;
  currentDirectory: string | null;
  initialWorkingDirectory: string | null;
}

export interface BridgeSplitNodeState {
  type: "tab" | "split";
  id: string;
  tabId: string | null;
  direction: SplitDirection | null;
  ratio: number | null;
  first: BridgeSplitNodeState | null;
  second: BridgeSplitNodeState | null;
}

export interface BridgeWorkspaceState {
  id: string;
  directory: string;
  displayName: string;
  selectedTabId: string | null;
  splitLayout: BridgeSplitNodeState | null;
  tabs: BridgeTabState[];
}

export interface BridgeAppState {
  windowId: string | null;
  sidebarVisible: boolean;
  selectedWorkspaceId: string | null;
  workspaces: BridgeWorkspaceState[];
}

export interface BridgeResponse {
  id?: string;
  ok: boolean;
  state: BridgeAppState;
  error?: string | null;
}

export interface BridgeEventPayload {
  event: "stateChanged";
  state: BridgeAppState;
}

export interface TermoBridgeTransport {
  invoke(request: BridgeRequest): Promise<BridgeResponse>;
  subscribe?(listener: (payload: BridgeEventPayload) => void): () => void;
}

declare global {
  interface Window {
    __TERMO_BRIDGE__?: {
      invoke(request: BridgeRequest): Promise<BridgeResponse> | BridgeResponse;
      subscribe?(listener: (payload: BridgeEventPayload) => void): () => void;
    };
    webkit?: {
      messageHandlers?: {
        termoBridge?: {
          postMessage(payload: BridgeRequest): void;
        };
      };
    };
  }
}

function createRequest<T>(method: BridgeMethod, params?: T): BridgeRequest<T> {
  return {
    id: crypto.randomUUID(),
    method,
    params,
  };
}

export function createTermoBridge(): TermoBridgeTransport {
  const nativeBridge = window.__TERMO_BRIDGE__;
  if (nativeBridge) {
    return {
      invoke: (request) => Promise.resolve(nativeBridge.invoke(request)),
      subscribe: nativeBridge.subscribe,
    };
  }

  return {
    async invoke(request) {
      throw new Error(`No native bridge transport available for ${request.method}`);
    },
  };
}

export const termoBridge = {
  request: createRequest,
  getState: () => createRequest("getState"),
  createWorkspace: (directory: string) => createRequest("createWorkspace", { directory }),
  selectWorkspace: (workspaceId: string) => createRequest("selectWorkspace", { workspaceId }),
  closeWorkspace: (workspaceId: string) => createRequest("closeWorkspace", { workspaceId }),
  createTab: (workspaceId?: string) => createRequest("createTab", { workspaceId }),
  closeTab: (tabId: string) => createRequest("closeTab", { tabId }),
  selectTab: (tabId: string) => createRequest("selectTab", { tabId }),
  splitTab: (direction: SplitDirection, tabId?: string) =>
    createRequest("splitTab", { tabId, direction }),
  toggleSidebar: () => createRequest("toggleSidebar"),
  selectNextTab: () => createRequest("selectNextTab"),
  selectPreviousTab: () => createRequest("selectPreviousTab"),
  selectNextPane: () => createRequest("selectNextPane"),
  selectPreviousPane: () => createRequest("selectPreviousPane"),
};
