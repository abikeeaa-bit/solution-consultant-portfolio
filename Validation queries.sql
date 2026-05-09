-- =============================================================
-- AI Platform Pre-Deployment Data Analysis
-- Dataset: Inside Airbnb London (80,000+ residential property records)
-- Author: Oluwatobi Ayanreti
-- Purpose: Validate and analyse a client's residential property data
-- before configuring an AI communication platform like Travtus Adam.
-- =============================================================


-- Query 1: Communication response time breakdown
-- Purpose: Establishes the baseline of how operators currently respond
-- to residents across the entire dataset.
-- Risk if ignored: Without this baseline, there's no benchmark to
-- measure Adam's improvement against post-deployment.
SELECT 
    host_response_time,
    COUNT(*) as property_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM "listings ldn" WHERE host_response_time IS NOT NULL AND host_response_time != ''), 1) as percentage
FROM "listings ldn"
WHERE host_response_time IS NOT NULL 
AND host_response_time != ''
GROUP BY host_response_time
ORDER BY property_count DESC;


-- Query 2: Properties with missing response data
-- Purpose: Identifies properties where the operator has no measurable
-- communication metrics at all.
-- Risk if ignored: 32.7% of properties in this dataset have no
-- response data. These cannot be improved by Adam without manual
-- data collection during onboarding.
SELECT 
    COUNT(*) as total_listings,
    SUM(CASE WHEN host_response_rate IS NULL OR host_response_rate = '' THEN 1 ELSE 0 END) as missing_response_rate,
    SUM(CASE WHEN host_response_time IS NULL OR host_response_time = '' THEN 1 ELSE 0 END) as missing_response_time,
    ROUND(100.0 * SUM(CASE WHEN host_response_rate IS NULL OR host_response_rate = '' THEN 1 ELSE 0 END) / COUNT(*), 1) as pct_missing
FROM "listings ldn";


-- Query 3: Neighbourhoods with worst communication scores
-- Purpose: Identifies geographic concentrations of communication
-- problems.
-- Risk if ignored: Without this view, deployment priority is set
-- by hunch rather than data. The worst neighbourhoods are where
-- Adam delivers the highest measurable ROI.
SELECT 
    neighbourhood_cleansed,
    COUNT(*) as total_properties,
    ROUND(AVG(CAST(review_scores_communication AS FLOAT)), 2) as avg_communication_score,
    ROUND(AVG(CAST(review_scores_rating AS FLOAT)), 2) as avg_overall_rating
FROM "listings ldn"
WHERE review_scores_communication IS NOT NULL
AND review_scores_communication != ''
GROUP BY neighbourhood_cleansed
HAVING COUNT(*) > 20
ORDER BY avg_communication_score ASC
LIMIT 15;


-- Query 4: High rated properties with poor communication
-- Purpose: Identifies properties where the underlying product is
-- strong but communication is letting it down.
-- Risk if ignored: These are prime candidates for AI deployment.
-- Missing them means leaving the easiest wins on the table.
SELECT 
    id,
    host_id,
    neighbourhood_cleansed,
    property_type,
    review_scores_rating,
    review_scores_communication,
    host_response_time,
    number_of_reviews
FROM "listings ldn"
WHERE CAST(review_scores_rating AS FLOAT) >= 4.5
AND CAST(review_scores_communication AS FLOAT) < 4.0
AND review_scores_communication IS NOT NULL
AND review_scores_communication != ''
ORDER BY number_of_reviews DESC
LIMIT 25;


-- Query 5: Properties gone silent (stale data risk)
-- Purpose: Identifies records where the property is listed as
-- available but has had no resident activity in over a year.
-- Risk if ignored: Stale data corrupts Adam's reporting and
-- makes occupancy metrics unreliable.
SELECT 
    id,
    host_id,
    neighbourhood_cleansed,
    property_type,
    number_of_reviews,
    last_review,
    availability_365,
    CAST(JULIANDAY('now') - JULIANDAY(last_review) AS INTEGER) as days_since_last_review
FROM "listings ldn"
WHERE last_review IS NOT NULL
AND last_review != ''
AND JULIANDAY('now') - JULIANDAY(last_review) > 365
AND availability_365 > 0
ORDER BY days_since_last_review DESC
LIMIT 30;


