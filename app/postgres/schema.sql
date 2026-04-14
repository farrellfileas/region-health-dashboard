CREATE TABLE IF NOT EXISTS incidents (
    id          SERIAL PRIMARY KEY,
    region      VARCHAR(64)  NOT NULL,
    severity    VARCHAR(4)   NOT NULL CHECK (severity IN ('P1', 'P2', 'P3', 'P4')),
    title       TEXT         NOT NULL,
    started_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    resolved_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_incidents_started_at ON incidents (started_at DESC);
CREATE INDEX IF NOT EXISTS idx_incidents_region     ON incidents (region);
