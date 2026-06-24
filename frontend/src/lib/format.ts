export function yesterdayIso() {
  const date = new Date();
  date.setDate(date.getDate() - 1);
  return date.toISOString().slice(0, 10);
}

export function formatCurrency(value: string | number, currency = "USD", locale = "en-US") {
  const numericValue = typeof value === "string" ? Number(value) : value;
  return new Intl.NumberFormat(locale, {
    style: "currency",
    currency,
    maximumFractionDigits: 2,
  }).format(Number.isFinite(numericValue) ? numericValue : 0);
}

export function formatNumber(value: string | number, locale = "en-US") {
  const numericValue = typeof value === "string" ? Number(value) : value;
  return new Intl.NumberFormat(locale).format(Number.isFinite(numericValue) ? numericValue : 0);
}

export function formatDateTime(value?: string | null, locale = "en-US", fallback = "Never") {
  if (!value) return fallback;
  return new Intl.DateTimeFormat(locale, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}
