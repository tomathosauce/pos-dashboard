const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? "";

export type Source = {
  name: string;
  path: string;
  reader: string;
  timezone: string;
  currency: string;
};

export type SyncRun = {
  id: number;
  source_name: string;
  business_date: string;
  status: "running" | "success" | "failed";
  started_at: string;
  finished_at: string | null;
  rows_read: number;
  rows_matched: number;
  warnings: string[];
  error_text: string | null;
};

export type SummaryDay = {
  business_date: string;
  total_amount: string;
  receipt_count: number;
};

export type DashboardSummary = {
  from_date: string;
  to_date: string;
  source: string;
  currency: string;
  total_amount: string;
  payment_count: number;
  receipt_count: number;
  source_row_count: number;
  last_sync: SyncRun | null;
  days: SummaryDay[];
};

export type PaymentSummary = {
  payment_code: string;
  payment_label: string;
  currency: string;
  total_amount: string;
  payment_count: number;
};

async function getJson<T>(path: string): Promise<T> {
  const response = await fetch(`${API_BASE_URL}${path}`);
  if (!response.ok) {
    throw new Error(`API request failed: ${response.status}`);
  }
  return response.json() as Promise<T>;
}

export async function fetchSources() {
  return getJson<Source[]>("/api/sources");
}

export async function fetchSummary(params: { from: string; to: string; source: string }) {
  const search = new URLSearchParams(params);
  return getJson<DashboardSummary>(`/api/dashboard/summary?${search.toString()}`);
}

export async function fetchPayments(params: { from: string; to: string; source: string }) {
  const search = new URLSearchParams(params);
  return getJson<PaymentSummary[]>(`/api/dashboard/payments?${search.toString()}`);
}

export async function fetchSyncRuns(limit = 10) {
  return getJson<SyncRun[]>(`/api/sync-runs?limit=${limit}`);
}
