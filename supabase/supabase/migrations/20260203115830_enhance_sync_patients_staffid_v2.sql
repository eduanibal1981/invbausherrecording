-- =============================================
-- Drop and recreate enhanced Sync Function
-- Returns count of updated patients
-- =============================================

-- Drop existing function first (it currently returns void)
DROP FUNCTION IF EXISTS sync_all_patients_staffid();

-- Create enhanced version returning integer
CREATE OR REPLACE FUNCTION sync_all_patients_staffid()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  updated_count INTEGER;
BEGIN
  -- Update patients' nstaffid based on their main schedule matching groupsofpatients
  WITH updated AS (
    UPDATE patients p
    SET nstaffid = g.staffid
    FROM groupsofpatients g
    WHERE p.hall_main = g.ghall
      AND p.shift_main = g.gshift
      AND p.day_main = g.gday
      AND g.staffid IS NOT NULL
      AND g.ismain = TRUE  -- Only use main nurse assignments
      AND p.status = 'Active'
      AND p.nstaffid IS DISTINCT FROM g.staffid
    RETURNING p.pcid
  )
  SELECT COUNT(*) INTO updated_count FROM updated;
  
  RETURN updated_count;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION sync_all_patients_staffid() TO authenticated;
GRANT EXECUTE ON FUNCTION sync_all_patients_staffid() TO anon;

COMMENT ON FUNCTION sync_all_patients_staffid() IS 'Syncs patients nstaffid based on their main hall/day/shift assignment. Returns count of updated patients.';;
