-- =============================================================================
-- FILE       : 06_advanced_analytics.sql
-- PROJECT    : Loan Portfolio Risk Analysis
-- DESCRIPTION: Advanced SQL techniques — CTEs, window functions, rankings,
--              percentile analysis, and borrower profiling.
--              This file demonstrates analyst-grade SQL fluency beyond
--              basic aggregations. Key techniques used:
--                - Recursive / multi-step CTEs
--                - RANK(), DENSE_RANK(), NTILE(), ROW_NUMBER()
--                - LAG() / LEAD() for trend detection
--                - PERCENT_RANK() for distribution analysis
--                - Correlated subqueries
--                - Conditional aggregation pivots
-- =============================================================================

USE loan_portfolio_db;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION A │ BORROWER RISK SCORING (CTE + CASE WHEN)
-- ─────────────────────────────────────────────────────────────────────────────
-- Constructs a simple composite risk score for each borrower based on:
--   Grade (40%), DTI (30%), Verification (20%), Homeownership (10%)
-- This mimics how an underwriting scorecard works in practice.

-- A1. Composite Risk Score per Loan
WITH risk_scores AS (
    SELECT
        id,
        loan_status,
        grade,
        dti,
        verification_status,
        home_ownership,
        loan_amount,
        int_rate,
        purpose,
        -- Grade Score (lower grade = higher risk = lower score)
        CASE grade
            WHEN 'A' THEN 40
            WHEN 'B' THEN 32
            WHEN 'C' THEN 24
            WHEN 'D' THEN 16
            WHEN 'E' THEN 10
            WHEN 'F' THEN 5
            WHEN 'G' THEN 1
            ELSE 0
        END                                               AS grade_score,
        -- DTI Score
        CASE
            WHEN dti < 0.10              THEN 30
            WHEN dti BETWEEN 0.10 AND 0.15 THEN 25
            WHEN dti BETWEEN 0.15 AND 0.20 THEN 20
            WHEN dti BETWEEN 0.20 AND 0.25 THEN 12
            WHEN dti BETWEEN 0.25 AND 0.30 THEN 6
            ELSE 0
        END                                               AS dti_score,
        -- Verification Score
        CASE verification_status
            WHEN 'Verified'        THEN 20
            WHEN 'Source Verified' THEN 15
            WHEN 'Not Verified'    THEN 5
            ELSE 0
        END                                               AS verification_score,
        -- Homeownership Score
        CASE home_ownership
            WHEN 'OWN'      THEN 10
            WHEN 'MORTGAGE' THEN 8
            WHEN 'RENT'     THEN 4
            ELSE 2
        END                                               AS ownership_score
    FROM financial_loan
),
scored_loans AS (
    SELECT *,
        (grade_score + dti_score + verification_score + ownership_score)
                                                          AS composite_risk_score,
        CASE
            WHEN (grade_score + dti_score + verification_score + ownership_score) >= 80
                THEN 'Prime'
            WHEN (grade_score + dti_score + verification_score + ownership_score) >= 60
                THEN 'Near-Prime'
            WHEN (grade_score + dti_score + verification_score + ownership_score) >= 40
                THEN 'Sub-Prime'
            ELSE 'Deep Sub-Prime'
        END                                               AS risk_tier
    FROM risk_scores
)
-- A2. Risk Tier Performance Validation — does the score predict defaults?
SELECT
    risk_tier,
    COUNT(*)                                              AS loans,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2)    AS pct_of_portfolio,
    ROUND(AVG(composite_risk_score), 1)                   AS avg_score,
    ROUND(AVG(int_rate) * 100, 2)                         AS avg_int_rate_pct,
    ROUND(SUM(loan_amount) / 1e6, 2)                      AS funded_usd_m,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                          AS actual_default_rate_pct
FROM scored_loans
GROUP BY risk_tier
ORDER BY avg_score DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION B │ WINDOW FUNCTION RANKINGS
-- ─────────────────────────────────────────────────────────────────────────────

-- B1. State Risk Ranking using RANK() and DENSE_RANK()
--     Useful for geographic risk heatmaps
SELECT
    address_state,
    COUNT(*)                                              AS applications,
    ROUND(SUM(loan_amount) / 1e6, 2)                      AS funded_usd_m,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                          AS default_rate_pct,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off'
                   THEN (loan_amount - total_payment) ELSE 0 END) / 1e6, 3)
                                                          AS net_loss_usd_m,
    -- Rank by default rate (gaps allowed for ties)
    RANK() OVER (ORDER BY
        SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
        * 100.0 / COUNT(*) DESC)                          AS default_rate_rank,
    -- Rank by absolute dollar loss
    DENSE_RANK() OVER (ORDER BY
        SUM(CASE WHEN loan_status = 'Charged Off'
                 THEN (loan_amount - total_payment) ELSE 0 END) DESC)
                                                          AS loss_amount_rank
