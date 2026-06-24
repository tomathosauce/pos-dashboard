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

## Windows x86 Runtime Package

Live Paradox/BDE deployments often require a 32-bit process because the Paradox ODBC/BDE driver is only installed as 32-bit. For that setup, do not install normal system Python. Build and publish a self-contained x86 release package instead.

The release package contains:

- `backend/`
- prebuilt `frontend/dist/`
- a private Python 3.11 32-bit embeddable runtime under `runtime/python-x86/`
- Windows x86 Python dependencies, including `pyodbc` and `pg8000`
- `install-windows.ps1`, `update-windows.ps1`, `set-pos-source.ps1`, and `run-dashboard.ps1`

Build the package on a maintainer Windows machine with Node/npm available:

```powershell
cd pos-dashboard
.\scripts\build-windows-x86-package.ps1
```

Upload `release\pos-dashboard-windows-x86.zip` to a GitHub Release. The store/backoffice machine only needs Docker Desktop and the 32-bit Paradox ODBC/BDE driver installed; it does not need Node, npm, or system Python.

Fast target-machine install from the directory where the app should be installed:

```powershell
$env:POS_DASHBOARD_REPO = "your-org/pos-dashboard"

irm "https://raw.githubusercontent.com/${env:POS_DASHBOARD_REPO}/main/scripts/install-windows.ps1" | iex
```

For a private repo, provide a token only for that session:

```powershell
$env:GITHUB_TOKEN = "github_pat_..."
$env:POS_DASHBOARD_REPO = "your-org/pos-dashboard"

irm `
  -Headers @{ Authorization = "Bearer $env:GITHUB_TOKEN" } `
  "https://raw.githubusercontent.com/${env:POS_DASHBOARD_REPO}/main/scripts/install-windows.ps1" `
  | iex
```

By default, the installer uses the current directory as both:

- the install directory
- the POS source folder

Override those when needed:

```powershell
$env:POS_DASHBOARD_REPO = "your-org/pos-dashboard"
$env:POS_DASHBOARD_INSTALL_DIR = "C:\POSDashboard"
$env:POS_DASHBOARD_SOURCE_PATH = "C:\Path\To\Firestec"

irm "https://raw.githubusercontent.com/${env:POS_DASHBOARD_REPO}/main/scripts/install-windows.ps1" | iex
```

Avoid putting a PAT in the URL itself when using a private repo. Passing it through the `Authorization` header keeps it out of command history and most logs.

The installer:

- downloads the GitHub Release asset, using `GITHUB_TOKEN` only if one is provided
- extracts the self-contained app into the current directory unless `POS_DASHBOARD_INSTALL_DIR` or `-InstallDir` is provided
- creates or reuses a localhost-only `pos-dashboard-postgres` Docker container
- writes backend `.env` with `DATABASE_URL=postgresql+pg8000://...`
- validates the bundled Python runtime is 32-bit
- runs Alembic migrations
- registers a current-user Task Scheduler logon task

Installed dashboard URL:

```text
http://127.0.0.1:8000/
```

The built React app is served by FastAPI, so the installed dashboard runs as one Python process plus the PostgreSQL Docker container.

### Changing the POS source folder

From the installed dashboard directory:

```powershell
.\set-pos-source.ps1 "C:\Path\To\ParadoxFolder"
```

The helper updates both `install-config.json` and `backend\.env`, so future updates preserve the new folder. It also restarts the scheduled task by default.

Use an ODBC DSN when needed:

```powershell
.\set-pos-source.ps1 "C:\Path\To\ParadoxFolder" -OdbcDsn "FirestecParadox"
```

If you only want to update config without restarting:

```powershell
.\set-pos-source.ps1 "C:\Path\To\ParadoxFolder" -NoRestart
```

### Updating

After installation, update to the newest GitHub Release from the install directory:

```powershell
.\update-windows.ps1
```

Or run the latest updater script directly from GitHub:

```powershell
$env:POS_DASHBOARD_REPO = "your-org/pos-dashboard"
$env:POS_DASHBOARD_INSTALL_DIR = "C:\Path\To\Installed\Dashboard"

irm "https://raw.githubusercontent.com/${env:POS_DASHBOARD_REPO}/main/scripts/update-windows.ps1" | iex
```

For private update downloads, set `GITHUB_TOKEN` and pass the same header used by the installer:

```powershell
$env:GITHUB_TOKEN = "github_pat_..."
$env:POS_DASHBOARD_REPO = "your-org/pos-dashboard"

irm `
  -Headers @{ Authorization = "Bearer $env:GITHUB_TOKEN" } `
  "https://raw.githubusercontent.com/${env:POS_DASHBOARD_REPO}/main/scripts/update-windows.ps1" `
  | iex
```

To update from a specific release tag:

```powershell
.\update-windows.ps1 -ReleaseTag "v0.2.0"
```

To update from a specific branch or commit ref, the ref must contain a prebuilt package layout with `runtime/python-x86/` and `frontend/dist/`:

```powershell
.\update-windows.ps1 -Ref "main"
.\update-windows.ps1 -Ref "abc1234"
```

Release updates are the recommended path because release assets contain the built React frontend and bundled 32-bit Python runtime.
