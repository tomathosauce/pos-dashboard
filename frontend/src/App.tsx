import { type ReactNode, useEffect, useMemo, useState } from "react";
import {
  AlertTriangle,
  CalendarDays,
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  Database,
  DollarSign,
  Languages,
  ReceiptText,
  RefreshCw,
  TrendingUp,
  X,
} from "lucide-react";
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
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
import { cn } from "@/lib/utils";

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
type DateSelectionMode = "single" | "range";
type DatePickerTarget = "single" | "from" | "to";
type DatePickerState = {
  target: DatePickerTarget;
  value: string;
} | null;

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
    sourceLabel: "Source",
    singleDay: "Single day",
    dateRange: "Date range",
    fromDate: "From",
    toDate: "To",
    chooseDate: "Choose date",
    previousMonth: "Previous month",
    nextMonth: "Next month",
    closeCalendar: "Close calendar",
    weekdaysShort: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"],
    refresh: "Refresh",
    sync: "Sync",
    openSyncPanel: "Open sync controls",
    closeSyncPanel: "Close sync controls",
    forceSyncNow: "Force sync now",
    forceSyncingNow: "Syncing...",
    syncRequestFailed: "Sync request failed",
    dashboardRequestFailed: "Dashboard request failed",
    sales: "Sales",
    paymentRowsRead: (count: string) => `${count} payment rows read`,
    receipts: "Receipts",
    paymentAllocations: (count: string) => `${count} payment allocations`,
    salesDays: "Sales Days",
    syncedDaysInWindow: "Days with sales in this window",
    averageDailySales: "Avg. Daily Sales",
    acrossSyncedDays: "Across synced sales days",
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
    manualSync: "Manual Sync",
    selectedSource: "Selected Source",
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
    sourceLabel: "来源",
    singleDay: "单日",
    dateRange: "日期范围",
    fromDate: "开始",
    toDate: "结束",
    chooseDate: "选择日期",
    previousMonth: "上个月",
    nextMonth: "下个月",
    closeCalendar: "关闭日历",
    weekdaysShort: ["日", "一", "二", "三", "四", "五", "六"],
    refresh: "刷新",
    sync: "同步",
    openSyncPanel: "打开同步控制",
    closeSyncPanel: "关闭同步控制",
    forceSyncNow: "立即强制同步",
    forceSyncingNow: "同步中...",
    syncRequestFailed: "同步请求失败",
    dashboardRequestFailed: "仪表盘请求失败",
    sales: "销售额",
    paymentRowsRead: (count: string) => `已读取 ${count} 条付款记录`,
    receipts: "收据",
    paymentAllocations: (count: string) => `${count} 笔付款分配`,
    salesDays: "销售天数",
    syncedDaysInWindow: "此窗口内有销售的天数",
    averageDailySales: "日均销售额",
    acrossSyncedDays: "按已同步销售日计算",
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
    manualSync: "手动同步",
    selectedSource: "所选来源",
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
    sourceLabel: string;
    singleDay: string;
    dateRange: string;
    fromDate: string;
    toDate: string;
    chooseDate: string;
    previousMonth: string;
    nextMonth: string;
    closeCalendar: string;
    weekdaysShort: string[];
    refresh: string;
    sync: string;
    openSyncPanel: string;
    closeSyncPanel: string;
    forceSyncNow: string;
    forceSyncingNow: string;
    syncRequestFailed: string;
    dashboardRequestFailed: string;
    sales: string;
    paymentRowsRead: (count: string) => string;
    receipts: string;
    paymentAllocations: (count: string) => string;
    salesDays: string;
    syncedDaysInWindow: string;
    averageDailySales: string;
    acrossSyncedDays: string;
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
    manualSync: string;
    selectedSource: string;
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

type Translation = (typeof translations)[Language];

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

function parseIsoDate(value: string) {
  const [year, month, day] = value.split("-").map(Number);
  return new Date(year, month - 1, day);
}