-- Query 6a: Contradictory availability records
-- Purpose: Identifies records claiming to be available but with
-- zero availability days in the calendar.
-- Risk if ignored: Data integrity issue that breaks Adam's
-- occupancy dashboard reporting.
SELECT COUNT(*) as contradictory_availability
FROM "listings ldn"
WHERE availability_365 = 0 
AND has_availability = 't';


-- Query 6b: Missing critical fields
-- Purpose: Counts records missing the fields any property management
-- platform requires to function.
-- Risk if ignored: Records without host_id, neighbourhood, or
-- property_type cannot be processed by Adam at all.
SELECT COUNT(*) as missing_critical_fields
FROM "listings ldn"
WHERE host_id IS NULL
OR neighbourhood_cleansed IS NULL OR neighbourhood_cleansed = ''
OR property_type IS NULL OR property_type = '';


-- Query 7: Communication quality vs portfolio scale (KEY INSIGHT)
-- Purpose: Tests whether communication scores improve, decline,
-- or plateau as portfolio size grows.
-- Finding: Scores improve from 4.76 (small portfolios) to 4.89
-- (large portfolios), then plateau. Manual processes hit a ceiling
-- and stop improving. This is the AI use case in numbers.
SELECT 
    CASE 
        WHEN number_of_reviews < 10 THEN '1. Small (1-9 reviews)'
        WHEN number_of_reviews < 50 THEN '2. Medium (10-49 reviews)'
        WHEN number_of_reviews < 100 THEN '3. Growing (50-99 reviews)'
        WHEN number_of_reviews < 200 THEN '4. Large (100-199 reviews)'
        ELSE '5. Very Large (200+ reviews)'
    END as portfolio_size_tier,
    COUNT(*) as property_count,
    ROUND(AVG(CAST(review_scores_communication AS FLOAT)), 3) as avg_communication_score,
    ROUND(AVG(CAST(review_scores_rating AS FLOAT)), 3) as avg_overall_score
FROM "listings ldn"
WHERE review_scores_communication IS NOT NULL
AND review_scores_communication != ''
AND number_of_reviews IS NOT NULL
GROUP BY portfolio_size_tier
ORDER BY portfolio_size_tier;


-- Query 8: Neighbourhood response time benchmark
-- Purpose: Maps response speed at the neighbourhood level so
-- deployment can be prioritised geographically.
-- Risk if ignored: Onboarding effort gets distributed evenly
-- across properties when it should be focused where impact is
-- measurable fastest.
SELECT 
    neighbourhood_cleansed,
    COUNT(*) as total_properties,
    SUM(CASE WHEN host_response_time = 'within an hour' THEN 1 ELSE 0 END) as within_hour,
    SUM(CASE WHEN host_response_time = 'within a few hours' THEN 1 ELSE 0 END) as within_hours,
    SUM(CASE WHEN host_response_time = 'within a day' THEN 1 ELSE 0 END) as within_day,
    SUM(CASE WHEN host_response_time = 'a few days or more' THEN 1 ELSE 0 END) as slow_response,
    ROUND(100.0 * SUM(CASE WHEN host_response_time = 'within an hour' THEN 1 ELSE 0 END) / COUNT(*), 1) as pct_fast_response
FROM "listings ldn"
WHERE host_response_time IS NOT NULL
AND host_response_time != ''
GROUP BY neighbourhood_cleansed
HAVING COUNT(*) > 30
ORDER BY pct_fast_response ASC
LIMIT 20;


-- Query 9: Superhost vs non-superhost communication gap
-- Purpose: Tests whether the operator quality signal correlates
-- with communication quality.
-- Risk if ignored: Without this comparison, it's not clear
-- whether AI tools benefit only weak operators or all operators.
SELECT 
    host_is_superhost,
    COUNT(*) as total_properties,
    ROUND(AVG(CAST(review_scores_communication AS FLOAT)), 3) as avg_communication_score,
    ROUND(AVG(CAST(review_scores_rating AS FLOAT)), 3) as avg_overall_rating,
    SUM(CASE WHEN host_response_time = 'within an hour' THEN 1 ELSE 0 END) as responds_within_hour,
    ROUND(100.0 * SUM(CASE WHEN host_response_time = 'within an hour' THEN 1 ELSE 0 END) / COUNT(*), 1) as pct_fast_response
