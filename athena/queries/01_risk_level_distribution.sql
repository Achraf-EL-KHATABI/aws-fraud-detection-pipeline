-- ============================================================================
-- 01_risk_level_distribution.sql
-- ----------------------------------------------------------------------------
-- Counts transactions per risk level across the whole week.
-- This is the canonical validation query: the numbers MUST match what the
-- pandas prototype produced locally (LOW 32760, MEDIUM 354, HIGH 38).
-- If Spark = pandas, the ETL is faithful to the validated logic.
--
-- Workgroup: fraud-detection
-- Database:  fraud_detection
-- ============================================================================

SELECT
    risk_level,
    COUNT(*)                  AS n_transactions,
    SUM(is_fraud)             AS n_real_frauds,
    ROUND(100.0 * SUM(is_fraud) / COUNT(*), 3) AS fraud_rate_pct
FROM fraud_detection.transactions
GROUP BY risk_level
ORDER BY
    CASE risk_level
        WHEN 'HIGH'   THEN 1
        WHEN 'MEDIUM' THEN 2
        WHEN 'LOW'    THEN 3
    END;
