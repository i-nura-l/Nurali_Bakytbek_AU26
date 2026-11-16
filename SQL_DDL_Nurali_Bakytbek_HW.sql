-- Physical database for my Subway Metro System model


-- 1. Database and schema

-- PostgreSQL has no CREATE DATABASE IF NOT EXISTS, so I keep it as a comment, otherwise the second run of the script would fail.

-- CREATE DATABASE subway_metro;

-- After that I connect to subway_metro and run everything below.

CREATE SCHEMA IF NOT EXISTS metro;

-- 2. Tables

/*
    Why the order is important: a foreign key can reference only a table that already exists. So first I create parent tables (line, station, train_model, ticket_type, employee) and then the child tables. If I create for example line_station before line, I get ERROR: relation "metro.line" does not exist, and the table is not created.

    What happens if FK is missing: the column becomes just a number. I could insert a train with train_model_id = 999 that does not exist, or delete a station that still has tickets and stops. These "orphan" rows are lost in joins and reports show wrong numbers without any error.

    Data types and risks of a wrong type: dates are DATE, not VARCHAR. In text somebody can write '31.02.2026' or 'tomorrow', sorting works like text and I cannot calculate difference between dates. price is NUMERIC(9,2), not FLOAT. Float is not exact, so sum of prices can give small mistakes like 0.30000000004.capacity, length, speed are INTEGER. In text I could not use SUM or AVG, and SMALLINT is too small for length in metres (max 32767). names and codes are VARCHAR with a limit. If the limit is too small the real name does not fit. ticket_code is text because a number type would lose zeros at the start. description is TEXT because I do not know its length. Changed from logical model: TIMESTAMP to TIMESTAMPTZ. Normal timestamp does not keep the time zone, so the same moment can be saved differently from different computers and comparing two times can be wrong.
*/

-- ---------- parent tables (no foreign keys to other tables) ----------

CREATE TABLE IF NOT EXISTS metro.line (
    line_id      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    line_name    VARCHAR(100) NOT NULL UNIQUE,
    color        VARCHAR(50)  NOT NULL,
    opened_date  DATE NOT NULL,
    closed_date  DATE,
    -- date check: protects from typos like year 0205 or 1900
    CONSTRAINT chk_line_opened_date CHECK (opened_date > '2000-01-01'),
    -- a line cannot be closed before it was opened
    CONSTRAINT chk_line_dates CHECK (closed_date IS NULL OR closed_date >= opened_date)
);
-- UNIQUE on line_name: without it there can be two "Red Line" rows and nobody knows which one is correct. Also my inserts would make duplicates on every run.
-- NOT NULL a line without name or opening date has no meaning, and NULL values are skipped in joins and counts, so results would be wrong.

CREATE TABLE IF NOT EXISTS metro.station (
    station_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    station_name  VARCHAR(100) NOT NULL UNIQUE,
    address       VARCHAR(200),
    latitude      NUMERIC(9, 5),
    longitude     NUMERIC(9, 5),
    opened_date   DATE NOT NULL,
    closed_date   DATE,
    --  coordinates that do not exist
    CONSTRAINT chk_station_latitude  CHECK (latitude BETWEEN -90 AND 90),
    CONSTRAINT chk_station_longitude CHECK (longitude BETWEEN -180 AND 180),
    CONSTRAINT chk_station_opened_date CHECK (opened_date > '2000-01-01'),
    CONSTRAINT chk_station_dates CHECK (closed_date IS NULL OR closed_date >= opened_date)
);

CREATE TABLE IF NOT EXISTS metro.train_model (
    train_model_id  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    model_name      VARCHAR(100) NOT NULL UNIQUE,
    capacity        INTEGER NOT NULL,
    max_speed_kmh   INTEGER NOT NULL,
    -- Without the check a wrong row would break calculations of how many people we can carry.
    CONSTRAINT chk_train_model_capacity CHECK (capacity > 0),
    CONSTRAINT chk_train_model_speed    CHECK (max_speed_kmh > 0)
);

