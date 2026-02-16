-- Fix nurse summary BW counts:
-- 1) Count entries by staffenter + selected month + selected year.
-- 2) Normalize month text matching (trim + lower).
-- 3) Avoid faulty digit regex escaping from previous migration.
CREATE OR REPLACE FUNCTION public.get_nurse_patient_summary(
  in_target_year integer,
  in_target_month text
)
RETURNS TABLE(
  nurse_id bigint,
  nurse_name text,
  total_patients bigint,
  bw_entered_this_month bigint,
  bw_percentage numeric,
  assigned_groups text
)
LANGUAGE sql
STABLE
AS $function$
WITH normalized_input AS (
  SELECT
    in_target_year AS target_year,
    lower(trim(in_target_month)) AS target_month
),
assigned_patients AS (
  SELECT
    s.medicalstaffid AS nurse_id,
    COUNT(DISTINCT p.pcid)::bigint AS assigned_patient_count
  FROM public.staff s
  LEFT JOIN public.patients p
    ON p.nstaffid = s.medicalstaffid
   AND p.status = 'Active'
  WHERE lower(trim(s.staffrole)) = 'nurse'
  GROUP BY s.medicalstaffid
),
entries_by_staff AS (
  SELECT
    trim(bw.staffenter)::bigint AS nurse_id,
    COUNT(DISTINCT bw.pcid)::bigint AS entries_made
  FROM public.bloodweek bw
  CROSS JOIN normalized_input ni
  WHERE bw.year = ni.target_year
    AND lower(trim(bw.month)) = ni.target_month
    AND bw.staffenter IS NOT NULL
    AND trim(bw.staffenter) <> ''
    AND trim(bw.staffenter) ~ '^[0-9]+$'
  GROUP BY trim(bw.staffenter)::bigint
),
nurse_groups AS (
  SELECT
    g.staffid,
    STRING_AGG(
      CONCAT(g.ghall, '-', g.gday, '-', g.gshift),
      ' | '
      ORDER BY g.ghall, g.gday, g.gshift
    ) AS assigned_groups
  FROM public.groupsofpatients g
  WHERE g.ismain = true
  GROUP BY g.staffid
),
active_totals AS (
  SELECT COUNT(*)::bigint AS total_patients
  FROM public.patients p
  WHERE p.status = 'Active'
),
month_entries_total AS (
  SELECT COUNT(DISTINCT bw.pcid)::bigint AS entered_count
  FROM public.bloodweek bw
  CROSS JOIN normalized_input ni
  WHERE bw.year = ni.target_year
    AND lower(trim(bw.month)) = ni.target_month
)
SELECT
  s.medicalstaffid::bigint AS nurse_id,
  s.name::text AS nurse_name,
  COALESCE(ap.assigned_patient_count, 0)::bigint AS total_patients,
  COALESCE(eb.entries_made, 0)::bigint AS bw_entered_this_month,
  CASE
    WHEN COALESCE(ap.assigned_patient_count, 0) = 0 THEN 0::numeric
    ELSE ROUND(
      COALESCE(eb.entries_made, 0)::numeric
      / COALESCE(ap.assigned_patient_count, 1)::numeric
      * 100::numeric,
      1
    )
  END AS bw_percentage,
  ng.assigned_groups::text AS assigned_groups
FROM public.staff s
LEFT JOIN assigned_patients ap
  ON s.medicalstaffid = ap.nurse_id
LEFT JOIN entries_by_staff eb
  ON s.medicalstaffid = eb.nurse_id
LEFT JOIN nurse_groups ng
  ON s.medicalstaffid = ng.staffid
WHERE lower(trim(s.staffrole)) = 'nurse'

UNION ALL

SELECT
  0::bigint AS nurse_id,
  'TOTAL'::text AS nurse_name,
  at.total_patients,
  met.entered_count AS bw_entered_this_month,
  CASE
    WHEN at.total_patients = 0 THEN 0::numeric
    ELSE ROUND(
      met.entered_count::numeric
      / at.total_patients::numeric
      * 100::numeric,
      1
    )
  END AS bw_percentage,
  NULL::text AS assigned_groups
FROM active_totals at
CROSS JOIN month_entries_total met;
$function$;
