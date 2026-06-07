-- ============================================================================
-- 02_rule_precision.sql
-- ----------------------------------------------------------------------------
-- For each rule, computes:
--   - how many transactions it flagged
--   - how many of those were ACTUAL fraud (precision)
--   - how many true frauds it caught (recall)
--
-- This is the honest evaluation of each heuristic. The local prototype
-- found R1 (~5.6%) to be the only discriminating rule; this query confirms
-- the same numbers on the Spark output.
-- ============================================================================

WITH per_rule AS (
    SELECT 'r1_amount_anomaly' AS rule_name,
           SUM(r1_amount_anomaly)                                AS n_flagged,
           SUM(CASE WHEN r1_amount_anomaly = 1 AND is_fraud = 1
                    THEN 1 ELSE 0 END)                           AS n_correct
    FROM fraud_detection.transactions

    UNION ALL
    SELECT 'r2_velocity',
           SUM(r2_velocity),
           SUM(CASE WHEN r2_velocity = 1 AND is_fraud = 1 THEN 1 ELSE 0 END)
    FROM fraud_detection.transactions

    UNION ALL
    SELECT 'r4_odd_hour',
           SUM(r4_odd_hour),
           SUM(CASE WHEN r4_odd_hour = 1 AND is_fraud = 1 THEN 1 ELSE 0 END)
    FROM fraud_detection.transactions
)
SELECT
    rule_name,
    n_flagged,
    n_correct,
    CASE WHEN n_flagged = 0 THEN 0
         ELSE ROUND(100.0 * n_correct / n_flagged, 2)
    END AS precision_pct,
    (SELECT SUM(is_fraud) FROM fraud_detection.transactions) AS total_real_frauds,
    CASE WHEN (SELECT SUM(is_fraud) FROM fraud_detection.transactions) = 0 THEN 0
         ELSE ROUND(100.0 * n_correct
              / (SELECT SUM(is_fraud) FROM fraud_detection.transactions), 2)
    END AS recall_pct
FROM per_rule
ORDER BY precision_pct DESC;
