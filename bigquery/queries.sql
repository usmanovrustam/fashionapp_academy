-- Sylyo BigQuery analysis queries
-- Requires:
-- 1) Firebase Analytics linked to BigQuery (events_* tables)
-- 2) Optional: Firestore → BigQuery extension for wardrobe / analyticsEvents

-- Daily active users from Firebase Analytics export
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS day,
  COUNT(DISTINCT user_pseudo_id) AS dau
FROM `YOUR_PROJECT.analytics_YOUR_PROPERTY.events_*`
WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
  AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY day
ORDER BY day DESC;

-- Funnel: scan → save → recommendation accept
WITH events AS (
  SELECT
    user_pseudo_id,
    event_name,
    TIMESTAMP_MICROS(event_timestamp) AS event_ts
  FROM `YOUR_PROJECT.analytics_YOUR_PROPERTY.events_*`
  WHERE event_name IN ('scan_completed', 'item_saved', 'recommendation_accepted')
)
SELECT
  COUNTIF(event_name = 'scan_completed') AS scans,
  COUNTIF(event_name = 'item_saved') AS saves,
  COUNTIF(event_name = 'recommendation_accepted') AS accepts
FROM events;

-- Top clothing categories saved (from event params)
SELECT
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'category') AS category,
  COUNT(*) AS saves
FROM `YOUR_PROJECT.analytics_YOUR_PROPERTY.events_*`
WHERE event_name = 'item_saved'
GROUP BY category
ORDER BY saves DESC;

-- Assistant usage
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS day,
  COUNT(*) AS asks
FROM `YOUR_PROJECT.analytics_YOUR_PROPERTY.events_*`
WHERE event_name = 'assistant_asked'
GROUP BY day
ORDER BY day DESC;

-- If using Firestore→BigQuery extension for analyticsEvents:
-- SELECT name, COUNT(*) AS cnt
-- FROM `YOUR_PROJECT.sylyo_analytics.sylyo_analyticsEvents_raw_changelog`
-- WHERE operation = 'CREATE'
-- GROUP BY name
-- ORDER BY cnt DESC;
