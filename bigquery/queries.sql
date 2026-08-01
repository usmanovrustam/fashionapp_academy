-- Nook BigQuery analysis queries
-- Firebase project: sylyo-fashion (display name: stylo)
-- GA4 property: 548069136
-- Expected dataset (created after BigQuery link / first export):
--   sylyo-fashion.analytics_548069136.events_*
--
-- Note: the analytics_* dataset can take up to ~24 hours to appear after linking.

-- Daily active users
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS day,
  COUNT(DISTINCT user_pseudo_id) AS dau
FROM `sylyo-fashion.analytics_548069136.events_*`
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
  FROM `sylyo-fashion.analytics_548069136.events_*`
  WHERE event_name IN ('scan_completed', 'item_saved', 'recommendation_accepted')
)
SELECT
  COUNTIF(event_name = 'scan_completed') AS scans,
  COUNTIF(event_name = 'item_saved') AS saves,
  COUNTIF(event_name = 'recommendation_accepted') AS accepts
FROM events;

-- Top clothing categories saved
SELECT
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'category') AS category,
  COUNT(*) AS saves
FROM `sylyo-fashion.analytics_548069136.events_*`
WHERE event_name = 'item_saved'
GROUP BY category
ORDER BY saves DESC;

-- Assistant usage
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS day,
  COUNT(*) AS asks
FROM `sylyo-fashion.analytics_548069136.events_*`
WHERE event_name = 'assistant_asked'
GROUP BY day
ORDER BY day DESC;

-- Auth events
SELECT
  event_name,
  COUNT(*) AS cnt
FROM `sylyo-fashion.analytics_548069136.events_*`
WHERE event_name IN ('login', 'sign_up', 'logout')
GROUP BY event_name
ORDER BY cnt DESC;
