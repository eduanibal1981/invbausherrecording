-- Use temp_staffid when the primary nurse is on leave.
-- Keeps full reconciliation behavior for active patients.

CREATE OR REPLACE FUNCTION public.sync_all_patients_staffid()
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
  updated_count integer;
BEGIN
  WITH desired AS (
    SELECT
      p.pcid,
      CASE
        WHEN s.is_on_leave IS TRUE THEN COALESCE(g.temp_staffid, g.staffid)::bigint
        ELSE g.staffid::bigint
      END AS desired_nstaffid
    FROM public.patients p
    LEFT JOIN public.groupsofpatients g
      ON p.hall_main = g.ghall
     AND p.shift_main = g.gshift
     AND p.day_main = g.gday
     AND g.ismain = true
    LEFT JOIN public.staff s
      ON s.medicalstaffid = g.staffid
    WHERE p.status = 'Active'
  ),
  updated AS (
    UPDATE public.patients p
       SET nstaffid = d.desired_nstaffid
      FROM desired d
     WHERE p.pcid = d.pcid
       AND p.nstaffid IS DISTINCT FROM d.desired_nstaffid
    RETURNING p.pcid
  )
  SELECT COUNT(*) INTO updated_count FROM updated;

  RETURN updated_count;
END;
$function$;
