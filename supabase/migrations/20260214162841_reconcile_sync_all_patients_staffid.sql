-- Reconcile nurse assignments for active patients.
-- Behavior:
-- 1) Assign nstaffid when an active patient matches a main group assignment.
-- 2) Clear nstaffid (set NULL) when no valid main assignment exists.

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
      g.staffid AS desired_nstaffid
    FROM public.patients p
    LEFT JOIN public.groupsofpatients g
      ON p.hall_main = g.ghall
     AND p.shift_main = g.gshift
     AND p.day_main = g.gday
     AND g.ismain = true
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
