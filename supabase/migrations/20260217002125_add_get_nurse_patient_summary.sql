-- Parameterized nurse summary by month/year for Nurse Patient Summary screen.
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
WITH assigned_patients AS (
  SELECT
    s.medicalstaffid AS nurse_id,
    COUNT(DISTINCT p.pcid) AS assigned_patient_count
  FROM public.staff s
  LEFT JOIN public.groupsofpatients g
    ON g.staffid = s.medicalstaffid
   AND g.ismain = true
  LEFT JOIN public.patients p
    ON p.nstaffid = s.medicalstaffid
   AND p.status = 'Active'
  WHERE lower(s.staffrole) = 'nurse'
  GROUP BY s.medicalstaffid
),
entries_by_staff AS (
  SELECT
    bw.staffenter AS staff_id_text,
    COUNT(DISTINCT bw.pcid) FILTER (WHERE bw.cbchb IS NOT NULL) AS entries_made
  FROM public.bloodweek bw
  WHERE bw.year = in_target_year
    AND lower(bw.month) = lower(in_target_month)
    AND bw.staffenter IS NOT NULL
    AND bw.staffenter <> ''
    AND bw.staffenter ~ '^\\d+$'
  GROUP BY bw.staffenter
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
  ON s.medicalstaffid::text = eb.staff_id_text
LEFT JOIN nurse_groups ng
  ON s.medicalstaffid = ng.staffid
WHERE lower(s.staffrole) = 'nurse'

UNION ALL

SELECT
  0::bigint AS nurse_id,
  'TOTAL'::text AS nurse_name,
  (
    SELECT COUNT(*)::bigint
    FROM public.patients p
    WHERE p.status = 'Active'
  ) AS total_patients,
  (
    SELECT COUNT(DISTINCT bw.pcid)::bigint
    FROM public.bloodweek bw
    WHERE bw.year = in_target_year
      AND lower(bw.month) = lower(in_target_month)
      AND bw.cbchb IS NOT NULL
  ) AS bw_entered_this_month,
  CASE
    WHEN (
      SELECT COUNT(*)
      FROM public.patients p
      WHERE p.status = 'Active'
    ) = 0 THEN 0::numeric
    ELSE ROUND(
      (
        SELECT COUNT(DISTINCT bw.pcid)
        FROM public.bloodweek bw
        WHERE bw.year = in_target_year
          AND lower(bw.month) = lower(in_target_month)
          AND bw.cbchb IS NOT NULL
      )::numeric
      / (
        SELECT COUNT(*)
        FROM public.patients p
        WHERE p.status = 'Active'
      )::numeric
      * 100::numeric,
      1
    )
  END AS bw_percentage,
  NULL::text AS assigned_groups;
$function$;
