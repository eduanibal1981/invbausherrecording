-- Create view to get latest bloodweek entry with staff name for current month
CREATE OR REPLACE VIEW vw_patients_bw_status AS
SELECT 
    p.pcid,
    p.name as patient_name,
    p.lastbwcollected,
    p.nstaffid,
    bw.staffenter,
    s.name as entered_by_name,
    bw.cbchb,
    bw.month as bw_month,
    bw.year as bw_year,
    bw.created_at as bw_created_at
FROM patients p
LEFT JOIN LATERAL (
    SELECT b.* 
    FROM bloodweek b 
    WHERE b.pcid = p.pcid 
      AND b.year = EXTRACT(YEAR FROM CURRENT_DATE)
      AND b.month = to_char(CURRENT_DATE, 'FMMonth')
    ORDER BY b.created_at DESC 
    LIMIT 1
) bw ON TRUE
LEFT JOIN staff s ON s.medicalstaffid::text = bw.staffenter
WHERE p.status = 'Active';

COMMENT ON VIEW vw_patients_bw_status IS 'Patients with their current month bloodweek entry and the staff who entered it.';;