FROM financial_loan
GROUP BY address_state
HAVING COUNT(*) >= 50
ORDER BY default_rate_rank;


-- B2. Sub-Grade Risk Ladder — ranked within each parent grade
SELECT
    sub_grade,
    LEFT(sub_grade, 1)                                    AS grade,
    COUNT(*)                                              AS applications,
    ROUND(AVG(int_rate) * 100, 2)                         AS avg_int_rate_pct,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                          AS default_rate_pct,
    -- Rank within each grade group
    RANK() OVER (
        PARTITION BY LEFT(sub_grade, 1)
        ORDER BY
            SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
            * 100.0 / COUNT(*) DESC
    )                                                     AS rank_within_grade
FROM financial_loan
GROUP BY sub_grade
ORDER BY sub_grade;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION C │ PERCENTILE DISTRIBUTION ANALYSIS
-- ─────────────────────────────────────────────────────────────────────────────

-- C1. Loan Amount Distribution — NTILE into deciles
--     Shows which loan size bands carry the most risk
WITH loan_deciles AS (
    SELECT
        id,
        loan_amount,
        loan_status,
        int_rate,
        dti,
        NTILE(10) OVER (ORDER BY loan_amount)             AS loan_amount_decile
    FROM financial_loan
)
SELECT
    loan_amount_decile,
    COUNT(*)                                              AS loans,
    ROUND(MIN(loan_amount),  0)                           AS min_loan_usd,
    ROUND(MAX(loan_amount),  0)                           AS max_loan_usd,
    ROUND(AVG(loan_amount),  0)                           AS avg_loan_usd,
    ROUND(AVG(int_rate) * 100, 2)                         AS avg_int_rate_pct,
    ROUND(AVG(dti)      * 100, 2)                         AS avg_dti_pct,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                          AS default_rate_pct
FROM loan_deciles
GROUP BY loan_amount_decile
ORDER BY loan_amount_decile;


-- C2. Income Percentile Rank per borrower — who are the highest-income defaulters?
SELECT
    id,
    annual_income,
    loan_amount,
    grade,
    loan_status,
    ROUND(PERCENT_RANK() OVER (ORDER BY annual_income) * 100, 1)
                                                          AS income_percentile,
    ROUND(PERCENT_RANK() OVER (ORDER BY loan_amount)   * 100, 1)
                                                          AS loan_size_percentile
FROM financial_loan
WHERE loan_status = 'Charged Off'
  AND annual_income > 0
ORDER BY annual_income DESC
LIMIT 20;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION D │ MULTI-STEP CTE: PORTFOLIO CONCENTRATION ANALYSIS
-- ─────────────────────────────────────────────────────────────────────────────
-- Measures how concentrated the portfolio's losses are.
-- Analyst insight: if 20% of segments drive 80% of losses (Pareto principle),
-- that's where risk management should focus.

WITH segment_losses AS (
    -- Step 1: Calculate loss per purpose segment
    SELECT
        purpose,
        COUNT(*)                                          AS total_loans,
        SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
                                                          AS defaults,
        SUM(CASE WHEN loan_status = 'Charged Off'
                 THEN (loan_amount - total_payment) ELSE 0 END)
                                                          AS net_loss
    FROM financial_loan
    GROUP BY purpose
),
ranked_segments AS (
    -- Step 2: Rank segments by loss contribution
    SELECT
        purpose,
        total_loans,
        defaults,
        net_loss,
        RANK() OVER (ORDER BY net_loss DESC)              AS loss_rank,
        SUM(net_loss) OVER ()                             AS total_portfolio_loss
    FROM segment_losses
),
pareto AS (
    -- Step 3: Compute running cumulative loss % (Pareto curve)
    SELECT
        purpose,
        total_loans,
        defaults,
        ROUND(net_loss / 1e6, 3)                          AS net_loss_usd_m,
        loss_rank,
        ROUND(net_loss * 100.0 / total_portfolio_loss, 2) AS pct_of_total_loss,
        ROUND(SUM(net_loss) OVER (ORDER BY net_loss DESC)
              * 100.0 / total_portfolio_loss, 2)          AS cumulative_loss_pct
    FROM ranked_segments
)
SELECT * FROM pareto
ORDER BY loss_rank;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION E │ TREND DETECTION WITH LAG / LEAD
-- ─────────────────────────────────────────────────────────────────────────────

