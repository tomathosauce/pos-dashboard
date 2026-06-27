import { type ReactNode, useEffect, useMemo, useState } from "react";
import {
  AlertTriangle,
  CalendarDays,
  CheckCircle2,
  Database,
  DollarSign,
  Languages,
  ReceiptText,
  RefreshCw,
} from "lucide-react";
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import {
  DashboardSummary,
  PaymentSummary,
  Source,
  SyncRun,
  fetchPayments,
  fetchSources,
  fetchSummary,
  fetchSyncRuns,
  runSyncNow,
} from "@/lib/api";
import { formatCurrency, formatDateTime, formatNumber, yesterdayIso } from "@/lib/format";

type LoadState = {
  sources: Source[];
  summary: DashboardSummary | null;
  payments: PaymentSummary[];
  syncRuns: SyncRun[];
};

const emptyState: LoadState = {
  sources: [],
  summary: null,
  payments: [],
  syncRuns: [],
};

type Language = "en" | "zh-CN";
type SalesChartView = "daily" | "monthly";

const languageStorageKey = "pos-dashboard-language";

const localeByLanguage: Record<Language, string> = {
  en: "en-US",
  "zh-CN": "zh-CN",
};

const translations = {
  en: {
    appTitle: "Daily POS Dashboard",
    appSubtitle: "Sales and payment reconciliation",
    allSources: "All sources",
    refresh: "Refresh",
    forceSyncNow: "Force sync now",
    forceSyncingNow: "Syncing...",
    syncRequestFailed: "Sync request failed",
    dashboardRequestFailed: "Dashboard request failed",
    sales: "Sales",
    paymentRowsRead: (count: string) => `${count} payment rows read`,
    receipts: "Receipts",
    paymentAllocations: (count: string) => `${count} payment allocations`,
    lastSync: "Last Sync",
    noRuns: "No runs",
    never: "Never",
    window: "Window",
    allConfiguredSources: "All configured POS sources",
    range: (from: string, to: string) => `${from} to ${to}`,
    dailySales: "Daily Sales",
    monthlySales: "Monthly Sales",
    dailyView: "Daily",
    monthlyView: "Monthly",
    showDailySales: "Show daily sales",
    showMonthlySales: "Show monthly sales",
    actualSyncedWindow: (from: string, to: string) => `Actual synced window: ${from} to ${to}`,
    actualSyncedMonths: (from: string, to: string) => `Actual synced months: ${from} to ${to}`,
    noSyncedSalesDays: "No synced sales days in this window",
    noSyncedSalesDaysSentence: "No synced sales days in this window.",
    noSyncedSalesMonths: "No synced sales months in this window",
    noSyncedSalesMonthsSentence: "No synced sales months in this window.",
    paymentMix: "Payment Mix",
    totalsByMethod: "Totals by method",
    noPaymentTotals: "No payment totals for this range",
    syncStatus: "Sync Status",
    mostRecentRuns: "Most recent runs",
    noSyncRuns: "No sync runs recorded.",
    syncRows: (matched: string, read: string) => `${matched} matched / ${read} read`,
    paymentMethods: "Payment Methods",
    paymentMethodsDescription: "Daily payment totals from the POS sync",
    method: "Method",
    code: "Code",
    payments: "Payments",
    total: "Total",
    noPaymentData: "No payment data loaded for this range.",
    switchLanguage: "Switch language to Chinese",
    switchLanguageLabel: "中文",
    status: {
      success: "success",
      failed: "failed",
      partial: "partial",
      running: "running",
    },
  },
  "zh-CN": {
    appTitle: "每日 POS 仪表盘",
    appSubtitle: "销售与付款对账",
    allSources: "所有来源",
    refresh: "刷新",
    forceSyncNow: "立即强制同步",
    forceSyncingNow: "同步中...",
    syncRequestFailed: "同步请求失败",
    dashboardRequestFailed: "仪表盘请求失败",
    sales: "销售额",
    paymentRowsRead: (count: string) => `已读取 ${count} 条付款记录`,
    receipts: "收据",
    paymentAllocations: (count: string) => `${count} 笔付款分配`,
    lastSync: "上次同步",
    noRuns: "暂无运行记录",
    never: "从未",
    window: "时间窗口",
    allConfiguredSources: "所有已配置 POS 来源",
    range: (from: string, to: string) => `${from} 至 ${to}`,
    dailySales: "每日销售额",
    monthlySales: "每月销售额",
    dailyView: "每日",
    monthlyView: "每月",
    showDailySales: "显示每日销售额",
    showMonthlySales: "显示每月销售额",
    actualSyncedWindow: (from: string, to: string) => `实际同步窗口：${from} 至 ${to}`,
    actualSyncedMonths: (from: string, to: string) => `实际同步月份：${from} 至 ${to}`,
    noSyncedSalesDays: "此窗口内没有已同步销售日",
    noSyncedSalesDaysSentence: "此窗口内没有已同步销售日。",
    noSyncedSalesMonths: "此窗口内没有已同步销售月份",
    noSyncedSalesMonthsSentence: "此窗口内没有已同步销售月份。",
    paymentMix: "付款构成",
    totalsByMethod: "按付款方式汇总",
    noPaymentTotals: "此范围内没有付款汇总",
    syncStatus: "同步状态",
    mostRecentRuns: "最近运行",
    noSyncRuns: "暂无同步运行记录。",
    syncRows: (matched: string, read: string) => `匹配 ${matched} / 读取 ${read}`,
    paymentMethods: "付款方式",
    paymentMethodsDescription: "来自 POS 同步的每日付款汇总",
    method: "方式",
    code: "代码",
    payments: "付款笔数",
    total: "总计",
    noPaymentData: "此范围内没有已加载的付款数据。",
    switchLanguage: "切换语言为英文",
    switchLanguageLabel: "English",
    status: {
      success: "成功",
      failed: "失败",
      partial: "部分成功",
      running: "运行中",
    },
  },
} satisfies Record<
  Language,
  {
    appTitle: string;
    appSubtitle: string;
    allSources: string;
    refresh: string;
    forceSyncNow: string;
    forceSyncingNow: string;
    syncRequestFailed: string;
    dashboardRequestFailed: string;
    sales: string;
    paymentRowsRead: (count: string) => string;
    receipts: string;
    paymentAllocations: (count: string) => string;
    lastSync: string;
    noRuns: string;
    never: string;
    window: string;
    allConfiguredSources: string;
    range: (from: string, to: string) => string;
    dailySales: string;
    monthlySales: string;
    dailyView: string;
    monthlyView: string;
    showDailySales: string;
    showMonthlySales: string;
    actualSyncedWindow: (from: string, to: string) => string;
    actualSyncedMonths: (from: string, to: string) => string;
    noSyncedSalesDays: string;
    noSyncedSalesDaysSentence: string;
    noSyncedSalesMonths: string;
    noSyncedSalesMonthsSentence: string;
    paymentMix: string;
    totalsByMethod: string;
    noPaymentTotals: string;
    syncStatus: string;
    mostRecentRuns: string;
    noSyncRuns: string;
    syncRows: (matched: string, read: string) => string;
    paymentMethods: string;
    paymentMethodsDescription: string;
    method: string;
    code: string;
    payments: string;
    total: string;
    noPaymentData: string;
    switchLanguage: string;
    switchLanguageLabel: string;
    status: Record<string, string>;
  }