CREATE TABLE IF NOT EXISTS metro.ticket_type (
    ticket_type_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ticket_type_name  VARCHAR(50) NOT NULL UNIQUE,
    validity_hours    INTEGER NOT NULL,
    max_rides         INTEGER,   -- null = unlimited
    CONSTRAINT chk_ticket_type_hours CHECK (validity_hours > 0),
    CONSTRAINT chk_ticket_type_rides CHECK (max_rides > 0)
);

CREATE TABLE IF NOT EXISTS metro.employee (
    employee_id       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    supervisor_id     INTEGER REFERENCES metro.employee (employee_id),   -- null = the top boss
    full_name         VARCHAR(100) NOT NULL,
    job_title         VARCHAR(100) NOT NULL,
    email             VARCHAR(100) UNIQUE,   -- two people cannot have the same email
    hire_date         DATE NOT NULL,
    termination_date  DATE,
    -- employee cannot be his own supervisor
    CONSTRAINT chk_employee_supervisor CHECK (supervisor_id <> employee_id),
    CONSTRAINT chk_employee_hire_date CHECK (hire_date > '2000-01-01'),
    CONSTRAINT chk_employee_dates CHECK (termination_date IS NULL OR termination_date >= hire_date)
);

-- ---------- child tables ----------

-- many-to-many between line and station
CREATE TABLE IF NOT EXISTS metro.line_station (
    line_station_id  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    line_id          INTEGER NOT NULL REFERENCES metro.line (line_id),
    station_id       INTEGER NOT NULL REFERENCES metro.station (station_id),
    stop_order       INTEGER NOT NULL,
    valid_from       DATE NOT NULL,
    valid_to         DATE,
    -- the same station cannot be added to a line twice from the same date,
    -- and two stations cannot have the same position on the line
    CONSTRAINT uq_line_station_station UNIQUE (line_id, station_id, valid_from),
    CONSTRAINT uq_line_station_order   UNIQUE (line_id, stop_order, valid_from),
    CONSTRAINT chk_line_station_order  CHECK (stop_order > 0),
    CONSTRAINT chk_line_station_period CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS metro.track_segment (
    track_segment_id  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    from_station_id   INTEGER NOT NULL REFERENCES metro.station (station_id),
    to_station_id     INTEGER NOT NULL REFERENCES metro.station (station_id),
    length_m          INTEGER NOT NULL,
    -- generated column: database calculates it itself from length_m,
    -- so km and metres can never be different
    length_km         NUMERIC(8, 3) GENERATED ALWAYS AS (length_m / 1000.0) STORED,
    opened_date       DATE NOT NULL,
    closed_date       DATE,
    CONSTRAINT uq_track_segment UNIQUE (from_station_id, to_station_id, opened_date),
    CONSTRAINT chk_track_segment_stations CHECK (from_station_id < to_station_id),
    CONSTRAINT chk_track_segment_length CHECK (length_m > 0),
    CONSTRAINT chk_track_segment_opened_date CHECK (opened_date > '2000-01-01'),
    CONSTRAINT chk_track_segment_dates CHECK (closed_date IS NULL OR closed_date >= opened_date)
);

CREATE TABLE IF NOT EXISTS metro.train (
    train_id             INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    train_model_id       INTEGER NOT NULL REFERENCES metro.train_model (train_model_id),
    train_number         VARCHAR(50) NOT NULL UNIQUE,
    commissioned_date    DATE NOT NULL,
    decommissioned_date  DATE,
    CONSTRAINT chk_train_commissioned_date CHECK (commissioned_date > '2000-01-01'),
    CONSTRAINT chk_train_dates CHECK (decommissioned_date IS NULL OR decommissioned_date >= commissioned_date)
);

-- price history
CREATE TABLE IF NOT EXISTS metro.ticket_price (
    ticket_price_id  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ticket_type_id   INTEGER NOT NULL REFERENCES metro.ticket_type (ticket_type_id),
    price            NUMERIC(9, 2) NOT NULL,
    valid_from       DATE NOT NULL DEFAULT CURRENT_DATE,
    valid_to         DATE,
    CONSTRAINT uq_ticket_price UNIQUE (ticket_type_id, valid_from),
    -- measured value: price cannot be negative, otherwise we "pay" to the passenger
    -- and the revenue report is wrong. 0 is ok (free ticket).
    CONSTRAINT chk_ticket_price_price CHECK (price >= 0),
    CONSTRAINT chk_ticket_price_valid_from CHECK (valid_from > '2000-01-01'),
    CONSTRAINT chk_ticket_price_period CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

-- which line a train works on
CREATE TABLE IF NOT EXISTS metro.train_assignment (
    train_assignment_id  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    train_id             INTEGER NOT NULL REFERENCES metro.train (train_id),
    line_id              INTEGER NOT NULL REFERENCES metro.line (line_id),
    valid_from           DATE NOT NULL DEFAULT CURRENT_DATE,
    valid_to             DATE,
    CONSTRAINT uq_train_assignment UNIQUE (train_id, valid_from),
    CONSTRAINT chk_train_assignment_period CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

-- sold tickets
CREATE TABLE IF NOT EXISTS metro.ticket (
    ticket_id            INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ticket_code          VARCHAR(50) NOT NULL UNIQUE,   -- same code twice = two people on one ticket
    ticket_price_id      INTEGER NOT NULL REFERENCES metro.ticket_price (ticket_price_id),
    purchase_station_id  INTEGER REFERENCES metro.station (station_id),   -- null = bought online
    purchased_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    activated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_ticket_purchased_at CHECK (purchased_at > '2000-01-01'),
    -- ticket cannot start working before it was bought
    CONSTRAINT chk_ticket_activated_at CHECK (activated_at >= purchased_at)
);

-- maintenance order is for a train OR a station OR a track segment
CREATE TABLE IF NOT EXISTS metro.maintenance_order (
    maintenance_order_id  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    train_id              INTEGER REFERENCES metro.train (train_id),
    station_id            INTEGER REFERENCES metro.station (station_id),
    track_segment_id      INTEGER REFERENCES metro.track_segment (track_segment_id),
    maintenance_type      VARCHAR(50) NOT NULL,
    description           TEXT,
    planned_date          DATE NOT NULL,
    started_at            TIMESTAMPTZ,
    completed_at          TIMESTAMPTZ,
    status                VARCHAR(50) NOT NULL DEFAULT 'planned',
    -- exactly one of the three targets must be filled. Without this check an order can have no target (what to repair?) or two targets at the same time.
    CONSTRAINT chk_maintenance_order_target
        CHECK (num_nonnulls(train_id, station_id, track_segment_id) = 1),
    -- only specific values: without it people write 'done', 'Completed', 'finished' and a filter by status does not find all orders
    CONSTRAINT chk_maintenance_order_status
        CHECK (status IN ('planned', 'in_progress', 'completed', 'cancelled')),
    CONSTRAINT chk_maintenance_order_planned_date CHECK (planned_date > '2000-01-01'),
    -- work cannot be finished before it started
    CONSTRAINT chk_maintenance_order_times
        CHECK (completed_at IS NULL OR (started_at IS NOT NULL AND completed_at >= started_at))
);

-- timetable: a train (on its line) runs in a direction on a day type
CREATE TABLE IF NOT EXISTS metro.schedule (
    schedule_id          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    train_assignment_id  INTEGER NOT NULL REFERENCES metro.train_assignment (train_assignment_id),
    day_type             VARCHAR(10) NOT NULL,
    direction            VARCHAR(10) NOT NULL,
    valid_from           DATE NOT NULL DEFAULT CURRENT_DATE,
    valid_to             DATE,
    CONSTRAINT uq_schedule UNIQUE (train_assignment_id, day_type, direction, valid_from),
    -- only specific values, a typo like 'weekdy' would make a schedule that is never used
    CONSTRAINT chk_schedule_day_type  CHECK (day_type IN ('weekday', 'weekend', 'holiday')),
    CONSTRAINT chk_schedule_direction CHECK (direction IN ('forward', 'backward')),
    CONSTRAINT chk_schedule_period CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

-- many-to-many between maintenance_order and employee
CREATE TABLE IF NOT EXISTS metro.maintenance_assignment (
    maintenance_order_id  INTEGER NOT NULL REFERENCES metro.maintenance_order (maintenance_order_id),
    employee_id           INTEGER NOT NULL REFERENCES metro.employee (employee_id),
    assignment_role       VARCHAR(50) NOT NULL,
    PRIMARY KEY (maintenance_order_id, employee_id)
);

-- times at every stop of a schedule
CREATE TABLE IF NOT EXISTS metro.schedule_stop (
    schedule_id      INTEGER NOT NULL REFERENCES metro.schedule (schedule_id),
    line_station_id  INTEGER NOT NULL REFERENCES metro.line_station (line_station_id),
    arrival_time     TIME,
    departure_time   TIME,
    PRIMARY KEY (schedule_id, line_station_id),
    -- a stop without any time is useless
    CONSTRAINT chk_schedule_stop_time CHECK (arrival_time IS NOT NULL OR departure_time IS NOT NULL)
);


-- 3. Indexes

-- PK and UNIQUE already have indexes. I add indexes on foreign key columns that I use in joins.

CREATE INDEX IF NOT EXISTS idx_line_station_station_id ON metro.line_station (station_id);
CREATE INDEX IF NOT EXISTS idx_train_train_model_id ON metro.train (train_model_id);
CREATE INDEX IF NOT EXISTS idx_train_assignment_line_id ON metro.train_assignment (line_id);
CREATE INDEX IF NOT EXISTS idx_ticket_ticket_price_id ON metro.ticket (ticket_price_id);
CREATE INDEX IF NOT EXISTS idx_maintenance_order_train_id ON metro.maintenance_order (train_id);
CREATE INDEX IF NOT EXISTS idx_maintenance_assignment_employee_id ON metro.maintenance_assignment (employee_id);


-- 4. Sample data

/*
    How I keep the data consistent: I insert parents first and children after, same order as the tables. I never write ids by hand. Ids are generated by the database, and for every FK I find the parent id with a SELECT by its name / number / email. So the script works even if ids are different on another computer. If the parent is not found, the FK is NULL or the SELECT returns no rows, so a row with a wrong parent cannot be inserted (NOT NULL and FK stop it). ON CONFLICT DO NOTHING uses the UNIQUE constraints, so the second run does not create duplicates. For maintenance_order there is no unique column, so there I use WHERE NOT EXISTS.
*/

INSERT INTO metro.line (line_name, color, opened_date)
VALUES ('Red Line', 'red', '2005-09-01'),
       ('Blue Line', 'blue', '2012-05-15')
ON CONFLICT (line_name) DO NOTHING;

INSERT INTO metro.station (station_name, address, latitude, longitude, opened_date)
VALUES ('Central', '1 Central Square', 42.87460, 74.56980, '2005-09-01'),
       ('North Park', '25 Park Avenue', 42.89010, 74.57350, '2005-09-01'),
       ('Riverside', '8 River Embankment', 42.90520, 74.58110, '2007-03-20'),
       ('Airport', '100 Airport Road', 42.84130, 74.47760, '2012-05-15')
ON CONFLICT (station_name) DO NOTHING;

INSERT INTO metro.train_model (model_name, capacity, max_speed_kmh)
VALUES ('Metro-A 4-car', 800, 80),
       ('Metro-B 6-car', 1200, 90)
ON CONFLICT (model_name) DO NOTHING;

INSERT INTO metro.ticket_type (ticket_type_name, validity_hours, max_rides)
VALUES ('Single ride', 2, 1),
       ('Day pass', 24, NULL)
ON CONFLICT (ticket_type_name) DO NOTHING;

-- first the boss (no supervisor), then the others
INSERT INTO metro.employee (full_name, job_title, email, hire_date)
VALUES ('Aibek Asanov', 'Head of Maintenance', 'aibek.asanov@metro.example', '2010-02-01')
ON CONFLICT (email) DO NOTHING;

INSERT INTO metro.employee (supervisor_id, full_name, job_title, email, hire_date)
VALUES ((SELECT employee_id FROM metro.employee WHERE email = 'aibek.asanov@metro.example'),
        'Elena Kim', 'Rolling Stock Technician', 'elena.kim@metro.example', '2018-06-11'),
       ((SELECT employee_id FROM metro.employee WHERE email = 'aibek.asanov@metro.example'),
        'Marat Sadykov', 'Track Engineer', 'marat.sadykov@metro.example', '2021-09-01')
ON CONFLICT (email) DO NOTHING;

-- Red Line: Central -> North Park -> Riverside,  Blue Line: Central -> Airport
INSERT INTO metro.line_station (line_id, station_id, stop_order, valid_from)
VALUES ((SELECT line_id FROM metro.line WHERE line_name = 'Red Line'),
        (SELECT station_id FROM metro.station WHERE station_name = 'Central'), 1, '2005-09-01'),
       ((SELECT line_id FROM metro.line WHERE line_name = 'Red Line'),
        (SELECT station_id FROM metro.station WHERE station_name = 'North Park'), 2, '2005-09-01'),
       ((SELECT line_id FROM metro.line WHERE line_name = 'Red Line'),
        (SELECT station_id FROM metro.station WHERE station_name = 'Riverside'), 3, '2007-03-20'),
       ((SELECT line_id FROM metro.line WHERE line_name = 'Blue Line'),
        (SELECT station_id FROM metro.station WHERE station_name = 'Central'), 1, '2012-05-15'),
       ((SELECT line_id FROM metro.line WHERE line_name = 'Blue Line'),
        (SELECT station_id FROM metro.station WHERE station_name = 'Airport'), 2, '2012-05-15')
ON CONFLICT DO NOTHING;

-- LEAST / GREATEST because of the check from_station_id < to_station_id
INSERT INTO metro.track_segment (from_station_id, to_station_id, length_m, opened_date)
SELECT LEAST(a.station_id, b.station_id), GREATEST(a.station_id, b.station_id), 1850, DATE '2005-09-01'
FROM metro.station a
CROSS JOIN metro.station b
WHERE a.station_name = 'Central' AND b.station_name = 'North Park'
ON CONFLICT DO NOTHING;

INSERT INTO metro.track_segment (from_station_id, to_station_id, length_m, opened_date)
SELECT LEAST(a.station_id, b.station_id), GREATEST(a.station_id, b.station_id), 2100, DATE '2007-03-20'
FROM metro.station a
CROSS JOIN metro.station b
WHERE a.station_name = 'North Park' AND b.station_name = 'Riverside'
ON CONFLICT DO NOTHING;

INSERT INTO metro.track_segment (from_station_id, to_station_id, length_m, opened_date)
SELECT LEAST(a.station_id, b.station_id), GREATEST(a.station_id, b.station_id), 12400, DATE '2012-05-15'
FROM metro.station a
CROSS JOIN metro.station b
WHERE a.station_name = 'Central' AND b.station_name = 'Airport'
ON CONFLICT DO NOTHING;

INSERT INTO metro.train (train_model_id, train_number, commissioned_date)
VALUES ((SELECT train_model_id FROM metro.train_model WHERE model_name = 'Metro-A 4-car'), 'T-001', '2005-08-01'),
       ((SELECT train_model_id FROM metro.train_model WHERE model_name = 'Metro-A 4-car'), 'T-002', '2006-01-15'),
       ((SELECT train_model_id FROM metro.train_model WHERE model_name = 'Metro-B 6-car'), 'T-101', '2012-04-01')
ON CONFLICT (train_number) DO NOTHING;

-- Single ride has an old price and a new price (history)
INSERT INTO metro.ticket_price (ticket_type_id, price, valid_from, valid_to)
VALUES ((SELECT ticket_type_id FROM metro.ticket_type WHERE ticket_type_name = 'Single ride'), 20.00, '2024-01-01', '2025-12-31'),
       ((SELECT ticket_type_id FROM metro.ticket_type WHERE ticket_type_name = 'Single ride'), 25.00, '2026-01-01', NULL),
       ((SELECT ticket_type_id FROM metro.ticket_type WHERE ticket_type_name = 'Day pass'), 100.00, '2024-01-01', NULL)
ON CONFLICT (ticket_type_id, valid_from) DO NOTHING;

INSERT INTO metro.train_assignment (train_id, line_id, valid_from)
VALUES ((SELECT train_id FROM metro.train WHERE train_number = 'T-001'),
        (SELECT line_id FROM metro.line WHERE line_name = 'Red Line'), '2005-09-01'),
       ((SELECT train_id FROM metro.train WHERE train_number = 'T-002'),
        (SELECT line_id FROM metro.line WHERE line_name = 'Red Line'), '2006-02-01'),
       ((SELECT train_id FROM metro.train WHERE train_number = 'T-101'),
        (SELECT line_id FROM metro.line WHERE line_name = 'Blue Line'), '2012-05-15')
ON CONFLICT (train_id, valid_from) DO NOTHING;

-- the price is found by ticket type and by the date when the ticket was bought, so the ticket always gets the price that was valid on that day
INSERT INTO metro.ticket (ticket_code, ticket_price_id, purchase_station_id, purchased_at, activated_at)
SELECT 'TCK-000001', tp.ticket_price_id, s.station_id, '2025-06-10 08:15:00+06', '2025-06-10 08:20:00+06'
FROM metro.ticket_price tp
INNER JOIN metro.ticket_type tt ON tt.ticket_type_id = tp.ticket_type_id
CROSS JOIN metro.station s
WHERE tt.ticket_type_name = 'Single ride'
  AND DATE '2025-06-10' BETWEEN tp.valid_from AND COALESCE(tp.valid_to, CURRENT_DATE)
  AND s.station_name = 'Central'
ON CONFLICT (ticket_code) DO NOTHING;

INSERT INTO metro.ticket (ticket_code, ticket_price_id, purchase_station_id, purchased_at, activated_at)
SELECT 'TCK-000002', tp.ticket_price_id, s.station_id, '2026-03-02 17:40:00+06', '2026-03-02 17:42:00+06'
FROM metro.ticket_price tp
INNER JOIN metro.ticket_type tt ON tt.ticket_type_id = tp.ticket_type_id
CROSS JOIN metro.station s
WHERE tt.ticket_type_name = 'Single ride'
  AND DATE '2026-03-02' BETWEEN tp.valid_from AND COALESCE(tp.valid_to, CURRENT_DATE)
  AND s.station_name = 'Airport'
ON CONFLICT (ticket_code) DO NOTHING;

-- bought online, so no station
INSERT INTO metro.ticket (ticket_code, ticket_price_id, purchased_at, activated_at)
SELECT 'TCK-000003', tp.ticket_price_id, '2026-03-05 07:05:00+06', '2026-03-05 08:05:00+06'
FROM metro.ticket_price tp
INNER JOIN metro.ticket_type tt ON tt.ticket_type_id = tp.ticket_type_id
WHERE tt.ticket_type_name = 'Day pass'
  AND DATE '2026-03-05' BETWEEN tp.valid_from AND COALESCE(tp.valid_to, CURRENT_DATE)
ON CONFLICT (ticket_code) DO NOTHING;

-- maintenance_order has no unique column, so here I check with WHERE NOT EXISTS order for a train
INSERT INTO metro.maintenance_order (train_id, maintenance_type, description, planned_date, started_at, completed_at, status)
SELECT t.train_id, 'inspection', 'Scheduled brake inspection', DATE '2026-10-05',
       '2026-10-05 09:00:00+06', '2026-10-05 13:30:00+06', 'completed'
FROM metro.train t
WHERE t.train_number = 'T-001'
  AND NOT EXISTS (SELECT 1
                  FROM metro.maintenance_order mo
                  WHERE mo.train_id = t.train_id
                    AND mo.maintenance_type = 'inspection'
                    AND mo.planned_date = '2026-10-05');

-- order for a station
INSERT INTO metro.maintenance_order (station_id, maintenance_type, description, planned_date, started_at, status)
SELECT s.station_id, 'repair', 'Escalator 2 motor replacement', DATE '2026-11-10',
       '2026-11-10 23:30:00+06', 'in_progress'
FROM metro.station s
WHERE s.station_name = 'Central'
  AND NOT EXISTS (SELECT 1
                  FROM metro.maintenance_order mo
                  WHERE mo.station_id = s.station_id
                    AND mo.maintenance_type = 'repair'
                    AND mo.planned_date = '2026-11-10');

-- order for a track segment (Central - Airport). Status is not written, default 'planned' is used
INSERT INTO metro.maintenance_order (track_segment_id, maintenance_type, description, planned_date)
SELECT ts.track_segment_id, 'rail_grinding', 'Rail grinding on the airport part', DATE '2026-12-01'
FROM metro.track_segment ts
INNER JOIN metro.station a ON a.station_id = ts.from_station_id
INNER JOIN metro.station b ON b.station_id = ts.to_station_id
WHERE 'Central' IN (a.station_name, b.station_name)
  AND 'Airport' IN (a.station_name, b.station_name)
  AND NOT EXISTS (SELECT 1
                  FROM metro.maintenance_order mo
                  WHERE mo.track_segment_id = ts.track_segment_id
                    AND mo.maintenance_type = 'rail_grinding'
                    AND mo.planned_date = '2026-12-01');

-- schedules: I find the assignment by the train number
INSERT INTO metro.schedule (train_assignment_id, day_type, direction, valid_from)
SELECT ta.train_assignment_id, 'weekday', 'forward', DATE '2026-01-01'
FROM metro.train_assignment ta
INNER JOIN metro.train t ON t.train_id = ta.train_id
WHERE t.train_number = 'T-001' AND ta.valid_to IS NULL
ON CONFLICT DO NOTHING;

INSERT INTO metro.schedule (train_assignment_id, day_type, direction, valid_from)
SELECT ta.train_assignment_id, 'weekend', 'forward', DATE '2026-01-01'
FROM metro.train_assignment ta
INNER JOIN metro.train t ON t.train_id = ta.train_id
WHERE t.train_number = 'T-002' AND ta.valid_to IS NULL
ON CONFLICT DO NOTHING;

INSERT INTO metro.schedule (train_assignment_id, day_type, direction, valid_from)
SELECT ta.train_assignment_id, 'weekday', 'forward', DATE '2026-01-01'
FROM metro.train_assignment ta
INNER JOIN metro.train t ON t.train_id = ta.train_id
WHERE t.train_number = 'T-101' AND ta.valid_to IS NULL
ON CONFLICT DO NOTHING;

INSERT INTO metro.maintenance_assignment (maintenance_order_id, employee_id, assignment_role)
SELECT mo.maintenance_order_id, e.employee_id, 'technician'
FROM metro.maintenance_order mo
CROSS JOIN metro.employee e
WHERE mo.maintenance_type = 'inspection' AND mo.planned_date = '2026-10-05'
  AND e.email = 'elena.kim@metro.example'
ON CONFLICT DO NOTHING;

INSERT INTO metro.maintenance_assignment (maintenance_order_id, employee_id, assignment_role)
SELECT mo.maintenance_order_id, e.employee_id, 'supervisor'
FROM metro.maintenance_order mo
CROSS JOIN metro.employee e
WHERE mo.maintenance_type = 'inspection' AND mo.planned_date = '2026-10-05'
  AND e.email = 'aibek.asanov@metro.example'
ON CONFLICT DO NOTHING;

INSERT INTO metro.maintenance_assignment (maintenance_order_id, employee_id, assignment_role)
SELECT mo.maintenance_order_id, e.employee_id, 'technician'
FROM metro.maintenance_order mo
CROSS JOIN metro.employee e
WHERE mo.maintenance_type = 'repair' AND mo.planned_date = '2026-11-10'
  AND e.email = 'elena.kim@metro.example'
ON CONFLICT DO NOTHING;

INSERT INTO metro.maintenance_assignment (maintenance_order_id, employee_id, assignment_role)
SELECT mo.maintenance_order_id, e.employee_id, 'lead engineer'
FROM metro.maintenance_order mo
CROSS JOIN metro.employee e
WHERE mo.maintenance_type = 'rail_grinding' AND mo.planned_date = '2026-12-01'
  AND e.email = 'marat.sadykov@metro.example'
ON CONFLICT DO NOTHING;

-- stops for all schedules. I take the stations from the line of the train, so a schedule cannot get a station from another line. The times are calculated from
-- stop_order: first stop at 06:00, 4 minutes between stops, train stands 1 minute.
INSERT INTO metro.schedule_stop (schedule_id, line_station_id, arrival_time, departure_time)
SELECT sc.schedule_id,
       ls.line_station_id,
       TIME '06:00' + (ls.stop_order - 1) * INTERVAL '4 minutes',
       TIME '06:01' + (ls.stop_order - 1) * INTERVAL '4 minutes'
FROM metro.schedule sc
INNER JOIN metro.train_assignment ta ON ta.train_assignment_id = sc.train_assignment_id
INNER JOIN metro.line_station ls ON ls.line_id = ta.line_id
WHERE sc.direction = 'forward'
  AND ls.valid_to IS NULL
ON CONFLICT DO NOTHING;


-- 5. record_ts

-- IF NOT EXISTS so it works on the second run too. Because the column has a default, old rows get the value automatically and NOT NULL does not give an error.

ALTER TABLE metro.line ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE metro.station ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE metro.train_model ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE metro.ticket_type ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE metro.employee ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE metro.line_station ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE metro.track_segment ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE metro.train ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE metro.ticket_price ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE metro.train_assignment ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE metro.ticket ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE metro.maintenance_order ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE metro.schedule ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE metro.maintenance_assignment ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE metro.schedule_stop ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

-- check that record_ts is set for existing rows: empty_record_ts must be 0 in every table
SELECT 'line' AS table_name, COUNT(*) AS all_rows, COUNT(*) - COUNT(record_ts) AS empty_record_ts FROM metro.line
UNION ALL
SELECT 'station', COUNT(*), COUNT(*) - COUNT(record_ts) FROM metro.station
UNION ALL
SELECT 'train_model', COUNT(*), COUNT(*) - COUNT(record_ts) FROM metro.train_model
UNION ALL
SELECT 'ticket_type', COUNT(*), COUNT(*) - COUNT(record_ts) FROM metro.ticket_type
UNION ALL
SELECT 'employee', COUNT(*), COUNT(*) - COUNT(record_ts) FROM metro.employee
UNION ALL
SELECT 'line_station', COUNT(*), COUNT(*) - COUNT(record_ts) FROM metro.line_station
UNION ALL
SELECT 'track_segment', COUNT(*), COUNT(*) - COUNT(record_ts) FROM metro.track_segment
UNION ALL
SELECT 'train', COUNT(*), COUNT(*) - COUNT(record_ts) FROM metro.train
UNION ALL
SELECT 'ticket_price', COUNT(*), COUNT(*) - COUNT(record_ts) FROM metro.ticket_price
UNION ALL
SELECT 'train_assignment', COUNT(*), COUNT(*) - COUNT(record_ts) FROM metro.train_assignment
UNION ALL
SELECT 'ticket', COUNT(*), COUNT(*) - COUNT(record_ts) FROM metro.ticket
UNION ALL
SELECT 'maintenance_order', COUNT(*), COUNT(*) - COUNT(record_ts) FROM metro.maintenance_order
UNION ALL
SELECT 'schedule', COUNT(*), COUNT(*) - COUNT(record_ts) FROM metro.schedule
UNION ALL
SELECT 'maintenance_assignment', COUNT(*), COUNT(*) - COUNT(record_ts) FROM metro.maintenance_assignment
UNION ALL
SELECT 'schedule_stop', COUNT(*), COUNT(*) - COUNT(record_ts) FROM metro.schedule_stop;
