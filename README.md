# Loan Portfolio Risk Analysis
### SQL · Tableau · Credit Risk Analytics

> **Tools:** MySQL 8 · Tableau Desktop  
> **Dataset:** 38,576 loan records · 24 variables · FY2021  
> **Domain:** Consumer Lending · Credit Risk · Portfolio Management

---

## Business Context

A consumer lending institution needs visibility into the health of its loan portfolio. This analysis answers three core questions faced by risk analysts and credit managers:

1. **Exposure** — Where is our capital deployed, and how is it concentrated?
2. **Loss** — How much are we losing, who is defaulting, and why?
3. **Trend** — Is credit quality improving or deteriorating over time?

The analysis translates raw loan-level data into actionable insights across portfolio segmentation, default risk profiling, Loss Given Default (LGD) estimation, and temporal trend monitoring.

---

## Key Findings

| Metric | Value |
|--------|-------|
| Total Loan Applications | 38,576 |
| Total Funded Amount | ~$446M |
| Total Amount Received | ~$474M |
| Average Interest Rate | ~12% |
| Average DTI | ~13.3% |
| Bad Loan (Charged Off) Rate | ~13.8% |

**Top Insights:**
- **Grade concentration risk:** Grades A and B account for ~50% of the portfolio but carry default rates under 5%. Grades E–G carry default rates exceeding 28%, indicating a high-risk tail in the book.
- **Purpose-driven defaults:** `small_business` and `renewable_energy` loans have the highest default rates despite moderate volumes — a pricing and underwriting blind spot.
- **DTI threshold effect:** Borrowers with DTI > 20% default at nearly 2× the rate of those below 15%, yet many are approved at similar interest rates — signalling a potential repricing opportunity.
- **Geographic concentration:** California, New York, and Texas account for ~35% of funded volume. Several mid-size states show default rates above 17%.
- **60-month term risk premium:** Across almost all loan purposes, 60-month loans default significantly more than 36-month loans, suggesting term length is an underappreciated risk factor.
- **LGD finding:** Average Loss Given Default is ~48%, meaning for every $1 that charges off, only ~$0.52 is recovered. Grade F–G loans have LGDs above 60%.

---

## SQL Analysis Structure

The analysis is broken into six modular scripts, designed to run sequentially:

```
sql/
├── 01_schema_setup.sql         — Database creation, table DDL, data load instructions
├── 02_kpi_summary.sql          — Executive KPIs: portfolio totals, good/bad loan split, scorecard
├── 03_portfolio_breakdown.sql  — Segmentation: Grade, Purpose, State, Term, Emp. Length, Ownership
├── 04_risk_analysis.sql        — LGD, DTI buckets, multi-factor risk matrices, interest rate sensitivity
├── 05_time_series.sql          — Monthly trends, MoM growth (LAG), cohort analysis, cumulative exposure
└── 06_advanced_analytics.sql   — Composite risk scoring, RANK/NTILE/PERCENT_RANK, Pareto analysis, pivots
```

### SQL Techniques Demonstrated

| Technique | File(s) |
|-----------|---------|
| CTEs (multi-step logic) | 04, 05, 06 |
| Window Functions: `RANK()`, `DENSE_RANK()`, `NTILE()` | 06 |
| Window Functions: `LAG()`, `LEAD()`, `SUM() OVER()` | 05, 06 |
| `PERCENT_RANK()` for percentile distribution | 06 |
| `CASE WHEN` for risk segmentation & pivot aggregation | 03, 04, 06 |
| Conditional aggregation (pivot-style cross-tabs) | 06 |
| `PARTITION BY` for within-group calculations | 03, 05, 06 |
| Composite scoring (analyst scorecard) | 06 |
| Pareto / cumulative concentration analysis | 06 |
| Date functions: `DATE_FORMAT()`, `STR_TO_DATE()` | 01, 05 |

---

## How to Run

**Prerequisites:** MySQL 8.0+, ~500MB disk space

```bash
# 1. Clone the repository
git clone https://github.com/<your-username>/Loan-Portfolio-Risk-Analysis.git
cd Loan-Portfolio-Risk-Analysis

# 2. Start MySQL and run scripts in order
mysql -u root -p < sql/01_schema_setup.sql   # Creates DB + table
# Load financial_loan.csv via MySQL Workbench Import Wizard (see comments in 01_schema_setup.sql)

mysql -u root -p loan_portfolio_db < sql/02_kpi_summary.sql
mysql -u root -p loan_portfolio_db < sql/03_portfolio_breakdown.sql
mysql -u root -p loan_portfolio_db < sql/04_risk_analysis.sql
mysql -u root -p loan_portfolio_db < sql/05_time_series.sql
mysql -u root -p loan_portfolio_db < sql/06_advanced_analytics.sql
```

**Alternatively:** Open each `.sql` file in MySQL Workbench or DBeaver and run section by section.

---

## Tableau Dashboard

The Tableau workbook (`Bank Loan Analysis Project.twb`) connects to the same dataset and provides three interactive dashboards:

- **Summary Dashboard** — Portfolio-level KPIs and good/bad loan split
- **Overview Dashboard** — Segmentation by grade, purpose, state, term
- **Details Dashboard** — Loan-level drill-down table

> The SQL queries in this repository are the analytical backbone that validated all Tableau metrics and generated additional insights not shown in the dashboards.

---

## Dataset

| Field | Description |
|-------|-------------|
| `loan_status` | Fully Paid / Current / Charged Off |
| `grade` / `sub_grade` | LendingClub risk grade (A1–G5) |
| `loan_amount` | Principal disbursed (USD) |
| `total_payment` | Total payments received to date (USD) |
| `int_rate` | Interest rate (decimal) |
| `dti` | Debt-to-income ratio at origination |
| `annual_income` | Borrower stated annual income |
| `purpose` | Borrower's stated loan purpose |
| `address_state` | US state of borrower |
| `term` | Loan term: 36 or 60 months |
| `emp_length` | Employment length band |
| `verification_status` | Income verification level |
| `issue_date` | Loan origination date |

**Source:** Adapted from LendingClub public loan data · FY2021

---

## Skills Demonstrated

`SQL` `MySQL` `Window Functions` `CTEs` `Credit Risk` `LGD Analysis` `Portfolio Segmentation` `Cohort Analysis` `Data Analytics` `Tableau` `Business Intelligence` `Financial Analysis`