>;

function isLanguage(value: string | null): value is Language {
  return value === "en" || value === "zh-CN";
}

function getInitialLanguage(): Language {
  try {
    const storedLanguage = window.localStorage.getItem(languageStorageKey);
    return isLanguage(storedLanguage) ? storedLanguage : "en";
  } catch {
    return "en";
  }
}

function translatedStatus(status: string | undefined, t: (typeof translations)[Language]) {
  if (!status) return undefined;
  const statusLabels = t.status as Record<string, string>;
  return statusLabels[status] ?? status;
}

function statusVariant(status?: string) {
  if (status === "success") return "default";
  if (status === "failed") return "destructive";
  return "secondary";
}

function App() {
  const defaultDate = useMemo(() => yesterdayIso(), []);
  const [language, setLanguage] = useState<Language>(() => getInitialLanguage());
  const [fromDate, setFromDate] = useState(defaultDate);
  const [toDate, setToDate] = useState(defaultDate);
  const [source, setSource] = useState("all");
  const [salesChartView, setSalesChartView] = useState<SalesChartView>("daily");
  const [state, setState] = useState<LoadState>(emptyState);
  const [isLoading, setIsLoading] = useState(true);
  const [isSyncing, setIsSyncing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const t = translations[language];
  const locale = localeByLanguage[language];
  const nextLanguage: Language = language === "en" ? "zh-CN" : "en";

  async function loadDashboard() {
    setIsLoading(true);
    setError(null);
    try {
      const [sources, summary, payments, syncRuns] = await Promise.all([
        fetchSources(),
        fetchSummary({ from: fromDate, to: toDate, source }),
        fetchPayments({ from: fromDate, to: toDate, source }),
        fetchSyncRuns(10),
      ]);
      setState({ sources, summary, payments, syncRuns });
    } catch (err) {
      setError(err instanceof Error ? err.message : t.dashboardRequestFailed);
    } finally {
      setIsLoading(false);
    }
  }

  async function handleForceSyncNow() {
    setIsSyncing(true);
    setError(null);
    try {
      await runSyncNow(source);
      await loadDashboard();
    } catch (err) {
      setError(err instanceof Error ? err.message : t.syncRequestFailed);
    } finally {
      setIsSyncing(false);
    }
  }

  useEffect(() => {
    document.documentElement.lang = language;
    try {
      window.localStorage.setItem(languageStorageKey, language);
    } catch {
      // Non-critical preference persistence can fail in restricted browser modes.
    }
  }, [language]);

  useEffect(() => {
    loadDashboard();
  }, [fromDate, toDate, source]);

  const currency = state.summary?.currency ?? "USD";
  const lastSync = state.summary?.last_sync ?? state.syncRuns[0] ?? null;
  const paymentChartData = state.payments.map((payment) => ({
    name: payment.payment_label,
    total: Number(payment.total_amount),
  }));
  const dailySalesChartData = (state.summary?.days ?? []).map((day) => ({
    date: day.business_date,
    total: Number(day.total_amount),
  }));
  const monthlySalesChartData = Array.from(
    dailySalesChartData.reduce((months, day) => {
      const month = day.date.slice(0, 7);
      months.set(month, (months.get(month) ?? 0) + day.total);
      return months;
    }, new Map<string, number>()),
    ([date, total]) => ({ date, total }),
  ).sort((first, second) => first.date.localeCompare(second.date));
  const salesChartData = salesChartView === "daily" ? dailySalesChartData : monthlySalesChartData;
  const salesChartTitle = salesChartView === "daily" ? t.dailySales : t.monthlySales;
  const actualWindowLabel =
    salesChartData.length > 0
      ? salesChartView === "daily"
        ? t.actualSyncedWindow(salesChartData[0].date, salesChartData[salesChartData.length - 1].date)
        : t.actualSyncedMonths(salesChartData[0].date, salesChartData[salesChartData.length - 1].date)
      : salesChartView === "daily"
        ? t.noSyncedSalesDays
        : t.noSyncedSalesMonths;
  const emptySalesChartLabel =
    salesChartView === "daily" ? t.noSyncedSalesDaysSentence : t.noSyncedSalesMonthsSentence;

  return (
    <main className="min-h-screen bg-background">
      <div className="mx-auto flex w-full max-w-7xl flex-col gap-5 px-4 py-5 sm:px-6 lg:px-8">
        <header className="flex flex-col gap-4 border-b border-border pb-5 lg:flex-row lg:items-end lg:justify-between">
          <div className="space-y-2">
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/15 text-primary">
                <Database className="h-5 w-5" />
              </div>
              <div>
                <h1 className="text-2xl font-semibold tracking-normal">{t.appTitle}</h1>
                <p className="text-sm text-muted-foreground">{t.appSubtitle}</p>
              </div>
            </div>
          </div>

          <div className="grid gap-3 sm:grid-cols-[150px_150px_160px_auto_auto_auto]">
            <Input type="date" value={fromDate} onChange={(event) => setFromDate(event.target.value)} />
            <Input type="date" value={toDate} onChange={(event) => setToDate(event.target.value)} />
            <select
              className="h-9 rounded-md border border-input bg-background px-3 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
              value={source}
              onChange={(event) => setSource(event.target.value)}
            >
              <option value="all">{t.allSources}</option>
              {state.sources.map((item) => (
                <option key={item.name} value={item.name}>
                  {item.name}
                </option>
              ))}
            </select>
            <Button variant="secondary" onClick={loadDashboard} disabled={isLoading || isSyncing}>
              <RefreshCw className={`mr-2 h-4 w-4 ${isLoading ? "animate-spin" : ""}`} />
              {t.refresh}
            </Button>
            <Button type="button" onClick={handleForceSyncNow} disabled={isSyncing || isLoading}>
              <RefreshCw className={`mr-2 h-4 w-4 ${isSyncing ? "animate-spin" : ""}`} />
              {isSyncing ? t.forceSyncingNow : t.forceSyncNow}
            </Button>
            <Button
              type="button"
              variant="outline"
              onClick={() => setLanguage(nextLanguage)}
              aria-label={t.switchLanguage}
              title={t.switchLanguage}
            >
              <Languages className="mr-2 h-4 w-4" />
              {t.switchLanguageLabel}
            </Button>
          </div>
        </header>

        {error ? (
          <Card className="border-destructive/50">
            <CardContent className="flex items-center gap-3 p-5 text-sm text-destructive">
              <AlertTriangle className="h-4 w-4" />
              {error}
            </CardContent>
          </Card>
        ) : null}

        <section className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          <MetricCard
            title={t.sales}
            value={formatCurrency(state.summary?.total_amount ?? 0, currency, locale)}
            icon={<DollarSign className="h-4 w-4" />}
            muted={t.paymentRowsRead(formatNumber(state.summary?.source_row_count ?? 0, locale))}
          />
          <MetricCard
            title={t.receipts}
            value={formatNumber(state.summary?.receipt_count ?? 0, locale)}
            icon={<ReceiptText className="h-4 w-4" />}
            muted={t.paymentAllocations(formatNumber(state.summary?.payment_count ?? 0, locale))}
          />
          <MetricCard
            title={t.lastSync}
            value={lastSync ? translatedStatus(lastSync.status, t) ?? lastSync.status : t.noRuns}
            icon={lastSync?.status === "success" ? <CheckCircle2 className="h-4 w-4" /> : <AlertTriangle className="h-4 w-4" />}
            muted={formatDateTime(lastSync?.finished_at ?? lastSync?.started_at, locale, t.never)}
            badge={lastSync?.status}
            badgeLabel={translatedStatus(lastSync?.status, t)}
          />
          <MetricCard
            title={t.window}
            value={fromDate === toDate ? fromDate : t.range(fromDate, toDate)}
            icon={<CalendarDays className="h-4 w-4" />}
            muted={source === "all" ? t.allConfiguredSources : source}
          />
        </section>

        <Card>
          <CardHeader className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <CardTitle>{salesChartTitle}</CardTitle>
              <CardDescription>{actualWindowLabel}</CardDescription>
            </div>
            <div className="grid grid-cols-2 rounded-md border border-input bg-background p-1">
              <Button
                type="button"
                size="sm"
                variant={salesChartView === "daily" ? "secondary" : "ghost"}
                className="w-24"
                aria-pressed={salesChartView === "daily"}
                aria-label={t.showDailySales}
                onClick={() => setSalesChartView("daily")}
              >
                {t.dailyView}
              </Button>
              <Button
                type="button"
                size="sm"
                variant={salesChartView === "monthly" ? "secondary" : "ghost"}
                className="w-24"
                aria-pressed={salesChartView === "monthly"}
                aria-label={t.showMonthlySales}
                onClick={() => setSalesChartView("monthly")}
              >
                {t.monthlyView}
              </Button>
            </div>
          </CardHeader>
          <CardContent>
            <div className="h-72">
              {salesChartData.length === 0 ? (
                <div className="flex h-full items-center justify-center rounded-md border border-dashed border-border text-sm text-muted-foreground">
                  {emptySalesChartLabel}
                </div>
              ) : (
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={salesChartData} margin={{ top: 10, right: 12, left: 0, bottom: 24 }}>
                    <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
                    <XAxis
                      dataKey="date"
                      tick={{ fill: "hsl(var(--muted-foreground))", fontSize: 12 }}
                      interval={0}
                      minTickGap={12}
                      height={42}
                    />
                    <YAxis tick={{ fill: "hsl(var(--muted-foreground))", fontSize: 12 }} width={80} />
                    <Tooltip
                      cursor={{ fill: "hsl(var(--muted))" }}
                      contentStyle={{
                        background: "hsl(var(--card))",
                        border: "1px solid hsl(var(--border))",
                        borderRadius: "8px",
                      }}
                      formatter={(value) => formatCurrency(Number(value), currency, locale)}
                    />
                    <Bar dataKey="total" fill="hsl(var(--accent))" radius={[4, 4, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              )}
            </div>
          </CardContent>
        </Card>

        <section className="grid gap-4 xl:grid-cols-[1.15fr_0.85fr]">
          <Card>
            <CardHeader>
              <CardTitle>{t.paymentMix}</CardTitle>
              <CardDescription>{state.payments.length ? t.totalsByMethod : t.noPaymentTotals}</CardDescription>
            </CardHeader>
            <CardContent>
              <div className="h-72">
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={paymentChartData} margin={{ top: 10, right: 12, left: 0, bottom: 24 }}>
                    <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
                    <XAxis dataKey="name" tick={{ fill: "hsl(var(--muted-foreground))", fontSize: 12 }} interval={0} angle={-20} textAnchor="end" height={60} />
                    <YAxis tick={{ fill: "hsl(var(--muted-foreground))", fontSize: 12 }} width={70} />
                    <Tooltip
                      cursor={{ fill: "hsl(var(--muted))" }}
                      contentStyle={{
                        background: "hsl(var(--card))",
                        border: "1px solid hsl(var(--border))",
                        borderRadius: "8px",
                      }}
                      formatter={(value) => formatCurrency(Number(value), currency, locale)}
                    />
                    <Bar dataKey="total" fill="hsl(var(--primary))" radius={[4, 4, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>{t.syncStatus}</CardTitle>
              <CardDescription>{t.mostRecentRuns}</CardDescription>
            </CardHeader>
            <CardContent>
              <div className="space-y-3">
                {state.syncRuns.length === 0 ? (
                  <p className="text-sm text-muted-foreground">{t.noSyncRuns}</p>
                ) : (
                  state.syncRuns.slice(0, 5).map((run) => (
                    <div key={run.id} className="flex items-center justify-between gap-3 rounded-md border border-border p-3">
                      <div className="min-w-0">
                        <div className="truncate text-sm font-medium">
                          {run.source_name} · {run.business_date}
                        </div>
                        <div className="text-xs text-muted-foreground">
                          {t.syncRows(formatNumber(run.rows_matched, locale), formatNumber(run.rows_read, locale))}
                        </div>
                      </div>
                      <Badge variant={statusVariant(run.status)}>{translatedStatus(run.status, t)}</Badge>
                    </div>
                  ))
                )}
              </div>
            </CardContent>
          </Card>
        </section>

        <Card>
          <CardHeader>
            <CardTitle>{t.paymentMethods}</CardTitle>
            <CardDescription>{t.paymentMethodsDescription}</CardDescription>
          </CardHeader>
          <CardContent>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t.method}</TableHead>
                  <TableHead>{t.code}</TableHead>
                  <TableHead className="text-right">{t.payments}</TableHead>
                  <TableHead className="text-right">{t.total}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {state.payments.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={4} className="h-20 text-center text-muted-foreground">
                      {t.noPaymentData}
                    </TableCell>
                  </TableRow>
                ) : (
                  state.payments.map((payment) => (
                    <TableRow key={payment.payment_code}>
                      <TableCell className="font-medium">{payment.payment_label}</TableCell>
                      <TableCell className="font-mono text-xs text-muted-foreground">{payment.payment_code}</TableCell>
                      <TableCell className="text-right">{formatNumber(payment.payment_count, locale)}</TableCell>
                      <TableCell className="text-right font-medium">
                        {formatCurrency(payment.total_amount, payment.currency, locale)}
                      </TableCell>
                    </TableRow>
                  ))
                )}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      </div>
    </main>
  );
}

function MetricCard({
  title,
  value,
  muted,
  icon,
  badge,
  badgeLabel,
}: {
  title: string;
  value: string;
  muted: string;
  icon: ReactNode;
  badge?: string;
  badgeLabel?: string;
}) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-3">
        <CardTitle className="text-muted-foreground">{title}</CardTitle>
        <div className="text-muted-foreground">{icon}</div>
      </CardHeader>
      <CardContent>
        <div className="flex items-center gap-2">
          <div className="truncate text-2xl font-semibold">{value}</div>
          {badge ? <Badge variant={statusVariant(badge)}>{badgeLabel ?? badge}</Badge> : null}
        </div>
        <p className="mt-1 truncate text-xs text-muted-foreground">{muted}</p>
      </CardContent>
    </Card>
  );
}

export default App;
