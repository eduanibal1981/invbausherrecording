-- Update get_all_latest_labs to return month and date metadata for bloodwork, PTH, and Iron profile
DROP FUNCTION IF EXISTS public.get_all_latest_labs();

CREATE OR REPLACE FUNCTION public.get_all_latest_labs()
 RETURNS TABLE(
   pcid bigint, 
   vaccess text, 
   cbchb real, 
   ue1k real, 
   bca real, 
   bpo4 real, 
   effurr real, 
   effktv real, 
   pthresult real, 
   irontsat real, 
   ironferritin real,
   bw_month text,
   bw_year integer,
   bw_date timestamptz,
   pth_date timestamptz,
   pth_year integer,
   iron_date date,
   iron_year integer
 )
 LANGUAGE sql
 SECURITY DEFINER
AS $function$
  WITH RankedBlood AS (
    SELECT 
      pcid, 
      cbchb, ue1k, bca, bpo4, effurr, effktv,
      month, year, COALESCE(dateofresult, created_at) as bw_date,
      ROW_NUMBER() OVER(PARTITION BY pcid ORDER BY created_at DESC) as rn
    FROM bloodweek
  ),
  LatestBlood AS (
    SELECT * FROM RankedBlood WHERE rn = 1
  ),
  RankedPth AS (
    SELECT 
      pcid, pthresult,
      pthdate, pthyear,
      ROW_NUMBER() OVER(PARTITION BY pcid ORDER BY created_at DESC) as rn
    FROM parathyroid
  ),
  LatestPth AS (
    SELECT * FROM RankedPth WHERE rn = 1
  ),
  RankedIron AS (
    SELECT 
      pcid, irontsat, ironferritin,
      invdate, ironyear,
      ROW_NUMBER() OVER(PARTITION BY pcid ORDER BY created_at DESC) as rn
    FROM ironprofile
  ),
  LatestIron AS (
    SELECT * FROM RankedIron WHERE rn = 1
  )
  SELECT 
    p.pcid, 
    p.vaccess,
    b.cbchb, b.ue1k, b.bca, b.bpo4, b.effurr, b.effktv,
    pt.pthresult,
    i.irontsat, i.ironferritin,
    b.month as bw_month,
    b.year as bw_year,
    b.bw_date,
    pt.pthdate as pth_date,
    pt.pthyear as pth_year,
    i.invdate as iron_date,
    i.ironyear as iron_year
  FROM patients p
  LEFT JOIN LatestBlood b ON p.pcid = b.pcid
  LEFT JOIN LatestPth pt ON p.pcid = pt.pcid
  LEFT JOIN LatestIron i ON p.pcid = i.pcid
  WHERE p.status = 'Active';
$function$;

GRANT EXECUTE ON FUNCTION public.get_all_latest_labs() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_all_latest_labs() TO anon;
GRANT EXECUTE ON FUNCTION public.get_all_latest_labs() TO service_role;

NOTIFY pgrst, 'reload schema';