-- E1. Month-over-month default rate acceleration
--     Flags months where the default rate jumped by more than 2 percentage points
WITH monthly_defaults AS (
    SELECT
        DATE_FORMAT(issue_date, '%Y-%m')                  AS month,
        COUNT(*)                                          AS total,
        ROUND(SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
              * 100.0 / COUNT(*), 2)                      AS default_rate_pct
    FROM financial_loan
    GROUP BY month
)
SELECT
    month,
    total,
    default_rate_pct,
    LAG(default_rate_pct)  OVER (ORDER BY month)          AS prev_month_rate,
    LEAD(default_rate_pct) OVER (ORDER BY month)          AS next_month_rate,
    ROUND(default_rate_pct
          - LAG(default_rate_pct) OVER (ORDER BY month), 2)
                                                          AS mom_change_pp,
    -- Flag months where default rate spiked (early warning indicator)
    CASE
        WHEN (default_rate_pct
              - LAG(default_rate_pct) OVER (ORDER BY month)) > 2
        THEN '⚠ Spike'
        ELSE '—'
    END                                                   AS alert
FROM monthly_defaults
ORDER BY month;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION F │ CONDITIONAL AGGREGATION PIVOT
-- ─────────────────────────────────────────────────────────────────────────────

-- F1. Grade × Loan Status cross-tab (pivot-style)
--     Produces a matrix of application counts by grade and status
--     — directly usable as a Tableau data source
SELECT
    grade,
    COUNT(*)                                              AS total_loans,
    SUM(CASE WHEN loan_status = 'Fully Paid'   THEN 1 ELSE 0 END)
                                                          AS fully_paid,
    SUM(CASE WHEN loan_status = 'Current'      THEN 1 ELSE 0 END)
                                                          AS current_loans,
    SUM(CASE WHEN loan_status = 'Charged Off'  THEN 1 ELSE 0 END)
                                                          AS charged_off,
    -- Percentages
    ROUND(SUM(CASE WHEN loan_status = 'Fully Paid'  THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                          AS fully_paid_pct,
    ROUND(SUM(CASE WHEN loan_status = 'Current'     THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                          AS current_pct,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                          AS charged_off_pct,
    -- Dollar amounts
    ROUND(SUM(CASE WHEN loan_status = 'Fully Paid'  THEN loan_amount ELSE 0 END) / 1e6, 2)
                                                          AS fully_paid_usd_m,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off' THEN loan_amount ELSE 0 END) / 1e6, 2)
                                                          AS charged_off_usd_m
FROM financial_loan
GROUP BY grade
ORDER BY grade;


-- F2. Purpose × Term Default Rate Matrix
--     Reveals which purpose+term combinations are structural risk concentrations
SELECT
    purpose,
    ROUND(SUM(CASE WHEN TRIM(term) = '36 months' THEN 1 ELSE 0 END)
          * 100.0 / NULLIF(SUM(CASE WHEN TRIM(term) = '36 months' THEN 1 ELSE 0 END), 0), 2)
                                                          AS apps_36m,
    ROUND(SUM(CASE WHEN TRIM(term) = '36 months'
                    AND loan_status = 'Charged Off' THEN 1 ELSE 0 END)
          * 100.0 / NULLIF(SUM(CASE WHEN TRIM(term) = '36 months' THEN 1 ELSE 0 END), 0), 2)
                                                          AS default_rate_36m_pct,
    ROUND(SUM(CASE WHEN TRIM(term) = '60 months' THEN 1 ELSE 0 END)
          * 100.0 / NULLIF(SUM(CASE WHEN TRIM(term) = '60 months' THEN 1 ELSE 0 END), 0), 2)
                                                          AS apps_60m,
    ROUND(SUM(CASE WHEN TRIM(term) = '60 months'
                    AND loan_status = 'Charged Off' THEN 1 ELSE 0 END)
          * 100.0 / NULLIF(SUM(CASE WHEN TRIM(term) = '60 months' THEN 1 ELSE 0 END), 0), 2)
                                                          AS default_rate_60m_pct,
    -- Which term is riskier for this purpose?
    CASE
        WHEN SUM(CASE WHEN TRIM(term) = '60 months' AND loan_status = 'Charged Off' THEN 1 ELSE 0 END)
             * 1.0 / NULLIF(SUM(CASE WHEN TRIM(term) = '60 months' THEN 1 ELSE 0 END), 0)
             >
             SUM(CASE WHEN TRIM(term) = '36 months' AND loan_status = 'Charged Off' THEN 1 ELSE 0 END)
             * 1.0 / NULLIF(SUM(CASE WHEN TRIM(term) = '36 months' THEN 1 ELSE 0 END), 0)
        THEN '60-month riskier'
        ELSE '36-month riskier'
    END                                                   AS riskier_term
FROM financial_loan
GROUP BY purpose
ORDER BY purpose;
