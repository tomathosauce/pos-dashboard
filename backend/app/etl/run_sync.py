import argparse
from datetime import date, timedelta

from app.core.config import settings
from app.db.session import SessionLocal
from app.services.sync_service import SyncService


def main() -> None:
    parser = argparse.ArgumentParser(description="Run Paradox POS daily aggregate sync.")
    parser.add_argument("--date", dest="business_date", default=None, help="Business date as YYYY-MM-DD")
    parser.add_argument("--source", default="all", help="Configured source name or 'all'")
    args = parser.parse_args()

    business_date = date.fromisoformat(args.business_date) if args.business_date else date.today() - timedelta(days=1)
    sources = settings.pos_sources if args.source == "all" else [settings.get_source(args.source)]
    service = SyncService()

    with SessionLocal() as db:
        for source in sources:
            run = service.sync_day(db, source, business_date)
            print(f"{source.name} {business_date} {run.status} rows={run.rows_read} matched={run.rows_matched}")
            if run.error_text:
                print(run.error_text)


if __name__ == "__main__":
    main()

