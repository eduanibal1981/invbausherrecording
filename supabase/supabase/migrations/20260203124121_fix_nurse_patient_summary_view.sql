-- =============================================
-- Fixed Nurse Patient Summary View
-- Handles empty string staffenter values
-- =============================================

DROP VIEW IF EXISTS nurse_patient_summary;

CREATE VIEW nurse_patient_summary AS
WITH current_month AS (
    SELECT 
        to_char(CURRENT_DATE, 'FMMonth') as month_name,
        EXTRACT(YEAR FROM CURRENT_DATE)::int as year_num
),
-- Get patients assigned to each nurse (based on their groups)
assigned_patients AS (
    SELECT 
        s.medicalstaffid as nurse_id,
        COUNT(DISTINCT p.pcid) as assigned_patient_count
    FROM staff s
    LEFT JOIN groupsofpatients g ON g.staffid = s.medicalstaffid AND g.ismain = TRUE
    LEFT JOIN patients p ON p.nstaffid = s.medicalstaffid AND p.status = 'Active'
    WHERE LOWER(s.staffrole) = 'nurse'
    GROUP BY s.medicalstaffid
),
-- Count BW entries made BY each staff member this month (who entered it)
-- Filter out empty strings and nulls
entries_by_staff AS (
    SELECT 
        bw.staffenter as staff_id_text,
        COUNT(DISTINCT bw.pcid) FILTER (WHERE bw.cbchb IS NOT NULL) as entries_made
    FROM bloodweek bw
    CROSS JOIN current_month cm
    WHERE bw.year = cm.year_num
      AND bw.month = cm.month_name
      AND bw.staffenter IS NOT NULL 
      AND bw.staffenter <> ''
      AND bw.staffenter ~ '^\d+$'  -- Only numeric strings
    GROUP BY bw.staffenter
),
-- Get nurse groups for display
nurse_groups AS (
    SELECT 
        g.staffid,
        string_agg(
            concat(g.ghall, '-', g.gday, '-', g.gshift), 
            ' | ' ORDER BY g.ghall, g.gday, g.gshift
        ) AS assigned_groups
    FROM groupsofpatients g
    WHERE g.ismain = TRUE
    GROUP BY g.staffid
)
SELECT 
    s.medicalstaffid AS nurse_id,
    s.name AS nurse_name,
    COALESCE(ap.assigned_patient_count, 0) AS total_patients,
    COALESCE(eb.entries_made, 0) AS bw_entered_this_month,
    CASE 
        WHEN COALESCE(ap.assigned_patient_count, 0) = 0 THEN 0
        ELSE ROUND(
            COALESCE(eb.entries_made, 0)::numeric / 
            COALESCE(ap.assigned_patient_count, 1)::numeric * 100, 
            1
        )
    END AS bw_percentage,
    ng.assigned_groups
FROM staff s
LEFT JOIN assigned_patients ap ON s.medicalstaffid = ap.nurse_id
LEFT JOIN entries_by_staff eb ON s.medicalstaffid::text = eb.staff_id_text
LEFT JOIN nurse_groups ng ON s.medicalstaffid = ng.staffid
WHERE LOWER(s.staffrole) = 'nurse'

UNION ALL

-- TOTAL row
SELECT 
    0 AS nurse_id,
    'TOTAL' AS nurse_name,
    (SELECT COUNT(*) FROM patients WHERE status = 'Active') AS total_patients,
    (SELECT COUNT(DISTINCT bw.pcid) 
     FROM bloodweek bw 
     CROSS JOIN current_month cm
     WHERE bw.year = cm.year_num 
       AND bw.month = cm.month_name 
       AND bw.cbchb IS NOT NULL) AS bw_entered_this_month,
    CASE 
        WHEN (SELECT COUNT(*) FROM patients WHERE status = 'Active') = 0 THEN 0
        ELSE ROUND(
            (SELECT COUNT(DISTINCT bw.pcid) 
             FROM bloodweek bw 
             CROSS JOIN current_month cm
             WHERE bw.year = cm.year_num 
               AND bw.month = cm.month_name 
               AND bw.cbchb IS NOT NULL)::numeric /
            (SELECT COUNT(*) FROM patients WHERE status = 'Active')::numeric * 100,
            1
        )
    END AS bw_percentage,
    NULL AS assigned_groups
FROM current_month;

COMMENT ON VIEW nurse_patient_summary IS 
'Monthly nurse performance: assigned patients vs BW entries made. 
bw_entered_this_month = entries made BY this staff (not whose patient it is).
bw_percentage can exceed 100% if nurse enters more than their assigned patients.
Resets automatically each month.';;