FROM "listings ldn"
WHERE review_scores_communication IS NOT NULL
AND review_scores_communication != ''
GROUP BY host_is_superhost;


-- Query 10: Hosts managing multiple properties (enterprise client profile)
-- Purpose: Identifies the large-portfolio operators in the dataset.
-- Risk if ignored: These are exactly the profile of company Travtus
-- sells to. Their patterns should drive deployment configuration
-- for similar real-world clients.
SELECT 
    host_id,
    host_name,
    host_total_listings_count,
    COUNT(*) as properties_in_dataset,
    ROUND(AVG(CAST(review_scores_communication AS FLOAT)), 2) as avg_communication_score,
    ROUND(AVG(CAST(review_scores_rating AS FLOAT)), 2) as avg_overall_rating,
    MAX(host_response_time) as response_time,
    SUM(number_of_reviews) as total_reviews_across_portfolio
FROM "listings ldn"
WHERE host_total_listings_count > 10
AND review_scores_communication IS NOT NULL
AND review_scores_communication != ''
GROUP BY host_id
ORDER BY host_total_listings_count DESC
LIMIT 20;


-- Query 11: Review frequency drop-off (early warning system)
-- Purpose: Identifies neighbourhoods where historical engagement
-- was high but recent activity has dropped sharply.
-- Risk if ignored: This is a pre-churn indicator. Adam can be
-- configured to alert property managers before they lose tenants.
SELECT 
    neighbourhood_cleansed,
    COUNT(*) as total_properties,
    ROUND(AVG(number_of_reviews), 1) as avg_total_reviews,
    ROUND(AVG(number_of_reviews_ltm), 1) as avg_reviews_last_12_months,
    ROUND(AVG(number_of_reviews_l30d), 1) as avg_reviews_last_30_days,
    ROUND(100.0 * AVG(number_of_reviews_ltm) / NULLIF(AVG(number_of_reviews), 0), 1) as review_activity_rate_pct
FROM "listings ldn"
WHERE number_of_reviews > 0
GROUP BY neighbourhood_cleansed
HAVING COUNT(*) > 20
ORDER BY review_activity_rate_pct ASC
LIMIT 15;


-- Query 12: Revenue vs communication score (THE MONEY QUERY)
-- Purpose: Tests the direct financial relationship between
-- communication quality and annual revenue.
-- Finding: Properties scoring below 3.0 on communication earn
-- $2,484/year average. Properties scoring 4.5-4.7 earn $17,370.
-- That's a 7x revenue gap directly tied to communication quality.
-- For a client onboarding 1,000 units with 5% in bottom tiers,
-- that's $750K of unrealised annual revenue. This is the ROI
-- case for Adam in a single number.
SELECT 
    CASE 
        WHEN CAST(review_scores_communication AS FLOAT) >= 4.8 THEN '4.8-5.0 (Excellent)'
        WHEN CAST(review_scores_communication AS FLOAT) >= 4.5 THEN '4.5-4.7 (Good)'
        WHEN CAST(review_scores_communication AS FLOAT) >= 4.0 THEN '4.0-4.4 (Average)'
        WHEN CAST(review_scores_communication AS FLOAT) >= 3.0 THEN '3.0-3.9 (Poor)'
        ELSE 'Below 3.0 (Critical)'
    END as communication_tier,
    COUNT(*) as property_count,
    ROUND(AVG(estimated_occupancy_l365d), 1) as avg_occupancy_days_per_year,
    ROUND(AVG(CAST(REPLACE(REPLACE(estimated_revenue_l365d, '$', ''), ',', '') AS FLOAT)), 0) as avg_annual_revenue
FROM "listings ldn"
WHERE review_scores_communication IS NOT NULL
AND review_scores_communication != ''
AND estimated_revenue_l365d IS NOT NULL
AND estimated_revenue_l365d != ''
GROUP BY communication_tier
ORDER BY avg_annual_revenue DESC;