-- ============================================================================
-- 03_fraud_hotspots.sql
-- ----------------------------------------------------------------------------
-- Two business-oriented analyses on the curated data:
--   A. Daily fraud breakdown — how many real frauds per day, and how many
--      were caught by ANY of our rules (risk_score > 0).
--   B. Top 10 merchant cities by real-fraud count — the geographical
--      hotspots in the observed week.
-- ============================================================================

-- A. Daily fraud counts vs rules-detected counts
SELECT
    year, month, day,
    COUNT(*)                                                       AS total_txns,
    SUM(is_fraud)                                                  AS real_frauds,
    SUM(CASE WHEN risk_score > 0 AND is_fraud = 1 THEN 1 ELSE 0 END) AS frauds_caught,
    SUM(CASE WHEN risk_score > 0 THEN 1 ELSE 0 END)                AS total_flagged
FROM fraud_detection.transactions
GROUP BY year, month, day
ORDER BY year, month, day;


-- B. Top 10 merchant cities by real-fraud count
-- Run this as a SECOND query (Athena runs one statement at a time).
--
-- SELECT
--     merchant_city,
--     merchant_state,
--     COUNT(*)        AS total_txns,
--     SUM(is_fraud)   AS real_frauds,
--     ROUND(100.0 * SUM(is_fraud) / COUNT(*), 3) AS fraud_rate_pct
-- FROM fraud_detection.transactions
-- WHERE is_fraud = 1
-- GROUP BY merchant_city, merchant_state
-- ORDER BY real_frauds DESC
-- LIMIT 10;