function formatIsoDate(date: Date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function addMonths(date: Date, months: number) {
  return new Date(date.getFullYear(), date.getMonth() + months, 1);
}

function formatDisplayDate(value: string, locale: string) {
  return new Intl.DateTimeFormat(locale, { dateStyle: "medium" }).format(parseIsoDate(value));
}

function formatMonthYear(date: Date, locale: string) {
  return new Intl.DateTimeFormat(locale, { month: "long", year: "numeric" }).format(date);
}

function formatChartDateLabel(value: string, view: SalesChartView, locale: string) {
  if (view === "monthly") {
    const [year, month] = value.split("-").map(Number);
    return new Intl.DateTimeFormat(locale, { month: "short", year: "numeric" }).format(new Date(year, month - 1, 1));
  }

  return new Intl.DateTimeFormat(locale, { month: "short", day: "numeric" }).format(parseIsoDate(value));
}

function getCalendarDays(monthDate: Date) {
  const firstOfMonth = new Date(monthDate.getFullYear(), monthDate.getMonth(), 1);
  const calendarStart = new Date(firstOfMonth);
  calendarStart.setDate(firstOfMonth.getDate() - firstOfMonth.getDay());

  return Array.from({ length: 42 }, (_, index) => {
    const date = new Date(calendarStart);
    date.setDate(calendarStart.getDate() + index);
    return {
      iso: formatIsoDate(date),
      day: date.getDate(),
      isOutsideMonth: date.getMonth() !== monthDate.getMonth(),
    };
  });
}

function App() {
  const defaultDate = useMemo(() => yesterdayIso(), []);
  const [language, setLanguage] = useState<Language>(() => getInitialLanguage());
  const [fromDate, setFromDate] = useState(defaultDate);
  const [toDate, setToDate] = useState(defaultDate);
  const [dateMode, setDateMode] = useState<DateSelectionMode>("single");
  const [datePicker, setDatePicker] = useState<DatePickerState>(null);
  const [source, setSource] = useState("all");
  const [salesChartView, setSalesChartView] = useState<SalesChartView>("daily");
  const [isSyncPanelOpen, setIsSyncPanelOpen] = useState(false);
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

  function showSingleDayMode() {
    setDateMode("single");
    setToDate(fromDate);
  }

  function showDateRangeMode() {
    setDateMode("range");
  }

  function openDatePicker(target: DatePickerTarget) {
    setDatePicker({
      target,
      value: target === "to" ? toDate : fromDate,
    });
  }

  function handleDateSelected(value: string) {
    if (!datePicker) return;

    if (datePicker.target === "single") {
      setDateMode("single");
      setFromDate(value);
      setToDate(value);
    }
    else if (datePicker.target === "from") {
      setFromDate(value);
      if (value > toDate) {
        setToDate(value);
      }
    }
    else {
      setToDate(value);
      if (value < fromDate) {
        setFromDate(value);
      }
    }

    setDatePicker(null);
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
  const syncedSalesDayCount = dailySalesChartData.length;
  const averageDailySales =
    syncedSalesDayCount > 0 ? Number(state.summary?.total_amount ?? 0) / syncedSalesDayCount : 0;
  const monthlySalesChartData = Array.from(
    dailySalesChartData.reduce((months, day) => {
      const month = day.date.slice(0, 7);
      months.set(month, (months.get(month) ?? 0) + day.total);
      return months;
    }, new Map<string, number>()),
    ([date, total]) => ({ date, total }),
  ).sort((first, second) => first.date.localeCompare(second.date));
  const salesChartData = salesChartView === "daily" ? dailySalesChartData : monthlySalesChartData;
  const salesChartWidth = Math.max(720, salesChartData.length * (salesChartView === "daily" ? 76 : 120));
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

          <div className="w-full space-y-3 lg:max-w-5xl">
            <div className="grid gap-3 sm:grid-cols-[auto_minmax(160px,220px)] lg:justify-end">
              <div className="grid grid-cols-2 rounded-md border border-input bg-background p-1">
                <Button
                  type="button"
                  size="sm"
                  variant={dateMode === "single" ? "secondary" : "ghost"}
                  className="h-9"
                  data-testid="date-mode-single"
                  aria-pressed={dateMode === "single"}
                  onClick={showSingleDayMode}
                >
                  {t.singleDay}
                </Button>
                <Button
                  type="button"
                  size="sm"
                  variant={dateMode === "range" ? "secondary" : "ghost"}
                  className="h-9"
                  data-testid="date-mode-range"
                  aria-pressed={dateMode === "range"}
                  onClick={showDateRangeMode}
                >
                  {t.dateRange}
                </Button>
              </div>
              <label className="grid gap-1.5">
                <span className="text-xs font-medium text-muted-foreground">{t.sourceLabel}</span>
                <select
                  className="h-10 rounded-md border border-input bg-background px-3 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
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
              </label>
            </div>

            <div
              className={cn(
                "grid gap-3",
                dateMode === "single"
                  ? "sm:grid-cols-[minmax(180px,1fr)_auto_auto_auto]"
                  : "sm:grid-cols-2 xl:grid-cols-[minmax(160px,1fr)_minmax(160px,1fr)_auto_auto_auto]",
              )}
            >
              {dateMode === "single" ? (
                <DateFieldButton
                  label={t.singleDay}
                  value={fromDate}
                  locale={locale}
                  testId="date-field-single"
                  onClick={() => openDatePicker("single")}
                />
              ) : (
                <>
                  <DateFieldButton
                    label={t.fromDate}
                    value={fromDate}
                    locale={locale}
                    testId="date-field-from"
                    onClick={() => openDatePicker("from")}
                  />
                  <DateFieldButton
                    label={t.toDate}
                    value={toDate}
                    locale={locale}
                    testId="date-field-to"
                    onClick={() => openDatePicker("to")}
                  />
                </>
              )}
              <Button className="h-11 w-full" variant="secondary" onClick={loadDashboard} disabled={isLoading || isSyncing}>
                <RefreshCw className={`mr-2 h-4 w-4 ${isLoading ? "animate-spin" : ""}`} />
                {t.refresh}
              </Button>
              <Button
                className="h-11 w-full"
                type="button"
                variant="outline"
                onClick={() => setIsSyncPanelOpen(true)}
                aria-label={t.openSyncPanel}
              >
                <RefreshCw className={`mr-2 h-4 w-4 ${isSyncing ? "animate-spin" : ""}`} />
                {t.sync}
              </Button>
              <Button
                className="h-11 w-full"
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
          </div>
        </header>

        <DatePickerModal
          labels={t}
          locale={locale}
          onClose={() => setDatePicker(null)}
          onSelect={handleDateSelected}
          value={datePicker?.value ?? fromDate}
          targetLabel={
            datePicker?.target === "from"
              ? t.fromDate
              : datePicker?.target === "to"
                ? t.toDate
                : t.singleDay
          }
          open={Boolean(datePicker)}
        />

        <SyncPanelModal
          labels={t}
          locale={locale}
          onClose={() => setIsSyncPanelOpen(false)}
          onRunSync={handleForceSyncNow}
          open={isSyncPanelOpen}
          isLoading={isLoading}
          isSyncing={isSyncing}
          lastSync={lastSync}
          selectedSource={source}
          syncRuns={state.syncRuns}
        />

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
            title={t.salesDays}
            value={formatNumber(syncedSalesDayCount, locale)}
            icon={<CalendarDays className="h-4 w-4" />}
            muted={t.syncedDaysInWindow}
          />
          <MetricCard
            title={t.averageDailySales}
            value={formatCurrency(averageDailySales, currency, locale)}
            icon={<TrendingUp className="h-4 w-4" />}
            muted={t.acrossSyncedDays}
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
            <div className="h-72 overflow-x-auto overflow-y-hidden pb-2" data-testid="sales-chart-scroll">
              {salesChartData.length === 0 ? (
                <div className="flex h-full items-center justify-center rounded-md border border-dashed border-border text-sm text-muted-foreground">
                  {emptySalesChartLabel}
                </div>
              ) : (
                <div className="h-full min-w-full" style={{ width: `${salesChartWidth}px` }}>
                  <ResponsiveContainer width="100%" height="100%">
                    <BarChart data={salesChartData} margin={{ top: 10, right: 12, left: 0, bottom: 34 }}>
                      <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
                      <XAxis
                        dataKey="date"
                        tick={{ fill: "hsl(var(--muted-foreground))", fontSize: 12 }}
                        tickFormatter={(value) => formatChartDateLabel(String(value), salesChartView, locale)}
                        interval={0}
                        minTickGap={12}
                        angle={-35}
                        textAnchor="end"
                        height={62}
                        tickMargin={12}
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
                </div>
              )}
            </div>
          </CardContent>
        </Card>

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

function DateFieldButton({
  label,
  value,
  locale,
  testId,
  onClick,
}: {
  label: string;
  value: string;
  locale: string;
  testId: string;
  onClick: () => void;
}) {
  const displayDate = formatDisplayDate(value, locale);

  return (
    <button
      type="button"
      data-testid={testId}
      aria-label={`${label}: ${displayDate}`}
      className="flex h-11 w-full items-center justify-between gap-3 rounded-md border border-input bg-background px-3 text-left text-sm shadow-sm transition-colors hover:bg-accent hover:text-accent-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
      onClick={onClick}
    >
      <span className="min-w-0">
        <span className="block text-xs font-medium text-muted-foreground">{label}</span>
        <span className="block truncate font-medium">{displayDate}</span>
      </span>
      <CalendarDays className="h-4 w-4 shrink-0 text-muted-foreground" />
    </button>
  );
}

function SyncPanelModal({
  labels,
  locale,
  onClose,
  onRunSync,
  open,
  isLoading,
  isSyncing,
  lastSync,
  selectedSource,
  syncRuns,
}: {
  labels: Translation;
  locale: string;
  onClose: () => void;
  onRunSync: () => void | Promise<void>;
  open: boolean;
  isLoading: boolean;
  isSyncing: boolean;
  lastSync: SyncRun | null;
  selectedSource: string;
  syncRuns: SyncRun[];
}) {
  const selectedSourceLabel = selectedSource === "all" ? labels.allSources : selectedSource;

  useEffect(() => {
    if (!open) return;

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        onClose();
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [onClose, open]);

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-foreground/30 p-0 sm:items-center sm:p-4" role="presentation">
      <button className="absolute inset-0 cursor-default" type="button" aria-hidden="true" tabIndex={-1} onClick={onClose} />
      <div
        className="relative max-h-[calc(100vh-2rem)] w-full overflow-y-auto rounded-t-lg border border-border bg-card p-4 text-card-foreground shadow-lg sm:max-w-lg sm:rounded-lg sm:p-5"
        role="dialog"
        aria-modal="true"
        aria-label={labels.syncStatus}
      >
        <div className="mb-4 flex items-start justify-between gap-3">
          <div>
            <p className="text-xs font-medium uppercase tracking-normal text-muted-foreground">{labels.syncStatus}</p>
            <h2 className="mt-1 text-lg font-semibold">{labels.sync}</h2>
          </div>
          <Button type="button" variant="ghost" size="icon" aria-label={labels.closeSyncPanel} onClick={onClose}>
            <X className="h-4 w-4" />
          </Button>
        </div>

        <div className="grid gap-3 sm:grid-cols-2">
          <div className="rounded-md border border-border p-3">
            <div className="flex items-center justify-between gap-3">
              <div className="flex min-w-0 items-center gap-2">
                <span className="text-muted-foreground">
                  {lastSync?.status === "success" ? <CheckCircle2 className="h-4 w-4" /> : <AlertTriangle className="h-4 w-4" />}
                </span>
                <div className="min-w-0">
                  <p className="text-xs font-medium text-muted-foreground">{labels.lastSync}</p>
                  <p className="truncate text-sm font-semibold">
                    {lastSync ? translatedStatus(lastSync.status, labels) ?? lastSync.status : labels.noRuns}
                  </p>
                </div>
              </div>
              {lastSync?.status ? <Badge variant={statusVariant(lastSync.status)}>{translatedStatus(lastSync.status, labels)}</Badge> : null}
            </div>
            <p className="mt-3 text-xs text-muted-foreground">
              {formatDateTime(lastSync?.finished_at ?? lastSync?.started_at, locale, labels.never)}
            </p>
          </div>

          <div className="rounded-md border border-border p-3">
            <p className="text-xs font-medium text-muted-foreground">{labels.manualSync}</p>
            <p className="mt-2 text-xs font-medium text-muted-foreground">{labels.selectedSource}</p>
            <p className="mt-1 truncate text-sm font-semibold">{selectedSourceLabel}</p>
            <Button className="mt-3 w-full" type="button" onClick={onRunSync} disabled={isSyncing || isLoading}>
              <RefreshCw className={`mr-2 h-4 w-4 ${isSyncing ? "animate-spin" : ""}`} />
              {isSyncing ? labels.forceSyncingNow : labels.forceSyncNow}
            </Button>
          </div>
        </div>

        <div className="mt-5">
          <h3 className="text-sm font-semibold">{labels.mostRecentRuns}</h3>
          <div className="mt-3 space-y-2">
            {syncRuns.length === 0 ? (
              <p className="rounded-md border border-dashed border-border p-4 text-sm text-muted-foreground">{labels.noSyncRuns}</p>
            ) : (
              syncRuns.slice(0, 5).map((run) => (
                <div key={run.id} className="flex items-center justify-between gap-3 rounded-md border border-border p-3">
                  <div className="min-w-0">
                    <div className="truncate text-sm font-medium">
                      {run.source_name} · {run.business_date}
                    </div>
                    <div className="text-xs text-muted-foreground">
                      {labels.syncRows(formatNumber(run.rows_matched, locale), formatNumber(run.rows_read, locale))}
                    </div>
                    <div className="text-xs text-muted-foreground">
                      {formatDateTime(run.finished_at ?? run.started_at, locale, labels.never)}
                    </div>
                  </div>
                  <Badge variant={statusVariant(run.status)}>{translatedStatus(run.status, labels)}</Badge>
                </div>
              ))
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

function DatePickerModal({
  labels,
  locale,
  onClose,
  onSelect,
  open,
  targetLabel,
  value,
}: {
  labels: Translation;
  locale: string;
  onClose: () => void;
  onSelect: (value: string) => void;
  open: boolean;
  targetLabel: string;
  value: string;
}) {
  const [visibleMonth, setVisibleMonth] = useState(() => parseIsoDate(value));
  const selectedIso = value;
  const todayIso = formatIsoDate(new Date());
  const calendarDays = getCalendarDays(visibleMonth);

  useEffect(() => {
    if (open) {
      setVisibleMonth(parseIsoDate(value));
    }
  }, [open, value]);

  useEffect(() => {
    if (!open) return;

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        onClose();
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [onClose, open]);

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-foreground/30 p-0 sm:items-center sm:p-4" role="presentation">
      <button className="absolute inset-0 cursor-default" type="button" aria-hidden="true" tabIndex={-1} onClick={onClose} />
      <div
        className="relative w-full rounded-t-lg border border-border bg-card p-4 text-card-foreground shadow-lg sm:max-w-sm sm:rounded-lg"
        role="dialog"
        aria-modal="true"
        aria-label={`${labels.chooseDate}: ${targetLabel}`}
      >
        <div className="mb-4 flex items-center justify-between gap-3">
          <div>
            <p className="text-xs font-medium text-muted-foreground">{targetLabel}</p>
            <h2 className="text-base font-semibold">{formatMonthYear(visibleMonth, locale)}</h2>
          </div>
          <div className="flex items-center gap-1">
            <Button
              type="button"
              variant="ghost"
              size="icon"
              aria-label={labels.previousMonth}
              onClick={() => setVisibleMonth((current) => addMonths(current, -1))}
            >
              <ChevronLeft className="h-4 w-4" />
            </Button>
            <Button
              type="button"
              variant="ghost"
              size="icon"
              aria-label={labels.nextMonth}
              onClick={() => setVisibleMonth((current) => addMonths(current, 1))}
            >
              <ChevronRight className="h-4 w-4" />
            </Button>
            <Button type="button" variant="ghost" size="icon" aria-label={labels.closeCalendar} onClick={onClose}>
              <X className="h-4 w-4" />
            </Button>
          </div>
        </div>

        <div className="grid grid-cols-7 gap-1">
          {labels.weekdaysShort.map((weekday) => (
            <div key={weekday} className="flex h-8 items-center justify-center text-xs font-medium text-muted-foreground">
              {weekday}
            </div>
          ))}
          {calendarDays.map((day) => {
            const isSelected = day.iso === selectedIso;
            const isToday = day.iso === todayIso;

            return (
              <button
                key={day.iso}
                type="button"
                data-date={day.iso}
                className={cn(
                  "flex aspect-square min-h-10 items-center justify-center rounded-md border text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring",
                  isSelected
                    ? "border-primary bg-primary text-primary-foreground"
                    : "border-transparent hover:border-input hover:bg-accent hover:text-accent-foreground",
                  day.isOutsideMonth && !isSelected ? "text-muted-foreground/50" : "",
                  isToday && !isSelected ? "border-primary/60 text-primary" : "",
                )}
                aria-pressed={isSelected}
                onClick={() => onSelect(day.iso)}
              >
                {day.day}
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}

export default App;
