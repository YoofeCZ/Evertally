"use client";
import { useEffect, useState } from "react";

export class ApiFailure extends Error {
  constructor(public code: string, message: string, public status: number) { super(message); }
}

export async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(path, {
    ...init,
    headers: { ...(init?.body ? { "Content-Type": "application/json" } : {}), ...init?.headers },
    cache: "no-store",
  });
  const data = await response.json().catch(() => null) as (T & { error?: { code?: string; message?: string } }) | null;
  if (!response.ok || data === null) {
    throw new ApiFailure(data?.error?.code ?? "generic", data?.error?.message ?? `Request failed (${response.status}).`, response.status);
  }
  return data;
}

/** Fetch on mount and whenever `path` changes; `null` path skips. */
export function useApi<T>(path: string | null, version = 0) {
  const [state, setState] = useState<{ path: string | null; version: number; data: T | null; error: ApiFailure | null }>({ path: null, version: -1, data: null, error: null });
  useEffect(() => {
    if (!path) return;
    let canceled = false;
    api<T>(path)
      .then((data) => { if (!canceled) setState({ path, version, data, error: null }); })
      .catch((error: unknown) => {
        if (!canceled) setState({ path, version, data: null, error: error instanceof ApiFailure ? error : new ApiFailure("generic", "Request failed.", 0) });
      });
    return () => { canceled = true; };
  }, [path, version]);
  // Keep showing the previous data for the same path while a refresh is in flight.
  const samePath = state.path === path;
  return { data: samePath ? state.data : null, error: samePath ? state.error : null, loading: Boolean(path) && (!samePath || state.version !== version) };
}
