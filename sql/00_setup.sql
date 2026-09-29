-- ============================================================
-- 00  SETUP: create the database and load events.csv
-- Tool: MySQL 8.0+
--
-- Source: RetailRocket e-commerce dataset (Kaggle)
--   https://www.kaggle.com/datasets/retailrocket/ecommerce-dataset
--   events.csv -> 2,756,101 rows: timestamp, visitorid, event, itemid, transactionid
--
-- Run once. Update the file path in LOAD DATA to where events.csv lives.
-- If LOAD DATA LOCAL is blocked, start the client with --local-infile=1
-- and run:  SET GLOBAL local_infile = 1;
-- ============================================================

CREATE DATABASE IF NOT EXISTS retailrocket;
USE retailrocket;

-- All date logic in this project is in UTC so results are reproducible
-- on any machine. (FROM_UNIXTIME otherwise uses the local time zone.)
SET time_zone = '+00:00';

DROP TABLE IF EXISTS events;
CREATE TABLE events (
  timestamp      BIGINT       NOT NULL,   -- Unix time in MILLISECONDS
  visitorid      INT          NOT NULL,
  event          VARCHAR(12)  NOT NULL,   -- 'view' | 'addtocart' | 'transaction'
  itemid         INT          NOT NULL,
  transactionid  INT          NULL        -- only on 'transaction' rows
);

LOAD DATA LOCAL INFILE '/path/to/events.csv'
INTO TABLE events
FIELDS TERMINATED BY ','
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(timestamp, visitorid, event, itemid, @txn)
SET transactionid = NULLIF(TRIM(TRAILING '\r' FROM @txn), '');

CREATE INDEX ix_events_visitor ON events (visitorid);
CREATE INDEX ix_events_event   ON events (event, visitorid);

-- ------------------------------------------------------------
-- Visitor-level summary table. Almost every question in this
-- project is "per visitor", so building this once keeps the
-- later queries short and fast.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS visitor_summary;
CREATE TABLE visitor_summary AS
SELECT
  visitorid,
  DATE(FROM_UNIXTIME(MIN(timestamp) / 1000))                    AS first_seen_date,
  COUNT(DISTINCT CASE WHEN event = 'view' THEN itemid END)      AS items_viewed,
  SUM(event = 'view')                                           AS view_events,
  MAX(event = 'view')                                           AS has_view,
  MAX(event = 'addtocart')                                      AS carted,
  MAX(event = 'transaction')                                    AS bought,
  COUNT(DISTINCT transactionid)                                 AS orders,
  COUNT(DISTINCT DATE(FROM_UNIXTIME(timestamp / 1000)))         AS active_days
FROM events
GROUP BY visitorid;

ALTER TABLE visitor_summary ADD PRIMARY KEY (visitorid);

-- Browse-depth bucket used throughout the analysis
ALTER TABLE visitor_summary ADD COLUMN depth_bucket VARCHAR(10);
UPDATE visitor_summary
SET depth_bucket = CASE
  WHEN items_viewed = 0             THEN '0 (no view)'
  WHEN items_viewed = 1             THEN '1 item'
  WHEN items_viewed BETWEEN 2 AND 4 THEN '2-4 items'
  WHEN items_viewed BETWEEN 5 AND 9 THEN '5-9 items'
  ELSE '10+ items'
END;

-- Quick check: expect 2,756,101 events and 1,407,580 visitors
SELECT (SELECT COUNT(*) FROM events)          AS events,
       (SELECT COUNT(*) FROM visitor_summary) AS visitors;
