import logging
import os

import asyncpg
import structlog
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException
from prometheus_fastapi_instrumentator import Instrumentator
import random


structlog.configure(
    processors=[
        structlog.contextvars.merge_contextvars,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer(),
    ],
    wrapper_class=structlog.make_filtering_bound_logger(logging.INFO),
    context_class=dict,
    logger_factory=structlog.PrintLoggerFactory(),
)

log = structlog.get_logger()

DB_DSN = os.getenv("DATABASE_URL", "postgresql://health:health@postgres:5432/health")


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.pool = await asyncpg.create_pool(DB_DSN, min_size=1, max_size=5)
    log.info("database_pool_created")
    yield
    await app.state.pool.close()
    log.info("database_pool_closed")


app = FastAPI(title="Region Health API", lifespan=lifespan)
Instrumentator().instrument(app).expose(app)


@app.get("/health")
async def health():
    try:
        async with app.state.pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
        log.info("health_check", status="ok")
        return {"status": "ok", "database": "connected"}
    except Exception as exc:
        log.error("health_check_failed", error=str(exc))
        raise HTTPException(
            status_code=503,
            detail={"status": "degraded", "database": "unreachable"},
        )


@app.get("/incidents")
async def list_incidents():
    async with app.state.pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT id, region, severity, title, started_at, resolved_at
            FROM incidents
            ORDER BY started_at DESC
            LIMIT 50
            """
        )
    result = [dict(r) for r in rows]
    log.info("incidents_fetched", count=len(result))
    return {"incidents": result}


@app.get("/error")
async def trigger_error():
    if random.random() < 0.5:
        log.error("Deliberate test error triggered")
        raise HTTPException(status_code=500, detail="Deliberate test error")
    return {"status": "ok"}