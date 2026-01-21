# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

AmakaFlow is a microservices monorepo with Supabase as the single source of truth. All services read/write to a shared PostgreSQL database with Clerk handling authentication and Supabase RLS handling authorization.

```
┌─────────────────────────────────────────────┐
│         amakaflow-db (DB Migrations)        │
│     (Schema, migrations, edge functions)    │
└─────────────────────────────────────────────┘
                      │
                      ▼
              Supabase Database
                      │
    ┌─────────────────┼─────────────────┐
    │                 │                 │
    ▼                 ▼                 ▼
 amakaflow-ui     mapper-api     workout-ingestor-api
 (React, :3000)   (FastAPI, :8001)  (FastAPI, :8004)
                      │
    ┌─────────────────┼─────────────────┐
    │                 │                 │
    ▼                 ▼                 ▼
 strava-sync      calendar-api    garmin-sync-api
 (:8000)          (:8003)         (:8002, optional)
```

## Build & Run Commands

### Docker Compose (Primary Development Method)
```bash
docker-compose up -d                    # Start core services
docker-compose --profile full up -d     # Include optional Garmin services
docker-compose logs -f [service]        # View logs
docker-compose down                     # Stop all
```

### UI (amakaflow-ui)
```bash
cd amakaflow-ui
npm install
npm run dev           # Development server on :3000
npm run build         # Production build
npm test              # Vitest watch mode
npm run test:run      # Single test run
npm run test:coverage # With coverage
```

### Python APIs (mapper-api, workout-ingestor-api, etc.)
```bash
cd mapper-api
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
pytest                              # Run all tests
pytest -m unit                      # Unit tests only
pytest -m "not e2e"                 # All except e2e
pytest --cov=backend --cov=shared   # With coverage
npm run test:watch                  # Watch mode (mapper-api)
```

### Database Migrations (amakaflow-db)
```bash
npx supabase link --project-ref wdeqaibnwjekcyfpuple  # One-time setup
npx supabase migration new feature_name               # Create migration
npx supabase db push                                  # Apply to production
npx supabase db diff                                  # Check pending changes
npx supabase db reset                                 # Reset local
```

## Service Details

| Service | Tech | Port | Purpose |
|---------|------|------|---------|
| amakaflow-ui | React + Vite + TypeScript | 3000 | Frontend with Clerk auth, Radix UI |
| mapper-api | FastAPI | 8001 | Exercise mapping, workout format conversion (FIT/ZWO/Apple) |
| workout-ingestor-api | FastAPI | 8004 | Parse Instagram/YouTube workouts via OCR + vision models |
| calendar-api | FastAPI | 8003 | Workout calendar event CRUD |
| strava-sync-api | FastAPI | 8000 | Strava OAuth integration |
| garmin-sync-api | FastAPI | 8002 | Garmin Connect sync (optional, feature-flagged) |
| amakaflow-fitfiletool | Python package | - | Shared FIT file generation library |

## Key Patterns

### FastAPI App Factory (mapper-api)
- Entry point: `backend.main.create_app()`
- Settings: `backend.settings.Settings` (Pydantic BaseSettings)
- Routers: `api.routers/` (health, mapping, exports, workouts, pairing, completions)

### Test Markers (pytest)
```python
@pytest.mark.unit         # Fast, isolated tests
@pytest.mark.golden       # Snapshot tests for export output
@pytest.mark.integration  # FastAPI TestClient with fakes
@pytest.mark.contract     # API response shape validation
@pytest.mark.e2e          # Real services (nightly only)
```

### Shared Library
`amakaflow-fitfiletool` is installed as an editable package in mapper-api and workout-ingestor-api via Docker volume mounts.

## Database Schema (Core Tables)

- `profiles` - User accounts (Clerk ID linked)
- `linked_accounts` - OAuth connections (Strava, Garmin)
- `workouts` - Standard workouts from workflow
- `follow_along_workouts` - Video-based workouts (Instagram/YouTube)
- `follow_along_steps` - Individual steps in follow-along workouts
- `workout_completions` - Completion history tracking
- `workout_events` - Calendar events

### Migration Best Practices
Use `IF NOT EXISTS` for idempotency. Always enable RLS and add policies for new tables. Avoid destructive operations without careful planning.

## Environment Variables

Root `.env` contains all shared config. Key variables:
- `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`
- `CLERK_PUBLISHABLE_KEY`, `CLERK_SECRET_KEY`, `CLERK_DOMAIN`
- `SENTRY_DSN_API`, `SENTRY_DSN_UI`
- `OPENAI_API_KEY` (for workout-ingestor vision models)
- `GARMIN_UNOFFICIAL_SYNC_ENABLED` (feature flag, defaults to false)
