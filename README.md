# Daily POS Dashboard

Prototype dashboard for aggregate-only daily POS reporting from Paradox/BDE tables.

## Shape

- `backend/`: FastAPI API, PostgreSQL models, Alembic migrations, daily sync job.
- `frontend/`: React + Vite + Tailwind dashboard using shadcn-style UI primitives.
- `docker-compose.yml`: local/store-server services.

The dashboard reads PostgreSQL only. The POS Paradox folder is treated as a read-only source for the scheduled ETL.

## Quick Start

```bash
cd pos-dashboard
cp .env.example .env
docker compose up --build
```

Backend: <http://localhost:8000>  
Frontend: <http://localhost:5173>

## Live POS Sync

The Paradox/BDE ODBC driver is a Windows host dependency. A normal Linux Docker container will not be able to use the Windows BDE driver directly.

Recommended store-server setup:

1. Run PostgreSQL with Docker Compose, or use an existing PostgreSQL instance.
2. Run the FastAPI backend natively on the Windows/backoffice machine that has BDE/ODBC installed.
3. Install backend dependencies:

```powershell
cd pos-dashboard\backend
py -m venv .venv
.\.venv\Scripts\pip install -r requirements.txt
.\.venv\Scripts\pip install -r requirements-odbc.txt
```

4. Configure `.env` with `DATABASE_URL`, `POS_SOURCES_JSON`, and `ENABLE_SCHEDULER=true`.
5. Apply migrations and start the backend:

```powershell
.\.venv\Scripts\alembic upgrade head
.\.venv\Scripts\uvicorn app.main:app --host 127.0.0.1 --port 8000
```

The backend scheduler runs yesterday's calendar-day sync at 8:00am. You can also run a manual sync:

```powershell
.\.venv\Scripts\python -m app.etl.run_sync --date 2022-08-06 --source main
```

Expose the dashboard privately with Tailscale Serve or by accessing the store server over the tailnet. Do not expose the Paradox folder, PostgreSQL, or the backend API directly to the public internet.

## Reader Options

Each source in `POS_SOURCES_JSON` supports a `reader` field:

- `odbc`: recommended for the live Windows store server with BDE/ODBC installed.
- `pxlib`: optional direct Paradox reader using `pypxlib`; useful for Linux/offline prototypes and table copies.

Install pxlib support when needed:

```powershell
.\.venv\Scripts\pip install -r requirements-pxlib.txt
```

Example pxlib source:

```json
[{"name":"main","path":"D:/Downloads/lafelicidad/firestec","reader":"pxlib","timezone":"America/Bogota","currency":"USD"}]
```

The pxlib reader scans `tdocumentos_formas.DB` and filters by `FECHA` in Python. It is convenient, but ODBC remains the safer live POS option.
