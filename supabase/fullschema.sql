


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE EXTENSION IF NOT EXISTS "pgsodium";






COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."bloodweek_efficiency_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Kt/V
    NEW.effktv :=
        public.calculate_effktv(
            NEW.ureapre,
            NEW.ureapost,
            NEW.ufdone,
            NEW.wtpost,
            NEW.timetaken
        );

    -- URR
    NEW.effurr :=
        public.calculate_effurr(
            NEW.ureapre,
            NEW.ureapost
        );

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."bloodweek_efficiency_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."bloodweek_effktv_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.effktv :=
        public.calculate_effktv(
            NEW.ureapre,
            NEW.ureapost,
            NEW.ufdone,
            NEW.wtpost,
            NEW.timetaken
        );

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."bloodweek_effktv_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."bw_zero_to_null"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.cbchb := nullif(new.cbchb, 0);
  new.bca   := nullif(new.bca, 0);
  new.bpo4  := nullif(new.bpo4, 0);
  new.ue1k := nullif(new.ue1k,0);
  new.ureapost := nullif(new.ureapost,0);
  new.ureapre := nullif(new.ureapre,0);
  new.effktv := nullif(new.effktv,0);
  new.effurr := nullif(new.effurr,0);

  return new;
end;
$$;


ALTER FUNCTION "public"."bw_zero_to_null"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_effktv"("p_ureapre" real, "p_ureapost" real, "p_ufdone" double precision, "p_wtpost" double precision, "p_timetaken" double precision) RETURNS real
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    r NUMERIC;
    value_inside_ln NUMERIC;
    result NUMERIC;
BEGIN
    IF p_ureapre IS NULL
       OR p_ureapost IS NULL
       OR p_ufdone IS NULL
       OR p_wtpost IS NULL
       OR p_timetaken IS NULL
       OR p_ureapre <= 0
       OR p_wtpost <= 0
       OR p_timetaken <= 0 THEN
        RETURN NULL;
    END IF;

    r := p_ureapost::NUMERIC / p_ureapre::NUMERIC;
    value_inside_ln := r - (0.008 * p_timetaken);

    IF value_inside_ln <= 0 THEN
        RETURN NULL;
    END IF;

    result :=
        -LN(value_inside_ln)
        + (4 - 3.5 * r) * (p_ufdone::NUMERIC / p_wtpost::NUMERIC);

    RETURN ROUND(result, 2)::REAL;
END;
$$;


ALTER FUNCTION "public"."calculate_effktv"("p_ureapre" real, "p_ureapost" real, "p_ufdone" double precision, "p_wtpost" double precision, "p_timetaken" double precision) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_effurr"("p_ureapre" real, "p_ureapost" real) RETURNS real
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result NUMERIC;
BEGIN
    IF p_ureapre IS NULL
       OR p_ureapost IS NULL
       OR p_ureapre <= 0 THEN
        RETURN NULL;
    END IF;

    result :=
        (1 - (p_ureapost::NUMERIC / p_ureapre::NUMERIC)) * 100;

    RETURN ROUND(result, 1)::REAL;
END;
$$;


ALTER FUNCTION "public"."calculate_effurr"("p_ureapre" real, "p_ureapost" real) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_bloodweek_for_month"("in_year" integer, "in_month" "text") RETURNS "void"
    LANGUAGE "sql"
    AS $$
  insert into public.bloodweek (pcid, month, year)
  select p.pcid, in_month, in_year
  from public.patients p
  where p.status = 'Active'
  on conflict (pcid, month, year) do nothing;
$$;


ALTER FUNCTION "public"."generate_bloodweek_for_month"("in_year" integer, "in_month" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_iron_for_num"("in_year" integer, "in_num" integer) RETURNS "void"
    LANGUAGE "sql"
    AS $$
  insert into public.ironprofile (pcid, ironcollectnum, ironyear)
  select p.pcid, in_num, in_year
  from public.patients p
  where p.status = 'Active'
  on conflict (pcid, ironcollectnum, ironyear) do nothing;
$$;


ALTER FUNCTION "public"."generate_iron_for_num"("in_year" integer, "in_num" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_pth_for_num"("in_year" integer, "in_num" integer) RETURNS "void"
    LANGUAGE "sql"
    AS $$
  insert into public.parathyroid (pcid, pthcollectnum, pthyear)
  select p.pcid, in_num, in_year
  from public.patients p
  where p.status = 'Active'
  on conflict (pcid, pthcollectnum, pthyear) do nothing;
$$;


ALTER FUNCTION "public"."generate_pth_for_num"("in_year" integer, "in_num" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_patient_bloodweek_summary"("in_target_year" integer, "in_target_month" "text") RETURNS TABLE("pcid" bigint, "name" "text", "labgroup" "text", "nstaffid" bigint, "day" "text", "shift" "text", "hallname" "text", "cbchb" real, "cbcplt" real, "cbcwbc" real, "bca" real, "bpo4" real, "balk" real, "ue1k" real, "ue1gfr" real, "ureapre" real, "ureapost" real, "effurr" real, "effktv" real)
    LANGUAGE "plpgsql"
    AS $$
begin
  return query
  with prioritized_schedule as (
    select
      s.pcid,
      s.day,
      s.shift,
      s.hallname,
      case 
        when lower(s.day) = 'saturday' then 1
        when lower(s.day) = 'sunday' then 2
        else 3
      end as priority
    from public.schedules s
  ),
  selected_schedule as (
    select distinct on (ps.pcid)
      ps.pcid,
      ps.day,
      ps.shift,
      ps.hallname
    from prioritized_schedule ps
    order by ps.pcid, ps.priority asc
  ),
  bw as (
    select distinct on (b.pcid)
      b.pcid,
      b.cbchb,
      b.cbcplt,
      b.cbcwbc,
      b.bca,
      b.bpo4,
      b.balk,
      b.ue1k,
      b.ue1gfr,
      b.ureapre,
      b.ureapost,
      b.effurr,
      b.effktv
    from public.bloodweek b
    where b.year = in_target_year
      and lower(b.month) = lower(in_target_month)
    order by b.pcid, b.dateofresult desc
  )
  select
    p.pcid,
    p.name,
    p.labgroup,
    p.nstaffid,
    ss.day,
    ss.shift,
    ss.hallname,
    bw.cbchb,
    bw.cbcplt,
    bw.cbcwbc,
    bw.bca,
    bw.bpo4,
    bw.balk,
    bw.ue1k,
    bw.ue1gfr,
    bw.ureapre,
    bw.ureapost,
    bw.effurr,
    bw.effktv
  from public.patients p
  left join selected_schedule ss on p.pcid = ss.pcid
  left join bw on p.pcid = bw.pcid
  where p.status = 'Active'
  order by p.name;
end;
$$;


ALTER FUNCTION "public"."get_patient_bloodweek_summary"("in_target_year" integer, "in_target_month" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."iron_zero_to_null"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Convert numeric text "0" to NULL
  new.ironnote := nullif(new.ironnote, '0');

  -- Convert real zero values to NULL
  new.irontsat := nullif(new.irontsat, 0);
  new.ironferritin := nullif(new.ironferritin, 0);

  RETURN new;
END;
$$;


ALTER FUNCTION "public"."iron_zero_to_null"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."make_lab_note"("pcid" bigint) RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  note text := '';
  bw   record;
  par  record;
  iron record;
BEGIN
  -- get newest bloodweek row
  SELECT *
  INTO bw
  FROM bloodweek
  WHERE bloodweek.pcid = make_lab_note.pcid
  ORDER BY dateofresult DESC
  LIMIT 1;

  -- get newest PTH row
  SELECT *
  INTO par
  FROM parathyroid
  WHERE parathyroid.pcid = make_lab_note.pcid
  ORDER BY pthdate DESC
  LIMIT 1;

  -- get newest iron row
  SELECT *
  INTO iron
  FROM ironprofile
  WHERE ironprofile.pcid = make_lab_note.pcid
  ORDER BY invdate DESC         -- FIXED
  LIMIT 1;

  -- Check BLOODWEEK values
  IF bw.cbchb IS NOT NULL AND (
       bw.cbchb < (SELECT minvalue FROM labnormalrange WHERE labcode='HB')
    OR bw.cbchb > (SELECT maxvalue FROM labnormalrange WHERE labcode='HB')
  ) THEN
      note := note || 'HB, ';
  END IF;

  IF bw.bca IS NOT NULL AND (
       bw.bca < (SELECT minvalue FROM labnormalrange WHERE labcode='CA')
    OR bw.bca > (SELECT maxvalue FROM labnormalrange WHERE labcode='CA')
  ) THEN
      note := note || 'Ca, ';
  END IF;

  IF bw.bpo4 IS NOT NULL AND (
       bw.bpo4 < (SELECT minvalue FROM labnormalrange WHERE labcode='PO4')
    OR bw.bpo4 > (SELECT maxvalue FROM labnormalrange WHERE labcode='PO4')
  ) THEN
      note := note || 'PO4, ';
  END IF;

  IF bw.ue1k IS NOT NULL AND (
       bw.ue1k < (SELECT minvalue FROM labnormalrange WHERE labcode='K')
    OR bw.ue1k > (SELECT maxvalue FROM labnormalrange WHERE labcode='K')
  ) THEN
      note := note || 'K, ';
  END IF;

  -- Check PTH
  IF par.pthresult IS NOT NULL AND (
       par.pthresult < (SELECT minvalue FROM labnormalrange WHERE labcode='PTH')
    OR par.pthresult > (SELECT maxvalue FROM labnormalrange WHERE labcode='PTH')
  ) THEN
      note := note || 'PTH, ';
  END IF;

  -- Check IRON profile
  IF iron.ironferritin IS NOT NULL AND (
       iron.ironferritin < (SELECT minvalue FROM labnormalrange WHERE labcode='FER')
    OR iron.ironferritin > (SELECT maxvalue FROM labnormalrange WHERE labcode='FER')
  ) THEN
      note := note || 'Ferritin, ';
  END IF;

  IF iron.irontsat IS NOT NULL AND (
       iron.irontsat < (SELECT minvalue FROM labnormalrange WHERE labcode='TSAT')
    OR iron.irontsat > (SELECT maxvalue FROM labnormalrange WHERE labcode='TSAT')
  ) THEN
      note := note || 'Check TSAT, ';
  END IF;

  RETURN trim(trailing ', ' FROM note);
END;
$$;


ALTER FUNCTION "public"."make_lab_note"("pcid" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."par_zero_to_null"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.pthresult := nullif(new.pthresult, 0);
  return new;
end;
$$;


ALTER FUNCTION "public"."par_zero_to_null"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."process_single_bloodweek_json"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  rec jsonb;

  pcid_value      bigint;
  year_value      int;
  month_value     text;

  cbchb_value     numeric;
  bca_value       numeric;
  bpo4_value      numeric;
  ue1k_value      numeric;
  ureapre_value   numeric;
  ureapost_value  numeric;

  staffenter_value bigint;
BEGIN

  -- Run only for bloodweek table
  IF NEW.tablename <> 'bloodweek' THEN
    RETURN NEW;
  END IF;

  -- First JSON object
  rec := NEW.datajson->0;

  -- Extract fields
  pcid_value      := (rec->>'pcid')::bigint;
  year_value      := (rec->>'year')::int;
  month_value     := rec->>'month';
  cbchb_value     := (rec->>'cbchb')::numeric;
  bca_value       := (rec->>'bca')::numeric;
  bpo4_value      := (rec->>'bpo4')::numeric;
  ue1k_value      := (rec->>'ue1k')::numeric;
  ureapre_value   := (rec->>'ureapre')::numeric;
  ureapost_value  := (rec->>'ureapost')::numeric;

  -- TAKE staffid FROM savebyjson TABLE
  staffenter_value := NEW.staffid;

  -- UPSERT into bloodweek table
  INSERT INTO bloodweek (
    pcid, year, month,
    cbchb, bca, bpo4, ue1k, ureapre, ureapost,
    staffenter
  )
  VALUES (
    pcid_value, year_value, month_value,
    cbchb_value, bca_value, bpo4_value, ue1k_value, ureapre_value, ureapost_value,
    staffenter_value
  )
  ON CONFLICT (pcid, year, month)
  DO UPDATE SET
    cbchb       = EXCLUDED.cbchb,
    bca         = EXCLUDED.bca,
    bpo4        = EXCLUDED.bpo4,
    ue1k        = EXCLUDED.ue1k,
    ureapre     = EXCLUDED.ureapre,
    ureapost    = EXCLUDED.ureapost,
    staffenter  = EXCLUDED.staffenter;

  -- mark success
  UPDATE savebyjson
  SET isupsert = true
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."process_single_bloodweek_json"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."process_single_ironprofile_json"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  rec jsonb;

  pcid_value        bigint;
  invdate_value     timestamp;
  ironyear_value    int;

  irontsat_value       numeric;
  ironferritin_value   numeric;
  ironnote_value       numeric;
BEGIN

  -- Run only for ironprofile table
  IF NEW.tablename <> 'ironprofile' THEN
    RETURN NEW;
  END IF;

  -- Extract first JSON object
  rec := NEW.datajson->0;

  -- Extract primary key columns
  pcid_value     := (rec->>'pcid')::bigint;
  invdate_value := to_date(rec->>'invdate', 'DD/MM/YYYY');
  ironyear_value := (rec->>'ironyear')::int;

  -- Extract data columns
  irontsat_value      := (rec->>'irontsat')::numeric;
  ironferritin_value  := (rec->>'ironferritin')::numeric;
  ironnote_value      := (rec->>'ironnote')::numeric;

  -- UPSERT into ironprofile
  INSERT INTO ironprofile (
    pcid, invdate, ironyear,
    irontsat, ironferritin, ironnote
  )
  VALUES (
    pcid_value, invdate_value, ironyear_value,
    irontsat_value, ironferritin_value, ironnote_value
  )
  ON CONFLICT (pcid, invdate)
  DO UPDATE SET
    ironyear      = EXCLUDED.ironyear,
    irontsat      = EXCLUDED.irontsat,
    ironferritin  = EXCLUDED.ironferritin,
    ironnote      = EXCLUDED.ironnote;

  -- Mark as processed
  UPDATE savebyjson
  SET isupsert = true
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."process_single_ironprofile_json"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."process_single_pthjson"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  rec jsonb;
  pcid_value bigint;
  pthdate_value timestamp;
  pthresult_value numeric;
  pthyear_value int;
BEGIN

  -- run ONLY for parathyroid table
  IF NEW.tablename <> 'parathyroid' THEN
    RETURN NEW;
  END IF;

  -- extract JSON
  rec := NEW.datajson->0;

  pcid_value       := (rec->>'pcid')::bigint;
  pthdate_value    := to_timestamp(rec->>'pthdate', 'DD/MM/YYYY')::timestamp;
  pthresult_value  := (rec->>'pthresult')::numeric;
  pthyear_value    := (rec->>'pthyear')::int;

  -- upsert into parathyroid table
  INSERT INTO parathyroid (pcid, pthdate, pthresult, pthyear)
  VALUES (pcid_value, pthdate_value, pthresult_value, pthyear_value)
  ON CONFLICT (pcid, pthdate)
  DO UPDATE SET
    pthresult = EXCLUDED.pthresult,
    pthyear   = EXCLUDED.pthyear;

  -- mark success
  UPDATE savebyjson
  SET isupsert = true
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."process_single_pthjson"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."refresh_media_status"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Update has_doppler
  UPDATE public.patients
  SET has_doppler = EXISTS (
      SELECT 1
      FROM public.doppplerslinks d
      WHERE d.pcid::text = public.patients.pcid::text
  )
  WHERE pcid IS NOT NULL;

  -- Update has_ecg
  UPDATE public.patients
  SET has_ecg = EXISTS (
      SELECT 1
      FROM public.ecg_links e
      WHERE e.pcid::text = public.patients.pcid::text
  )
  WHERE pcid IS NOT NULL;
END;
$$;


ALTER FUNCTION "public"."refresh_media_status"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_all_patients_staffid"() RETURNS integer
    LANGUAGE "plpgsql"
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


ALTER FUNCTION "public"."sync_all_patients_staffid"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."sync_all_patients_staffid"() IS 'Syncs patients nstaffid based on their main hall/day/shift assignment. Returns count of updated patients.';



CREATE OR REPLACE FUNCTION "public"."sync_patients_main_schedule"() RETURNS TABLE("updated_count" integer)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  total_updated integer := 0;
  main_rec RECORD;
BEGIN
  -- For each defined main schedule
  FOR main_rec IN SELECT * FROM main_schedules LOOP
    -- Update patients who have this schedule entry
    UPDATE patients p
    SET hall_main = main_rec.hall,
        day_main = main_rec.day,
        shift_main = main_rec.shift
    FROM schedules s
    WHERE s.pcid = p.pcid
      AND s.hallname = main_rec.hall
      AND s.day = main_rec.day
      AND s.shift = main_rec.shift
      AND (p.hall_main IS DISTINCT FROM main_rec.hall
           OR p.day_main IS DISTINCT FROM main_rec.day
           OR p.shift_main IS DISTINCT FROM main_rec.shift);
    
    total_updated := total_updated + (SELECT COUNT(*) FROM patients WHERE hall_main = main_rec.hall AND day_main = main_rec.day AND shift_main = main_rec.shift);
  END LOOP;
  
  RETURN QUERY SELECT total_updated;
END;
$$;


ALTER FUNCTION "public"."sync_patients_main_schedule"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_bloodweek_from_sheet"("in_pcid" bigint, "in_month" "text", "in_year" integer, "in_cbchb" real DEFAULT NULL::real, "in_cbcplt" real DEFAULT NULL::real, "in_cbcwbc" real DEFAULT NULL::real, "in_bca" real DEFAULT NULL::real, "in_bpo4" real DEFAULT NULL::real, "in_ue1k" real DEFAULT NULL::real, "in_ureapre" real DEFAULT NULL::real, "in_ureapost" real DEFAULT NULL::real) RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
begin
  -- Try to update if record exists
  update public.bloodweek
  set
    cbchb = coalesce(in_cbchb, cbchb),
    cbcplt = coalesce(in_cbcplt, cbcplt),
    cbcwbc = coalesce(in_cbcwbc, cbcwbc),
    bca = coalesce(in_bca, bca),
    bpo4 = coalesce(in_bpo4, bpo4),
    ue1k = coalesce(in_ue1k, ue1k),
    ureapre = coalesce(in_ureapre, ureapre),
    ureapost = coalesce(in_ureapost, ureapost)
  where pcid = in_pcid
    and month = in_month
    and year = in_year;

  -- If no row was updated, insert new one
  if not found then
    insert into public.bloodweek (
      pcid, month, year, cbchb, cbcplt, cbcwbc, bca, bpo4, ue1k
    )
    values (
      in_pcid, in_month, in_year,
      in_cbchb, in_cbcplt, in_cbcwbc, in_bca, in_bpo4, in_ue1k
    )
    on conflict (pcid, month, year) do update
    set
      cbchb = coalesce(excluded.cbchb, bloodweek.cbchb),
      cbcplt = coalesce(excluded.cbcplt, bloodweek.cbcplt),
      cbcwbc = coalesce(excluded.cbcwbc, bloodweek.cbcwbc),
      bca = coalesce(excluded.bca, bloodweek.bca),
      bpo4 = coalesce(excluded.bpo4, bloodweek.bpo4),
      ue1k = coalesce(excluded.ue1k, bloodweek.ue1k),
      ureapre = coalesce(excluded.ureapre, bloodweek.ureapre),
      ureapost = coalesce(excluded.ureapost, bloodweek.ureapost);
  end if;
end;
$$;


ALTER FUNCTION "public"."update_bloodweek_from_sheet"("in_pcid" bigint, "in_month" "text", "in_year" integer, "in_cbchb" real, "in_cbcplt" real, "in_cbcwbc" real, "in_bca" real, "in_bpo4" real, "in_ue1k" real, "in_ureapre" real, "in_ureapost" real) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_bloodweek_from_sheet_bulk"("in_data" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
begin
  insert into public.bloodweek (
    pcid, month, year,
    cbchb, cbcplt, cbcwbc,
    bca, bpo4, ue1k,
    ureapre, ureapost
  )
  select 
    (x->>'pcid')::bigint,
    x->>'month',
    (x->>'year')::integer,
    (x->>'cbchb')::real,
    (x->>'cbcplt')::real,
    (x->>'cbcwbc')::real,
    (x->>'bca')::real,
    (x->>'bpo4')::real,
    (x->>'ue1k')::real,
    (x->>'ureapre')::real,
    (x->>'ureapost')::real
  from jsonb_array_elements(in_data) as x
  on conflict (pcid, month, year)
  do update set
    cbchb = excluded.cbchb,
    cbcplt = excluded.cbcplt,
    cbcwbc = excluded.cbcwbc,
    bca = excluded.bca,
    bpo4 = excluded.bpo4,
    ue1k = excluded.ue1k,
    ureapre = excluded.ureapre,
    ureapost = excluded.ureapost,
    created_at = now();
end;
$$;


ALTER FUNCTION "public"."update_bloodweek_from_sheet_bulk"("in_data" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_group_count_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Update the count for the affected hall/shift/day
    INSERT INTO public.groupsofpatients (ghall, gshift, gday, gcount, staffid, ismcollected)
    SELECT 
        COALESCE(NEW.hallname, OLD.hallname),
        COALESCE(NEW.shift, OLD.shift),
        COALESCE(NEW.day, OLD.day),
        COUNT(*) as gcount,
        NULL as staffid,
        false as ismcollected
    FROM public.schedules
    WHERE hallname = COALESCE(NEW.hallname, OLD.hallname)
      AND shift = COALESCE(NEW.shift, OLD.shift)
      AND day = COALESCE(NEW.day, OLD.day)
    GROUP BY hallname, shift, day
    ON CONFLICT (ghall, gshift, gday) DO UPDATE SET
        gcount = EXCLUDED.gcount;
    
    RETURN NULL;
END;
$$;


ALTER FUNCTION "public"."update_group_count_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_groupsofpatients_staffid"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  target_days text[];
BEGIN
  -- Prevent recursive loop when we update the same table inside the trigger
  IF pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;

  -- Decide which 3-day set this row belongs to
  IF NEW.gday IN ('Saturday', 'Monday', 'Wednesday') THEN
    target_days := ARRAY['Saturday', 'Monday', 'Wednesday'];
  ELSIF NEW.gday IN ('Sunday', 'Tuesday', 'Thursday') THEN
    target_days := ARRAY['Sunday', 'Tuesday', 'Thursday'];
  ELSE
    -- Not part of either schedule set
    RETURN NEW;
  END IF;

  -- Propagate staffid (including NULL) to all days in the same set for same hall+shift
  UPDATE public.groupsofpatients gp
     SET staffid = NEW.staffid
   WHERE gp.ghall  = NEW.ghall
     AND gp.gshift = NEW.gshift
     AND gp.gday   = ANY(target_days)
     AND (gp.staffid IS DISTINCT FROM NEW.staffid);

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_groupsofpatients_staffid"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_hall_schedule_timestamp"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_hall_schedule_timestamp"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_patient_isdrreviewed"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  UPDATE patients p
  SET isdrreviwed = NEW.isdrrevbw
  WHERE p.pcid = NEW.pcid
    AND p.lastbwcollected = NEW.month;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_patient_isdrreviewed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_patient_lastbwcollected"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  update patients p
  set lastbwcollected = bw.month
  from (
     select month, year
     from bloodweek
     where pcid = new.pcid
       and cbchb is not null  -- << only months with hb
     order by to_date(year::text || '-' || month, 'YYYY-Mon') desc
     limit 1
  ) bw
  where p.pcid = new.pcid;

  return new;
end;
$$;


ALTER FUNCTION "public"."update_patient_lastbwcollected"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_patient_lastlabnote"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  update patients
  set lastlabnote = make_lab_note(NEW.pcid)
  where patients.pcid = NEW.pcid;

  return NEW;
end;
$$;


ALTER FUNCTION "public"."update_patient_lastlabnote"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_patient_schedule"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  WITH prioritized_schedule AS (
    SELECT
      s.pcid,
      s.hallname,
      s.day,
      s.shift,
      CASE 
        WHEN LOWER(s.day) = 'saturday' THEN 1
        WHEN LOWER(s.day) = 'sunday'   THEN 2
        ELSE 3
      END AS priority
    FROM public.schedules s
  ),
  selected_schedule AS (
    SELECT DISTINCT ON (ps.pcid)
      ps.pcid,
      ps.hallname,
      ps.day,
      ps.shift,
      ps.priority       -- include priority here!
    FROM prioritized_schedule ps
    ORDER BY ps.pcid, ps.priority
  )
  UPDATE public.patients p
  SET
    hall_main  = CASE WHEN ss.priority <= 2 THEN ss.hallname ELSE NULL END,
    day_main   = CASE WHEN ss.priority <= 2 THEN ss.day ELSE NULL END,
    shift_main = CASE WHEN ss.priority <= 2 THEN ss.shift ELSE NULL END
  FROM selected_schedule ss
  WHERE p.pcid = ss.pcid;
END;
$$;


ALTER FUNCTION "public"."update_patient_schedule"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_patients_staffid"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  UPDATE public.patients p
  SET nstaffid = NEW.staffid
  WHERE p.hall_main = NEW.ghall
    AND p.day_main  = NEW.gday
    AND p.shift_main = NEW.gshift;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_patients_staffid"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."antibiotics" (
    "abid" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "abname" "text",
    "doseregim" "text",
    "dosetotal" integer,
    "startdate" "date",
    "pcid" bigint,
    "enddate" "date",
    "dosetoday" integer,
    "iscompleted" boolean,
    "lastgiven" "date"
);


ALTER TABLE "public"."antibiotics" OWNER TO "postgres";


ALTER TABLE "public"."antibiotics" ALTER COLUMN "abid" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."antibiotics_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."anticoagulant" (
    "antiid" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "antiname" "text",
    "antidose" "text",
    "dateoforder" "date",
    "pcid" bigint
);


ALTER TABLE "public"."anticoagulant" OWNER TO "postgres";


ALTER TABLE "public"."anticoagulant" ALTER COLUMN "antiid" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."anticoagulant_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."bloodweek" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "cbchb" real,
    "cbcplt" real,
    "cbcwbc" real,
    "bca" real,
    "bpo4" real,
    "balk" real,
    "ue1k" real,
    "ue1gfr" real,
    "ureapre" real,
    "ureapost" real,
    "dateofresult" timestamp with time zone,
    "effurr" real,
    "effktv" real,
    "lablastsyncat" timestamp with time zone,
    "pcid" bigint NOT NULL,
    "drreviewed" "text",
    "month" "text" NOT NULL,
    "year" integer NOT NULL,
    "staffenter" "text",
    "needcolect" boolean,
    "monthnum" smallint GENERATED ALWAYS AS (
CASE "month"
    WHEN 'January'::"text" THEN 1
    WHEN 'February'::"text" THEN 2
    WHEN 'March'::"text" THEN 3
    WHEN 'April'::"text" THEN 4
    WHEN 'May'::"text" THEN 5
    WHEN 'June'::"text" THEN 6
    WHEN 'July'::"text" THEN 7
    WHEN 'August'::"text" THEN 8
    WHEN 'September'::"text" THEN 9
    WHEN 'October'::"text" THEN 10
    WHEN 'November'::"text" THEN 11
    WHEN 'December'::"text" THEN 12
    ELSE NULL::integer
END) STORED,
    "ufdone" double precision,
    "timetaken" double precision,
    "wtpost" double precision,
    "isdrrevbw" boolean,
    CONSTRAINT "chk_timetaken_reasonable" CHECK ((("timetaken" IS NULL) OR (("timetaken" >= (1.5)::double precision) AND ("timetaken" <= (6)::double precision)))),
    CONSTRAINT "chk_ufdone_nonnegative" CHECK ((("ufdone" IS NULL) OR ("ufdone" >= (0)::double precision))),
    CONSTRAINT "chk_ureapost_positive" CHECK ((("ureapost" IS NULL) OR ("ureapost" > (0)::double precision))),
    CONSTRAINT "chk_ureapre_positive" CHECK ((("ureapre" IS NULL) OR ("ureapre" > (0)::double precision))),
    CONSTRAINT "chk_wtpost_positive" CHECK ((("wtpost" IS NULL) OR ("wtpost" > (0)::double precision)))
);


ALTER TABLE "public"."bloodweek" OWNER TO "postgres";


ALTER TABLE "public"."bloodweek" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."bloodweek_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."bloodweekgroups" (
    "groupname" "text" NOT NULL,
    "doday" "text",
    "nextmonth" integer,
    "datetocollect" "date"
);


ALTER TABLE "public"."bloodweekgroups" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."dialyzer" (
    "dzid" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "pcid" bigint,
    "dztype" "text",
    "dzcomment" "text",
    "datesync" "date"
);


ALTER TABLE "public"."dialyzer" OWNER TO "postgres";


ALTER TABLE "public"."dialyzer" ALTER COLUMN "dzid" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."dialyzer_dzid_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."doppplerslinks" (
    "id" bigint NOT NULL,
    "pcid" "text" NOT NULL,
    "piclink" "text",
    "thumbnail_url" "text",
    "medium_url" "text",
    "large_url" "text",
    "full_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."doppplerslinks" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."doppplerslinks_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."doppplerslinks_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."doppplerslinks_id_seq" OWNED BY "public"."doppplerslinks"."id";



CREATE TABLE IF NOT EXISTS "public"."dryweight" (
    "id" bigint NOT NULL,
    "createdat" timestamp with time zone DEFAULT "now"() NOT NULL,
    "dryweight" real,
    "pcid" bigint,
    "lastsyncdate" timestamp without time zone,
    "orderdate" "date"
);


ALTER TABLE "public"."dryweight" OWNER TO "postgres";


ALTER TABLE "public"."dryweight" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."dryweight_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."ecg_links" (
    "id" bigint NOT NULL,
    "pcid" bigint NOT NULL,
    "piclink" "text",
    "thumbnail_url" "text",
    "medium_url" "text",
    "large_url" "text",
    "full_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "clinicalnote" "text"
);


ALTER TABLE "public"."ecg_links" OWNER TO "postgres";


ALTER TABLE "public"."ecg_links" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."ecg_links_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."halls" (
    "hallname" "text" NOT NULL,
    "totalbeds" integer NOT NULL
);


ALTER TABLE "public"."halls" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."schedules" (
    "scheduleid" bigint NOT NULL,
    "pcid" bigint NOT NULL,
    "created_at" timestamp without time zone DEFAULT "now"(),
    "day" "text",
    "shift" "text" NOT NULL,
    "ispwithus" boolean,
    "schedtype" "text",
    "hallname" "text",
    "tempdate" "date",
    "replaceday" "date"
);


ALTER TABLE "public"."schedules" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."free_beds" AS
 WITH "days" AS (
         SELECT DISTINCT "schedules"."day"
           FROM "public"."schedules"
        ), "shifts" AS (
         SELECT DISTINCT "schedules"."shift"
           FROM "public"."schedules"
          WHERE ("schedules"."shift" IS NOT NULL)
        )
 SELECT "h"."hallname" AS "hall_name",
    "dd"."day",
    "ds"."shift",
    ("h"."totalbeds" - COALESCE("s"."active_count", (0)::bigint)) AS "free_beds"
   FROM ((("public"."halls" "h"
     CROSS JOIN "days" "dd")
     CROSS JOIN "shifts" "ds")
     LEFT JOIN ( SELECT "schedules"."hallname" AS "hall_name",
            "schedules"."day",
            "schedules"."shift",
            "count"(*) AS "active_count"
           FROM "public"."schedules"
          WHERE ("schedules"."ispwithus" = true)
          GROUP BY "schedules"."hallname", "schedules"."day", "schedules"."shift") "s" ON ((("h"."hallname" = "s"."hall_name") AND ("dd"."day" = "s"."day") AND ("ds"."shift" = "s"."shift"))));


ALTER TABLE "public"."free_beds" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."free_beds_c" AS
 WITH "days" AS (
         SELECT DISTINCT "schedules"."day"
           FROM "public"."schedules"
        ), "shifts" AS (
         SELECT DISTINCT "schedules"."shift"
           FROM "public"."schedules"
          WHERE ("schedules"."shift" IS NOT NULL)
        )
 SELECT "h"."hallname" AS "hall_name",
    "dd"."day",
    "ds"."shift",
    ("h"."totalbeds" - COALESCE("s"."active_count", (0)::bigint)) AS "free_beds"
   FROM ((("public"."halls" "h"
     CROSS JOIN "days" "dd")
     CROSS JOIN "shifts" "ds")
     LEFT JOIN ( SELECT "schedules"."hallname" AS "hall_name",
            "schedules"."day",
            "schedules"."shift",
            "count"(*) AS "active_count"
           FROM "public"."schedules"
          WHERE ("schedules"."ispwithus" = true)
          GROUP BY "schedules"."hallname", "schedules"."day", "schedules"."shift") "s" ON ((("h"."hallname" = "s"."hall_name") AND ("dd"."day" = "s"."day") AND ("ds"."shift" = "s"."shift"))))
  WHERE ("ds"."shift" IS NOT NULL);


ALTER TABLE "public"."free_beds_c" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."free_beds_per_day_shift" AS
 WITH "days" AS (
         SELECT DISTINCT "schedules"."day"
           FROM "public"."schedules"
        ), "shifts" AS (
         SELECT DISTINCT "schedules"."shift"
           FROM "public"."schedules"
        )
 SELECT "h"."hallname" AS "hall_name",
    "dd"."day",
    "ds"."shift",
    ("h"."totalbeds" - COALESCE("s"."active_count", (0)::bigint)) AS "free_beds"
   FROM ((("public"."halls" "h"
     CROSS JOIN "days" "dd")
     CROSS JOIN "shifts" "ds")
     LEFT JOIN ( SELECT "schedules"."hallname" AS "hall_name",
            "schedules"."day",
            "schedules"."shift",
            "count"(*) AS "active_count"
           FROM "public"."schedules"
          WHERE ("schedules"."ispwithus" = true)
          GROUP BY "schedules"."hallname", "schedules"."day", "schedules"."shift") "s" ON ((("h"."hallname" = "s"."hall_name") AND ("dd"."day" = "s"."day") AND ("ds"."shift" = "s"."shift"))));


ALTER TABLE "public"."free_beds_per_day_shift" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."groupsofpatients" (
    "ghall" "text" NOT NULL,
    "gshift" "text" NOT NULL,
    "gday" "text" NOT NULL,
    "gcount" integer,
    "staffid" integer,
    "ismcollected" boolean DEFAULT false NOT NULL,
    "ismain" boolean,
    "temp_staffid" integer
);


ALTER TABLE "public"."groupsofpatients" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."hall_schedule_config" (
    "id" integer NOT NULL,
    "hallname" "text" NOT NULL,
    "day_name" "text" NOT NULL,
    "shift_name" "text" NOT NULL,
    "is_active" boolean DEFAULT true,
    "effective_from" "date" DEFAULT CURRENT_DATE,
    "effective_to" "date",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."hall_schedule_config" OWNER TO "postgres";


COMMENT ON TABLE "public"."hall_schedule_config" IS 'Configurable hall-day-shift schedule. Change is_active or set effective_to date to modify without deleting records.';



CREATE SEQUENCE IF NOT EXISTS "public"."hall_schedule_config_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."hall_schedule_config_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."hall_schedule_config_id_seq" OWNED BY "public"."hall_schedule_config"."id";



CREATE TABLE IF NOT EXISTS "public"."history" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone,
    "isdm" boolean,
    "ishtn" boolean,
    "isihd" boolean,
    "pdiagnosis" "text",
    "pallergy" "text",
    "diaglastsyncat" timestamp with time zone,
    "pcid" bigint NOT NULL,
    "phistory" "text"
);


ALTER TABLE "public"."history" OWNER TO "postgres";


ALTER TABLE "public"."history" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."history_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."inr" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "pcid" bigint,
    "result" real,
    "routinday" "text"
);


ALTER TABLE "public"."inr" OWNER TO "postgres";


ALTER TABLE "public"."inr" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."inr_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."ironprofile" (
    "created_at" timestamp with time zone DEFAULT "now"(),
    "irontsat" real,
    "ironferritin" real,
    "tttmedical" "text",
    "ironnote" "text",
    "pthlastsyncat" timestamp with time zone,
    "pcid" bigint NOT NULL,
    "invdate" "date" NOT NULL,
    "ironyear" integer NOT NULL,
    "isdrreviron" boolean
);


ALTER TABLE "public"."ironprofile" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."labdays" (
    "labday" "text" NOT NULL
);


ALTER TABLE "public"."labdays" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."labnormalrange" (
    "labcode" "text" NOT NULL,
    "minvalue" real,
    "maxvalue" real
);


ALTER TABLE "public"."labnormalrange" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."logs" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "pcid" integer,
    "action" "text",
    "data" "text",
    "staffid" integer
);


ALTER TABLE "public"."logs" OWNER TO "postgres";


ALTER TABLE "public"."logs" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."logs_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."medicationstb" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "medicbone" "text",
    "medicHb" "text",
    "medicOther" "text",
    "pcid" bigint,
    "note" "text"
);


ALTER TABLE "public"."medicationstb" OWNER TO "postgres";


ALTER TABLE "public"."medicationstb" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."medicationstb_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."patients" (
    "pcid" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "name" "text" NOT NULL,
    "phone" "text",
    "email" "text",
    "plastsyncat" timestamp with time zone,
    "labgroup" "text" DEFAULT 'Non Assigned'::"text",
    "dstaffid" bigint,
    "nstaffid" bigint,
    "inposition" boolean,
    "outpostioncause" "text",
    "sex" "text",
    "hall_main" "text",
    "status" "text" DEFAULT 'Active'::"text",
    "height" real,
    "returndate" "date",
    "ourunit" boolean,
    "birthdate" "date",
    "lastposthdupdate" "date",
    "nextduebw" "date",
    "dialyzer" "text",
    "vaccess" "text",
    "heparin" "text",
    "lastbwcollected" "text",
    "lastlabnote" "text",
    "day_main" "text",
    "shift_main" "text",
    "isdrreviwed" boolean,
    "has_doppler" boolean,
    "has_ecg" boolean,
    CONSTRAINT "patients_status_check" CHECK (("status" = ANY (ARRAY['Active'::"text", 'On Admission'::"text", 'On Travel'::"text", 'Other'::"text"])))
);


ALTER TABLE "public"."patients" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."staff" (
    "medicalstaffid" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "name" "text" NOT NULL,
    "phone" "text",
    "email" "text",
    "dlastsyncat" timestamp with time zone,
    "staffrole" "text",
    "leavegodate" "date",
    "leavbackdate" "date",
    "isonwork" boolean,
    "userid" "uuid" NOT NULL,
    "fullname" "text",
    "fcm_token" "text",
    "is_on_leave" boolean DEFAULT false
);


ALTER TABLE "public"."staff" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."nurse_patient_summary" AS
 WITH "current_month" AS (
         SELECT "to_char"((CURRENT_DATE)::timestamp with time zone, 'FMMonth'::"text") AS "month_name",
            (EXTRACT(year FROM CURRENT_DATE))::integer AS "year_num"
        ), "assigned_patients" AS (
         SELECT "s"."medicalstaffid" AS "nurse_id",
            "count"(DISTINCT "p"."pcid") AS "assigned_patient_count"
           FROM (("public"."staff" "s"
             LEFT JOIN "public"."groupsofpatients" "g" ON ((("g"."staffid" = "s"."medicalstaffid") AND ("g"."ismain" = true))))
             LEFT JOIN "public"."patients" "p" ON ((("p"."nstaffid" = "s"."medicalstaffid") AND ("p"."status" = 'Active'::"text"))))
          WHERE ("lower"("s"."staffrole") = 'nurse'::"text")
          GROUP BY "s"."medicalstaffid"
        ), "entries_by_staff" AS (
         SELECT "bw"."staffenter" AS "staff_id_text",
            "count"(DISTINCT "bw"."pcid") FILTER (WHERE ("bw"."cbchb" IS NOT NULL)) AS "entries_made"
           FROM ("public"."bloodweek" "bw"
             CROSS JOIN "current_month" "cm")
          WHERE (("bw"."year" = "cm"."year_num") AND ("bw"."month" = "cm"."month_name") AND ("bw"."staffenter" IS NOT NULL) AND ("bw"."staffenter" <> ''::"text") AND ("bw"."staffenter" ~ '^\d+$'::"text"))
          GROUP BY "bw"."staffenter"
        ), "nurse_groups" AS (
         SELECT "g"."staffid",
            "string_agg"("concat"("g"."ghall", '-', "g"."gday", '-', "g"."gshift"), ' | '::"text" ORDER BY "g"."ghall", "g"."gday", "g"."gshift") AS "assigned_groups"
           FROM "public"."groupsofpatients" "g"
          WHERE ("g"."ismain" = true)
          GROUP BY "g"."staffid"
        )
 SELECT "s"."medicalstaffid" AS "nurse_id",
    "s"."name" AS "nurse_name",
    COALESCE("ap"."assigned_patient_count", (0)::bigint) AS "total_patients",
    COALESCE("eb"."entries_made", (0)::bigint) AS "bw_entered_this_month",
        CASE
            WHEN (COALESCE("ap"."assigned_patient_count", (0)::bigint) = 0) THEN (0)::numeric
            ELSE "round"((((COALESCE("eb"."entries_made", (0)::bigint))::numeric / (COALESCE("ap"."assigned_patient_count", (1)::bigint))::numeric) * (100)::numeric), 1)
        END AS "bw_percentage",
    "ng"."assigned_groups"
   FROM ((("public"."staff" "s"
     LEFT JOIN "assigned_patients" "ap" ON (("s"."medicalstaffid" = "ap"."nurse_id")))
     LEFT JOIN "entries_by_staff" "eb" ON ((("s"."medicalstaffid")::"text" = "eb"."staff_id_text")))
     LEFT JOIN "nurse_groups" "ng" ON (("s"."medicalstaffid" = "ng"."staffid")))
  WHERE ("lower"("s"."staffrole") = 'nurse'::"text")
UNION ALL
 SELECT 0 AS "nurse_id",
    'TOTAL'::"text" AS "nurse_name",
    ( SELECT "count"(*) AS "count"
           FROM "public"."patients"
          WHERE ("patients"."status" = 'Active'::"text")) AS "total_patients",
    ( SELECT "count"(DISTINCT "bw"."pcid") AS "count"
           FROM ("public"."bloodweek" "bw"
             CROSS JOIN "current_month" "cm")
          WHERE (("bw"."year" = "cm"."year_num") AND ("bw"."month" = "cm"."month_name") AND ("bw"."cbchb" IS NOT NULL))) AS "bw_entered_this_month",
        CASE
            WHEN (( SELECT "count"(*) AS "count"
               FROM "public"."patients"
              WHERE ("patients"."status" = 'Active'::"text")) = 0) THEN (0)::numeric
            ELSE "round"((((( SELECT "count"(DISTINCT "bw"."pcid") AS "count"
               FROM ("public"."bloodweek" "bw"
                 CROSS JOIN "current_month" "cm")
              WHERE (("bw"."year" = "cm"."year_num") AND ("bw"."month" = "cm"."month_name") AND ("bw"."cbchb" IS NOT NULL))))::numeric / (( SELECT "count"(*) AS "count"
               FROM "public"."patients"
              WHERE ("patients"."status" = 'Active'::"text")))::numeric) * (100)::numeric), 1)
        END AS "bw_percentage",
    NULL::"text" AS "assigned_groups"
   FROM "current_month";


ALTER TABLE "public"."nurse_patient_summary" OWNER TO "postgres";


COMMENT ON VIEW "public"."nurse_patient_summary" IS 'Monthly nurse performance: assigned patients vs BW entries made. 
bw_entered_this_month = entries made BY this staff (not whose patient it is).
bw_percentage can exceed 100% if nurse enters more than their assigned patients.
Resets automatically each month.';



CREATE TABLE IF NOT EXISTS "public"."parathyroid" (
    "created_at" timestamp with time zone DEFAULT "now"(),
    "pthresult" real,
    "pthdate" timestamp with time zone NOT NULL,
    "treatmentnote" "text",
    "pthscan" "text",
    "pthlastsyncat" timestamp with time zone,
    "pcid" bigint NOT NULL,
    "pthyear" integer NOT NULL,
    "isdrrevpth" boolean
);


ALTER TABLE "public"."parathyroid" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."patientremarks" (
    "id" bigint NOT NULL,
    "pcid" bigint NOT NULL,
    "remarkid" bigint,
    "created_at" timestamp without time zone DEFAULT "now"(),
    "dodate" "date",
    "source" "text",
    "iscollected" boolean,
    "colldate" "date"
);


ALTER TABLE "public"."patientremarks" OWNER TO "postgres";


ALTER TABLE "public"."patientremarks" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."patient_remarks_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE OR REPLACE VIEW "public"."patients_missing_3_sessions" AS
 SELECT "p"."pcid",
    "p"."name",
    "s"."hallname",
    "count"("s"."scheduleid") AS "session_count"
   FROM ("public"."patients" "p"
     LEFT JOIN "public"."schedules" "s" ON (("p"."pcid" = "s"."pcid")))
  GROUP BY "p"."pcid", "p"."name", "s"."hallname"
 HAVING (("count"("s"."scheduleid") <> 3) OR ("count"("s"."scheduleid") = 0));


ALTER TABLE "public"."patients_missing_3_sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."posthdinstructions" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "posthdmedic" "text",
    "pcid" bigint NOT NULL,
    "lastinstrucsync" timestamp with time zone,
    "day" "text",
    "dose" "text",
    "isneedupdate" boolean DEFAULT false
);


ALTER TABLE "public"."posthdinstructions" OWNER TO "postgres";


ALTER TABLE "public"."posthdinstructions" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."posthdinstructions_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."weightdata" (
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "preweight" real,
    "postweight" real,
    "lastsyncdate" timestamp without time zone,
    "pcid" bigint,
    "ufkept" real,
    "tolerance" boolean DEFAULT true,
    "sessionid" bigint NOT NULL,
    "bfr" integer,
    "drywt" real
);


ALTER TABLE "public"."weightdata" OWNER TO "postgres";


ALTER TABLE "public"."weightdata" ALTER COLUMN "sessionid" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."preweightpost_sessionid_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."remarks" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "remake" "text",
    "lastsync" timestamp without time zone,
    "retype" "text"
);


ALTER TABLE "public"."remarks" OWNER TO "postgres";


ALTER TABLE "public"."remarks" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."remarks_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE "public"."schedules" ALTER COLUMN "scheduleid" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."schedules_schedule_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."shifts" (
    "shift" "text",
    "shiftid" bigint NOT NULL
);


ALTER TABLE "public"."shifts" OWNER TO "postgres";


ALTER TABLE "public"."shifts" ALTER COLUMN "shiftid" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."shifts_shift_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE OR REPLACE VIEW "public"."staff_with_counts" AS
 SELECT "s"."medicalstaffid",
    "s"."created_at",
    "s"."name",
    "s"."phone",
    "s"."email",
    "s"."dlastsyncat",
    "s"."staffrole",
    "s"."leavegodate",
    "s"."leavbackdate",
    "s"."isonwork",
    "s"."userid",
    COALESCE("sum"("g"."gcount"), (0)::bigint) AS "ptnscount",
    "string_agg"("concat"("g"."ghall", '-', "g"."gday", '-', "g"."gshift"), ' | '::"text" ORDER BY "g"."ghall", "g"."gday", "g"."gshift") AS "assigned_groups"
   FROM ("public"."staff" "s"
     LEFT JOIN "public"."groupsofpatients" "g" ON (("s"."medicalstaffid" = "g"."staffid")))
  GROUP BY "s"."medicalstaffid", "s"."created_at", "s"."name", "s"."phone", "s"."email", "s"."dlastsyncat", "s"."staffrole", "s"."leavegodate", "s"."leavbackdate", "s"."isonwork", "s"."userid";


ALTER TABLE "public"."staff_with_counts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "usertype" "text"
);


ALTER TABLE "public"."users" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."vascularaccess" (
    "vasid" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "haspcath" boolean,
    "hasavf" boolean,
    "hasavg" boolean,
    "vasclastsyncat" timestamp with time zone,
    "pcid" bigint NOT NULL,
    "vascularhist" "text",
    "vascurrent" "text",
    "appointnextdate" "date"
);


ALTER TABLE "public"."vascularaccess" OWNER TO "postgres";


ALTER TABLE "public"."vascularaccess" ALTER COLUMN "vasid" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."vascularaccess_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."virology" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "vilastsyncat" timestamp with time zone,
    "pcid" bigint NOT NULL,
    "hcv" boolean,
    "hbv" boolean,
    "hiv" boolean,
    "invdate" timestamp with time zone,
    "hcvpcr" "text"
);


ALTER TABLE "public"."virology" OWNER TO "postgres";


ALTER TABLE "public"."virology" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."virology_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE OR REPLACE VIEW "public"."vw_bloodweek_adequacy" AS
 SELECT "bw"."id",
    "bw"."pcid",
    "bw"."month",
    "bw"."year",
    "bw"."dateofresult",
    "bw"."effktv",
    "bw"."effurr",
        CASE
            WHEN ("bw"."effktv" IS NULL) THEN 'missing'::"text"
            WHEN ("bw"."effktv" >= (1.4)::double precision) THEN 'green'::"text"
            WHEN ("bw"."effktv" >= (1.2)::double precision) THEN 'yellow'::"text"
            ELSE 'red'::"text"
        END AS "ktv_status",
        CASE
            WHEN ("bw"."effurr" IS NULL) THEN 'missing'::"text"
            WHEN ("bw"."effurr" >= (65)::double precision) THEN 'green'::"text"
            WHEN ("bw"."effurr" >= (60)::double precision) THEN 'yellow'::"text"
            ELSE 'red'::"text"
        END AS "urr_status",
        CASE
            WHEN (("bw"."effktv" IS NULL) OR ("bw"."effurr" IS NULL)) THEN 'missing'::"text"
            WHEN (("bw"."effktv" >= (1.4)::double precision) AND ("bw"."effurr" >= (65)::double precision)) THEN 'green'::"text"
            WHEN (("bw"."effktv" >= (1.2)::double precision) AND ("bw"."effurr" >= (60)::double precision)) THEN 'yellow'::"text"
            ELSE 'red'::"text"
        END AS "overall_status"
   FROM "public"."bloodweek" "bw";


ALTER TABLE "public"."vw_bloodweek_adequacy" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_patients_bw_status" AS
 SELECT "p"."pcid",
    "p"."name" AS "patient_name",
    "p"."lastbwcollected",
    "p"."nstaffid",
    "bw"."staffenter",
    "s"."name" AS "entered_by_name",
    "bw"."cbchb",
    "bw"."month" AS "bw_month",
    "bw"."year" AS "bw_year",
    "bw"."created_at" AS "bw_created_at"
   FROM (("public"."patients" "p"
     LEFT JOIN LATERAL ( SELECT "b"."id",
            "b"."created_at",
            "b"."cbchb",
            "b"."cbcplt",
            "b"."cbcwbc",
            "b"."bca",
            "b"."bpo4",
            "b"."balk",
            "b"."ue1k",
            "b"."ue1gfr",
            "b"."ureapre",
            "b"."ureapost",
            "b"."dateofresult",
            "b"."effurr",
            "b"."effktv",
            "b"."lablastsyncat",
            "b"."pcid",
            "b"."drreviewed",
            "b"."month",
            "b"."year",
            "b"."staffenter",
            "b"."needcolect",
            "b"."monthnum",
            "b"."ufdone",
            "b"."timetaken",
            "b"."wtpost",
            "b"."isdrrevbw"
           FROM "public"."bloodweek" "b"
          WHERE (("b"."pcid" = "p"."pcid") AND (("b"."year")::numeric = EXTRACT(year FROM CURRENT_DATE)) AND ("b"."month" = "to_char"((CURRENT_DATE)::timestamp with time zone, 'FMMonth'::"text")))
          ORDER BY "b"."created_at" DESC
         LIMIT 1) "bw" ON (true))
     LEFT JOIN "public"."staff" "s" ON ((("s"."medicalstaffid")::"text" = "bw"."staffenter")))
  WHERE ("p"."status" = 'Active'::"text");


ALTER TABLE "public"."vw_patients_bw_status" OWNER TO "postgres";


COMMENT ON VIEW "public"."vw_patients_bw_status" IS 'Patients with their current month bloodweek entry and the staff who entered it.';



CREATE OR REPLACE VIEW "public"."vw_patients_groups" AS
 SELECT "p"."pcid",
    "p"."name",
    "p"."phone",
    "p"."nstaffid",
    "p"."hall_main",
    "p"."day_main",
    "p"."shift_main",
    "p"."status",
    "p"."labgroup",
    "p"."ourunit",
    "p"."inposition",
    "p"."outpostioncause",
    "p"."sex",
    "p"."height",
    "p"."birthdate",
    "p"."lastposthdupdate",
    "p"."nextduebw",
    "p"."dialyzer",
    "p"."vaccess",
    "p"."heparin",
    "p"."lastbwcollected" AS "mlabrecorded",
    "p"."lastlabnote",
    "g"."ismcollected",
    "s"."name" AS "staff_name",
    "s"."staffrole" AS "staff_role",
    "s"."phone" AS "staff_phone"
   FROM (("public"."patients" "p"
     LEFT JOIN "public"."groupsofpatients" "g" ON ((("p"."hall_main" = "g"."ghall") AND ("p"."day_main" = "g"."gday") AND ("p"."shift_main" = "g"."gshift"))))
     LEFT JOIN "public"."staff" "s" ON (("p"."nstaffid" = "s"."medicalstaffid")));


ALTER TABLE "public"."vw_patients_groups" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_patients_pth_summary" AS
 WITH "quarterly" AS (
         SELECT "p"."pcid",
            "p"."name",
            "pr"."pthresult",
            "pr"."pthdate",
            "pr"."pthyear",
                CASE
                    WHEN ((EXTRACT(month FROM "pr"."pthdate") >= (1)::numeric) AND (EXTRACT(month FROM "pr"."pthdate") <= (4)::numeric)) THEN 1
                    WHEN ((EXTRACT(month FROM "pr"."pthdate") >= (5)::numeric) AND (EXTRACT(month FROM "pr"."pthdate") <= (8)::numeric)) THEN 2
                    WHEN ((EXTRACT(month FROM "pr"."pthdate") >= (9)::numeric) AND (EXTRACT(month FROM "pr"."pthdate") <= (12)::numeric)) THEN 3
                    ELSE NULL::integer
                END AS "period_group"
           FROM ("public"."patients" "p"
             LEFT JOIN "public"."parathyroid" "pr" ON (("pr"."pcid" = "p"."pcid")))
        )
 SELECT "q"."pcid",
    "q"."name",
    "q"."pthyear" AS "year",
    "max"(
        CASE
            WHEN ("q"."period_group" = 1) THEN "q"."pthresult"
            ELSE NULL::real
        END) FILTER (WHERE ("q"."period_group" = 1)) AS "pth1",
    "max"(
        CASE
            WHEN ("q"."period_group" = 1) THEN "q"."pthdate"
            ELSE NULL::timestamp with time zone
        END) FILTER (WHERE ("q"."period_group" = 1)) AS "pth1date",
    "max"(
        CASE
            WHEN ("q"."period_group" = 2) THEN "q"."pthresult"
            ELSE NULL::real
        END) FILTER (WHERE ("q"."period_group" = 2)) AS "pth2",
    "max"(
        CASE
            WHEN ("q"."period_group" = 2) THEN "q"."pthdate"
            ELSE NULL::timestamp with time zone
        END) FILTER (WHERE ("q"."period_group" = 2)) AS "pth2date",
    "max"(
        CASE
            WHEN ("q"."period_group" = 3) THEN "q"."pthresult"
            ELSE NULL::real
        END) FILTER (WHERE ("q"."period_group" = 3)) AS "pth3",
    "max"(
        CASE
            WHEN ("q"."period_group" = 3) THEN "q"."pthdate"
            ELSE NULL::timestamp with time zone
        END) FILTER (WHERE ("q"."period_group" = 3)) AS "pth3date"
   FROM "quarterly" "q"
  GROUP BY "q"."pcid", "q"."name", "q"."pthyear"
  ORDER BY "q"."pcid", "q"."pthyear" DESC;


ALTER TABLE "public"."vw_patients_pth_summary" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_patients_pth_yearly_splits" AS
 SELECT "p"."pcid",
    "p"."name",
    "pth1"."pthresult" AS "pth1",
    "pth1"."pthdate" AS "pth1date",
    "pth2"."pthresult" AS "pth2",
    "pth2"."pthdate" AS "pth2date",
    "pth3"."pthresult" AS "pth3",
    "pth3"."pthdate" AS "pth3date"
   FROM ((("public"."patients" "p"
     LEFT JOIN LATERAL ( SELECT "pr"."pthresult",
            "pr"."pthdate"
           FROM "public"."parathyroid" "pr"
          WHERE (("pr"."pcid" = "p"."pcid") AND ((EXTRACT(month FROM "pr"."pthdate") >= (1)::numeric) AND (EXTRACT(month FROM "pr"."pthdate") <= (4)::numeric)))
          ORDER BY "pr"."pthdate" DESC
         LIMIT 1) "pth1" ON (true))
     LEFT JOIN LATERAL ( SELECT "pr"."pthresult",
            "pr"."pthdate"
           FROM "public"."parathyroid" "pr"
          WHERE (("pr"."pcid" = "p"."pcid") AND ((EXTRACT(month FROM "pr"."pthdate") >= (5)::numeric) AND (EXTRACT(month FROM "pr"."pthdate") <= (8)::numeric)))
          ORDER BY "pr"."pthdate" DESC
         LIMIT 1) "pth2" ON (true))
     LEFT JOIN LATERAL ( SELECT "pr"."pthresult",
            "pr"."pthdate"
           FROM "public"."parathyroid" "pr"
          WHERE (("pr"."pcid" = "p"."pcid") AND ((EXTRACT(month FROM "pr"."pthdate") >= (9)::numeric) AND (EXTRACT(month FROM "pr"."pthdate") <= (12)::numeric)))
          ORDER BY "pr"."pthdate" DESC
         LIMIT 1) "pth3" ON (true));


ALTER TABLE "public"."vw_patients_pth_yearly_splits" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_schedule_with_latest_results" AS
 SELECT "s"."scheduleid",
    "s"."pcid",
    "p"."name" AS "patient_name",
    "s"."day",
    "s"."shift",
    "s"."hallname",
    "s"."schedtype",
    "s"."tempdate",
    "s"."replaceday",
    "s"."created_at" AS "schedule_created_at",
    "bw"."cbchb",
    "bw"."cbcplt",
    "bw"."cbcwbc",
    "bw"."bca",
    "bw"."bpo4",
    "bw"."balk",
    "bw"."ue1k",
    "bw"."ue1gfr",
    "bw"."ureapre",
    "bw"."ureapost",
    "bw"."dateofresult" AS "bloodweek_date",
    "bw"."month" AS "bloodweek_month",
    "bw"."year" AS "bloodweek_year",
    "pr"."pthresult",
    "pr"."pthdate" AS "parathyroid_date",
    "pr"."treatmentnote" AS "pth_note",
    "ip"."irontsat",
    "ip"."ironferritin",
    "ip"."invdate" AS "iron_date",
    "ip"."ironnote" AS "iron_note",
    "i"."result" AS "inr_result",
    "i"."created_at" AS "inr_date"
   FROM ((((("public"."schedules" "s"
     LEFT JOIN "public"."patients" "p" ON (("s"."pcid" = "p"."pcid")))
     LEFT JOIN LATERAL ( SELECT "bw_1"."id",
            "bw_1"."created_at",
            "bw_1"."cbchb",
            "bw_1"."cbcplt",
            "bw_1"."cbcwbc",
            "bw_1"."bca",
            "bw_1"."bpo4",
            "bw_1"."balk",
            "bw_1"."ue1k",
            "bw_1"."ue1gfr",
            "bw_1"."ureapre",
            "bw_1"."ureapost",
            "bw_1"."dateofresult",
            "bw_1"."effurr",
            "bw_1"."effktv",
            "bw_1"."lablastsyncat",
            "bw_1"."pcid",
            "bw_1"."drreviewed",
            "bw_1"."month",
            "bw_1"."year",
            "bw_1"."staffenter",
            "bw_1"."needcolect",
            "bw_1"."monthnum"
           FROM "public"."bloodweek" "bw_1"
          WHERE ("bw_1"."pcid" = "s"."pcid")
          ORDER BY "bw_1"."year" DESC, "bw_1"."monthnum" DESC
         LIMIT 1) "bw" ON (true))
     LEFT JOIN LATERAL ( SELECT "pr_1"."created_at",
            "pr_1"."pthresult",
            "pr_1"."pthdate",
            "pr_1"."treatmentnote",
            "pr_1"."pthscan",
            "pr_1"."pthlastsyncat",
            "pr_1"."pcid",
            "pr_1"."pthyear"
           FROM "public"."parathyroid" "pr_1"
          WHERE ("pr_1"."pcid" = "s"."pcid")
          ORDER BY "pr_1"."pthdate" DESC
         LIMIT 1) "pr" ON (true))
     LEFT JOIN LATERAL ( SELECT "ip_1"."created_at",
            "ip_1"."irontsat",
            "ip_1"."ironferritin",
            "ip_1"."tttmedical",
            "ip_1"."ironnote",
            "ip_1"."pthlastsyncat",
            "ip_1"."pcid",
            "ip_1"."invdate",
            "ip_1"."ironyear"
           FROM "public"."ironprofile" "ip_1"
          WHERE ("ip_1"."pcid" = "s"."pcid")
          ORDER BY "ip_1"."invdate" DESC
         LIMIT 1) "ip" ON (true))
     LEFT JOIN LATERAL ( SELECT "i_1"."id",
            "i_1"."created_at",
            "i_1"."pcid",
            "i_1"."result",
            "i_1"."routinday"
           FROM "public"."inr" "i_1"
          WHERE ("i_1"."pcid" = "s"."pcid")
          ORDER BY "i_1"."created_at" DESC
         LIMIT 1) "i" ON (true));


ALTER TABLE "public"."vw_schedule_with_latest_results" OWNER TO "postgres";


ALTER TABLE ONLY "public"."doppplerslinks" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."doppplerslinks_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."hall_schedule_config" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."hall_schedule_config_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."bloodweekgroups"
    ADD CONSTRAINT "Bloodweekgroups_pkey" PRIMARY KEY ("groupname");



ALTER TABLE ONLY "public"."antibiotics"
    ADD CONSTRAINT "antibiotics_pkey" PRIMARY KEY ("abid");



ALTER TABLE ONLY "public"."anticoagulant"
    ADD CONSTRAINT "anticoagulant_pkey" PRIMARY KEY ("antiid");



ALTER TABLE ONLY "public"."bloodweek"
    ADD CONSTRAINT "bloodweek_id_key" UNIQUE ("id");



ALTER TABLE ONLY "public"."bloodweek"
    ADD CONSTRAINT "bloodweek_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."bloodweekgroups"
    ADD CONSTRAINT "bloodweekgroups_doday_key" UNIQUE ("doday");



ALTER TABLE ONLY "public"."dialyzer"
    ADD CONSTRAINT "dialyzer_dzid_key" UNIQUE ("dzid");



ALTER TABLE ONLY "public"."dialyzer"
    ADD CONSTRAINT "dialyzer_pkey" PRIMARY KEY ("dzid");



ALTER TABLE ONLY "public"."doppplerslinks"
    ADD CONSTRAINT "doppplerslinks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dryweight"
    ADD CONSTRAINT "dryweight_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ecg_links"
    ADD CONSTRAINT "ecg_links_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."groupsofpatients"
    ADD CONSTRAINT "groupsofpatients_pkey" PRIMARY KEY ("ghall", "gshift", "gday");



ALTER TABLE ONLY "public"."hall_schedule_config"
    ADD CONSTRAINT "hall_schedule_config_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."halls"
    ADD CONSTRAINT "halls_pkey" PRIMARY KEY ("hallname");



ALTER TABLE ONLY "public"."history"
    ADD CONSTRAINT "history_id_key" UNIQUE ("id");



ALTER TABLE ONLY "public"."history"
    ADD CONSTRAINT "history_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inr"
    ADD CONSTRAINT "inr_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ironprofile"
    ADD CONSTRAINT "ironprofile_pkey" PRIMARY KEY ("pcid", "invdate");



ALTER TABLE ONLY "public"."labdays"
    ADD CONSTRAINT "labdays_pkey" PRIMARY KEY ("labday");



ALTER TABLE ONLY "public"."labnormalrange"
    ADD CONSTRAINT "labnormalrange_pkey" PRIMARY KEY ("labcode");



ALTER TABLE ONLY "public"."logs"
    ADD CONSTRAINT "logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."medicationstb"
    ADD CONSTRAINT "medicationstb_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."parathyroid"
    ADD CONSTRAINT "parathyroid_pkey" PRIMARY KEY ("pthdate", "pcid");



ALTER TABLE ONLY "public"."patientremarks"
    ADD CONSTRAINT "patient_remarks_id_key" UNIQUE ("id");



ALTER TABLE ONLY "public"."patientremarks"
    ADD CONSTRAINT "patient_remarks_p_cid_remark_id_key" UNIQUE ("pcid", "remarkid");



ALTER TABLE ONLY "public"."patientremarks"
    ADD CONSTRAINT "patient_remarks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."patients"
    ADD CONSTRAINT "patients_p_cid_key" UNIQUE ("pcid");



ALTER TABLE ONLY "public"."patients"
    ADD CONSTRAINT "patients_p_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."patients"
    ADD CONSTRAINT "patients_pcid_unique" UNIQUE ("pcid");



ALTER TABLE ONLY "public"."patients"
    ADD CONSTRAINT "patients_pkey" PRIMARY KEY ("pcid");



ALTER TABLE ONLY "public"."posthdinstructions"
    ADD CONSTRAINT "posthdinstructions_id_key" UNIQUE ("id");



ALTER TABLE ONLY "public"."posthdinstructions"
    ADD CONSTRAINT "posthdinstructions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."weightdata"
    ADD CONSTRAINT "preweightpost_pkey" PRIMARY KEY ("sessionid");



ALTER TABLE ONLY "public"."remarks"
    ADD CONSTRAINT "remarks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."schedules"
    ADD CONSTRAINT "schedules_pkey" PRIMARY KEY ("scheduleid");



ALTER TABLE ONLY "public"."schedules"
    ADD CONSTRAINT "schedules_schedule_id_key" UNIQUE ("scheduleid");



ALTER TABLE ONLY "public"."schedules"
    ADD CONSTRAINT "schedules_unique_schedule" UNIQUE ("pcid", "day", "hallname", "shift");



ALTER TABLE ONLY "public"."shifts"
    ADD CONSTRAINT "shifts_pkey" PRIMARY KEY ("shiftid");



ALTER TABLE ONLY "public"."staff"
    ADD CONSTRAINT "staff_medicalstaffid_key" UNIQUE ("medicalstaffid");



ALTER TABLE ONLY "public"."staff"
    ADD CONSTRAINT "staff_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."staff"
    ADD CONSTRAINT "staff_pkey" PRIMARY KEY ("medicalstaffid");



ALTER TABLE ONLY "public"."hall_schedule_config"
    ADD CONSTRAINT "unique_hall_day_shift" UNIQUE ("hallname", "day_name", "shift_name", "effective_from");



ALTER TABLE ONLY "public"."bloodweek"
    ADD CONSTRAINT "unique_patient_month" UNIQUE ("pcid", "month", "year");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."vascularaccess"
    ADD CONSTRAINT "vascularaccess_id_key" UNIQUE ("vasid");



ALTER TABLE ONLY "public"."vascularaccess"
    ADD CONSTRAINT "vascularaccess_pkey" PRIMARY KEY ("vasid");



ALTER TABLE ONLY "public"."virology"
    ADD CONSTRAINT "virology_id_key" UNIQUE ("id");



ALTER TABLE ONLY "public"."virology"
    ADD CONSTRAINT "virology_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."weightdata"
    ADD CONSTRAINT "weightdata_sessionid_key" UNIQUE ("sessionid");



CREATE INDEX "idx_doppplerslinks_pcid" ON "public"."doppplerslinks" USING "btree" ("pcid");



CREATE INDEX "idx_hall_schedule_active" ON "public"."hall_schedule_config" USING "btree" ("hallname", "is_active") WHERE ("is_active" = true);



CREATE INDEX "idx_patients_schedule" ON "public"."patients" USING "btree" ("hall_main", "day_main", "shift_main");



CREATE INDEX "schedules_fast_lookup_idx" ON "public"."schedules" USING "btree" ("hallname", "day", "shift");



CREATE OR REPLACE TRIGGER "schedules_delete_trigger" AFTER DELETE ON "public"."schedules" FOR EACH ROW EXECUTE FUNCTION "public"."update_group_count_trigger"();



CREATE OR REPLACE TRIGGER "schedules_insert_trigger" AFTER INSERT ON "public"."schedules" FOR EACH ROW EXECUTE FUNCTION "public"."update_group_count_trigger"();



CREATE OR REPLACE TRIGGER "schedules_update_trigger" AFTER UPDATE OF "hallname", "shift", "day" ON "public"."schedules" FOR EACH ROW EXECUTE FUNCTION "public"."update_group_count_trigger"();



CREATE OR REPLACE TRIGGER "tg_bw_zero_to_null" BEFORE INSERT OR UPDATE ON "public"."bloodweek" FOR EACH ROW EXECUTE FUNCTION "public"."bw_zero_to_null"();



CREATE OR REPLACE TRIGGER "tg_iron_zero_to_null" BEFORE INSERT OR UPDATE ON "public"."ironprofile" FOR EACH ROW EXECUTE FUNCTION "public"."iron_zero_to_null"();



CREATE OR REPLACE TRIGGER "tg_par_zero_to_null" BEFORE INSERT OR UPDATE ON "public"."parathyroid" FOR EACH ROW EXECUTE FUNCTION "public"."par_zero_to_null"();



CREATE OR REPLACE TRIGGER "trg_bloodweek_efficiency" BEFORE INSERT OR UPDATE OF "ureapre", "ureapost", "ufdone", "wtpost", "timetaken" ON "public"."bloodweek" FOR EACH ROW EXECUTE FUNCTION "public"."bloodweek_efficiency_trigger"();



CREATE OR REPLACE TRIGGER "trg_bw_lastbwcollected" AFTER INSERT OR UPDATE ON "public"."bloodweek" FOR EACH ROW EXECUTE FUNCTION "public"."update_patient_lastbwcollected"();



CREATE OR REPLACE TRIGGER "trg_bw_note" AFTER INSERT OR UPDATE ON "public"."bloodweek" FOR EACH ROW EXECUTE FUNCTION "public"."update_patient_lastlabnote"();



CREATE OR REPLACE TRIGGER "trg_bw_update_isdrreviewed" AFTER INSERT OR UPDATE OF "isdrrevbw", "month" ON "public"."bloodweek" FOR EACH ROW EXECUTE FUNCTION "public"."update_patient_isdrreviewed"();



CREATE OR REPLACE TRIGGER "trg_groups_patients_staffid" AFTER INSERT OR UPDATE OF "staffid" ON "public"."groupsofpatients" FOR EACH ROW EXECUTE FUNCTION "public"."update_groupsofpatients_staffid"();



CREATE OR REPLACE TRIGGER "trg_hall_schedule_updated" BEFORE UPDATE ON "public"."hall_schedule_config" FOR EACH ROW EXECUTE FUNCTION "public"."update_hall_schedule_timestamp"();



CREATE OR REPLACE TRIGGER "trg_iron_note" AFTER INSERT OR UPDATE ON "public"."ironprofile" FOR EACH ROW EXECUTE FUNCTION "public"."update_patient_lastlabnote"();



CREATE OR REPLACE TRIGGER "trg_par_note" AFTER INSERT OR UPDATE ON "public"."parathyroid" FOR EACH ROW EXECUTE FUNCTION "public"."update_patient_lastlabnote"();



ALTER TABLE ONLY "public"."antibiotics"
    ADD CONSTRAINT "antibiotics_pcid_fkey" FOREIGN KEY ("pcid") REFERENCES "public"."patients"("pcid") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."anticoagulant"
    ADD CONSTRAINT "anticoagulant_pcid_fkey" FOREIGN KEY ("pcid") REFERENCES "public"."patients"("pcid") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bloodweek"
    ADD CONSTRAINT "bloodweek_pcid_fkey" FOREIGN KEY ("pcid") REFERENCES "public"."patients"("pcid") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dialyzer"
    ADD CONSTRAINT "dialyzer_pcid_fkey" FOREIGN KEY ("pcid") REFERENCES "public"."patients"("pcid") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dryweight"
    ADD CONSTRAINT "dryweight_pcid_fkey" FOREIGN KEY ("pcid") REFERENCES "public"."patients"("pcid") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ecg_links"
    ADD CONSTRAINT "ecg_links_pcid_fkey" FOREIGN KEY ("pcid") REFERENCES "public"."patients"("pcid");



ALTER TABLE ONLY "public"."patients"
    ADD CONSTRAINT "fk_patients_group" FOREIGN KEY ("hall_main", "shift_main", "day_main") REFERENCES "public"."groupsofpatients"("ghall", "gshift", "gday") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."history"
    ADD CONSTRAINT "history_pcid_fkey" FOREIGN KEY ("pcid") REFERENCES "public"."patients"("pcid") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."inr"
    ADD CONSTRAINT "inr_pcid_fkey" FOREIGN KEY ("pcid") REFERENCES "public"."patients"("pcid") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."medicationstb"
    ADD CONSTRAINT "medicationstb_pcid_fkey" FOREIGN KEY ("pcid") REFERENCES "public"."patients"("pcid") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."parathyroid"
    ADD CONSTRAINT "parathyroid_pcid_fkey" FOREIGN KEY ("pcid") REFERENCES "public"."patients"("pcid") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."posthdinstructions"
    ADD CONSTRAINT "posthdinstructions_pcid_fkey" FOREIGN KEY ("pcid") REFERENCES "public"."patients"("pcid") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."schedules"
    ADD CONSTRAINT "schedules_pcid_fkey" FOREIGN KEY ("pcid") REFERENCES "public"."patients"("pcid") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."staff"
    ADD CONSTRAINT "staff_userid_fkey" FOREIGN KEY ("userid") REFERENCES "auth"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."vascularaccess"
    ADD CONSTRAINT "vascularaccess_pcid_fkey" FOREIGN KEY ("pcid") REFERENCES "public"."patients"("pcid") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."virology"
    ADD CONSTRAINT "virology_pcid_fkey" FOREIGN KEY ("pcid") REFERENCES "public"."patients"("pcid") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."weightdata"
    ADD CONSTRAINT "weightdata_pcid_fkey" FOREIGN KEY ("pcid") REFERENCES "public"."patients"("pcid") ON UPDATE CASCADE ON DELETE CASCADE;



CREATE POLICY "Enable read access for all users" ON "public"."ecg_links" FOR SELECT USING (true);



ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";




















































































































































































GRANT ALL ON FUNCTION "public"."bloodweek_efficiency_trigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."bloodweek_efficiency_trigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."bloodweek_efficiency_trigger"() TO "service_role";



GRANT ALL ON FUNCTION "public"."bloodweek_effktv_trigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."bloodweek_effktv_trigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."bloodweek_effktv_trigger"() TO "service_role";



GRANT ALL ON FUNCTION "public"."bw_zero_to_null"() TO "anon";
GRANT ALL ON FUNCTION "public"."bw_zero_to_null"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."bw_zero_to_null"() TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_effktv"("p_ureapre" real, "p_ureapost" real, "p_ufdone" double precision, "p_wtpost" double precision, "p_timetaken" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_effktv"("p_ureapre" real, "p_ureapost" real, "p_ufdone" double precision, "p_wtpost" double precision, "p_timetaken" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_effktv"("p_ureapre" real, "p_ureapost" real, "p_ufdone" double precision, "p_wtpost" double precision, "p_timetaken" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_effurr"("p_ureapre" real, "p_ureapost" real) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_effurr"("p_ureapre" real, "p_ureapost" real) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_effurr"("p_ureapre" real, "p_ureapost" real) TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_bloodweek_for_month"("in_year" integer, "in_month" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."generate_bloodweek_for_month"("in_year" integer, "in_month" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_bloodweek_for_month"("in_year" integer, "in_month" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_iron_for_num"("in_year" integer, "in_num" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."generate_iron_for_num"("in_year" integer, "in_num" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_iron_for_num"("in_year" integer, "in_num" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_pth_for_num"("in_year" integer, "in_num" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."generate_pth_for_num"("in_year" integer, "in_num" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_pth_for_num"("in_year" integer, "in_num" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_patient_bloodweek_summary"("in_target_year" integer, "in_target_month" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_patient_bloodweek_summary"("in_target_year" integer, "in_target_month" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_patient_bloodweek_summary"("in_target_year" integer, "in_target_month" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."iron_zero_to_null"() TO "anon";
GRANT ALL ON FUNCTION "public"."iron_zero_to_null"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."iron_zero_to_null"() TO "service_role";



GRANT ALL ON FUNCTION "public"."make_lab_note"("pcid" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."make_lab_note"("pcid" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."make_lab_note"("pcid" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."par_zero_to_null"() TO "anon";
GRANT ALL ON FUNCTION "public"."par_zero_to_null"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."par_zero_to_null"() TO "service_role";



GRANT ALL ON FUNCTION "public"."process_single_bloodweek_json"() TO "anon";
GRANT ALL ON FUNCTION "public"."process_single_bloodweek_json"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."process_single_bloodweek_json"() TO "service_role";



GRANT ALL ON FUNCTION "public"."process_single_ironprofile_json"() TO "anon";
GRANT ALL ON FUNCTION "public"."process_single_ironprofile_json"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."process_single_ironprofile_json"() TO "service_role";



GRANT ALL ON FUNCTION "public"."process_single_pthjson"() TO "anon";
GRANT ALL ON FUNCTION "public"."process_single_pthjson"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."process_single_pthjson"() TO "service_role";



GRANT ALL ON FUNCTION "public"."refresh_media_status"() TO "anon";
GRANT ALL ON FUNCTION "public"."refresh_media_status"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."refresh_media_status"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_all_patients_staffid"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_all_patients_staffid"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_all_patients_staffid"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_patients_main_schedule"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_patients_main_schedule"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_patients_main_schedule"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_bloodweek_from_sheet"("in_pcid" bigint, "in_month" "text", "in_year" integer, "in_cbchb" real, "in_cbcplt" real, "in_cbcwbc" real, "in_bca" real, "in_bpo4" real, "in_ue1k" real, "in_ureapre" real, "in_ureapost" real) TO "anon";
GRANT ALL ON FUNCTION "public"."update_bloodweek_from_sheet"("in_pcid" bigint, "in_month" "text", "in_year" integer, "in_cbchb" real, "in_cbcplt" real, "in_cbcwbc" real, "in_bca" real, "in_bpo4" real, "in_ue1k" real, "in_ureapre" real, "in_ureapost" real) TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_bloodweek_from_sheet"("in_pcid" bigint, "in_month" "text", "in_year" integer, "in_cbchb" real, "in_cbcplt" real, "in_cbcwbc" real, "in_bca" real, "in_bpo4" real, "in_ue1k" real, "in_ureapre" real, "in_ureapost" real) TO "service_role";



GRANT ALL ON FUNCTION "public"."update_bloodweek_from_sheet_bulk"("in_data" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."update_bloodweek_from_sheet_bulk"("in_data" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_bloodweek_from_sheet_bulk"("in_data" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_group_count_trigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_group_count_trigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_group_count_trigger"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_groupsofpatients_staffid"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_groupsofpatients_staffid"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_groupsofpatients_staffid"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_hall_schedule_timestamp"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_hall_schedule_timestamp"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_hall_schedule_timestamp"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_patient_isdrreviewed"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_patient_isdrreviewed"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_patient_isdrreviewed"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_patient_lastbwcollected"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_patient_lastbwcollected"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_patient_lastbwcollected"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_patient_lastlabnote"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_patient_lastlabnote"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_patient_lastlabnote"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_patient_schedule"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_patient_schedule"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_patient_schedule"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_patients_staffid"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_patients_staffid"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_patients_staffid"() TO "service_role";



























GRANT ALL ON TABLE "public"."antibiotics" TO "anon";
GRANT ALL ON TABLE "public"."antibiotics" TO "authenticated";
GRANT ALL ON TABLE "public"."antibiotics" TO "service_role";



GRANT ALL ON SEQUENCE "public"."antibiotics_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."antibiotics_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."antibiotics_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."anticoagulant" TO "anon";
GRANT ALL ON TABLE "public"."anticoagulant" TO "authenticated";
GRANT ALL ON TABLE "public"."anticoagulant" TO "service_role";



GRANT ALL ON SEQUENCE "public"."anticoagulant_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."anticoagulant_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."anticoagulant_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."bloodweek" TO "anon";
GRANT ALL ON TABLE "public"."bloodweek" TO "authenticated";
GRANT ALL ON TABLE "public"."bloodweek" TO "service_role";



GRANT ALL ON SEQUENCE "public"."bloodweek_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."bloodweek_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."bloodweek_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."bloodweekgroups" TO "anon";
GRANT ALL ON TABLE "public"."bloodweekgroups" TO "authenticated";
GRANT ALL ON TABLE "public"."bloodweekgroups" TO "service_role";



GRANT ALL ON TABLE "public"."dialyzer" TO "anon";
GRANT ALL ON TABLE "public"."dialyzer" TO "authenticated";
GRANT ALL ON TABLE "public"."dialyzer" TO "service_role";



GRANT ALL ON SEQUENCE "public"."dialyzer_dzid_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."dialyzer_dzid_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."dialyzer_dzid_seq" TO "service_role";



GRANT ALL ON TABLE "public"."doppplerslinks" TO "anon";
GRANT ALL ON TABLE "public"."doppplerslinks" TO "authenticated";
GRANT ALL ON TABLE "public"."doppplerslinks" TO "service_role";



GRANT ALL ON SEQUENCE "public"."doppplerslinks_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."doppplerslinks_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."doppplerslinks_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."dryweight" TO "anon";
GRANT ALL ON TABLE "public"."dryweight" TO "authenticated";
GRANT ALL ON TABLE "public"."dryweight" TO "service_role";



GRANT ALL ON SEQUENCE "public"."dryweight_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."dryweight_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."dryweight_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."ecg_links" TO "anon";
GRANT ALL ON TABLE "public"."ecg_links" TO "authenticated";
GRANT ALL ON TABLE "public"."ecg_links" TO "service_role";



GRANT ALL ON SEQUENCE "public"."ecg_links_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."ecg_links_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."ecg_links_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."halls" TO "anon";
GRANT ALL ON TABLE "public"."halls" TO "authenticated";
GRANT ALL ON TABLE "public"."halls" TO "service_role";



GRANT ALL ON TABLE "public"."schedules" TO "anon";
GRANT ALL ON TABLE "public"."schedules" TO "authenticated";
GRANT ALL ON TABLE "public"."schedules" TO "service_role";



GRANT ALL ON TABLE "public"."free_beds" TO "anon";
GRANT ALL ON TABLE "public"."free_beds" TO "authenticated";
GRANT ALL ON TABLE "public"."free_beds" TO "service_role";



GRANT ALL ON TABLE "public"."free_beds_c" TO "anon";
GRANT ALL ON TABLE "public"."free_beds_c" TO "authenticated";
GRANT ALL ON TABLE "public"."free_beds_c" TO "service_role";



GRANT ALL ON TABLE "public"."free_beds_per_day_shift" TO "anon";
GRANT ALL ON TABLE "public"."free_beds_per_day_shift" TO "authenticated";
GRANT ALL ON TABLE "public"."free_beds_per_day_shift" TO "service_role";



GRANT ALL ON TABLE "public"."groupsofpatients" TO "anon";
GRANT ALL ON TABLE "public"."groupsofpatients" TO "authenticated";
GRANT ALL ON TABLE "public"."groupsofpatients" TO "service_role";



GRANT ALL ON TABLE "public"."hall_schedule_config" TO "anon";
GRANT ALL ON TABLE "public"."hall_schedule_config" TO "authenticated";
GRANT ALL ON TABLE "public"."hall_schedule_config" TO "service_role";



GRANT ALL ON SEQUENCE "public"."hall_schedule_config_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."hall_schedule_config_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."hall_schedule_config_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."history" TO "anon";
GRANT ALL ON TABLE "public"."history" TO "authenticated";
GRANT ALL ON TABLE "public"."history" TO "service_role";



GRANT ALL ON SEQUENCE "public"."history_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."history_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."history_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."inr" TO "anon";
GRANT ALL ON TABLE "public"."inr" TO "authenticated";
GRANT ALL ON TABLE "public"."inr" TO "service_role";



GRANT ALL ON SEQUENCE "public"."inr_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."inr_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."inr_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."ironprofile" TO "anon";
GRANT ALL ON TABLE "public"."ironprofile" TO "authenticated";
GRANT ALL ON TABLE "public"."ironprofile" TO "service_role";



GRANT ALL ON TABLE "public"."labdays" TO "anon";
GRANT ALL ON TABLE "public"."labdays" TO "authenticated";
GRANT ALL ON TABLE "public"."labdays" TO "service_role";



GRANT ALL ON TABLE "public"."labnormalrange" TO "anon";
GRANT ALL ON TABLE "public"."labnormalrange" TO "authenticated";
GRANT ALL ON TABLE "public"."labnormalrange" TO "service_role";



GRANT ALL ON TABLE "public"."logs" TO "anon";
GRANT ALL ON TABLE "public"."logs" TO "authenticated";
GRANT ALL ON TABLE "public"."logs" TO "service_role";



GRANT ALL ON SEQUENCE "public"."logs_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."logs_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."logs_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."medicationstb" TO "anon";
GRANT ALL ON TABLE "public"."medicationstb" TO "authenticated";
GRANT ALL ON TABLE "public"."medicationstb" TO "service_role";



GRANT ALL ON SEQUENCE "public"."medicationstb_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."medicationstb_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."medicationstb_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."patients" TO "anon";
GRANT ALL ON TABLE "public"."patients" TO "authenticated";
GRANT ALL ON TABLE "public"."patients" TO "service_role";



GRANT ALL ON TABLE "public"."staff" TO "anon";
GRANT ALL ON TABLE "public"."staff" TO "authenticated";
GRANT ALL ON TABLE "public"."staff" TO "service_role";



GRANT ALL ON TABLE "public"."nurse_patient_summary" TO "anon";
GRANT ALL ON TABLE "public"."nurse_patient_summary" TO "authenticated";
GRANT ALL ON TABLE "public"."nurse_patient_summary" TO "service_role";



GRANT ALL ON TABLE "public"."parathyroid" TO "anon";
GRANT ALL ON TABLE "public"."parathyroid" TO "authenticated";
GRANT ALL ON TABLE "public"."parathyroid" TO "service_role";



GRANT ALL ON TABLE "public"."patientremarks" TO "anon";
GRANT ALL ON TABLE "public"."patientremarks" TO "authenticated";
GRANT ALL ON TABLE "public"."patientremarks" TO "service_role";



GRANT ALL ON SEQUENCE "public"."patient_remarks_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."patient_remarks_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."patient_remarks_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."patients_missing_3_sessions" TO "anon";
GRANT ALL ON TABLE "public"."patients_missing_3_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."patients_missing_3_sessions" TO "service_role";



GRANT ALL ON TABLE "public"."posthdinstructions" TO "anon";
GRANT ALL ON TABLE "public"."posthdinstructions" TO "authenticated";
GRANT ALL ON TABLE "public"."posthdinstructions" TO "service_role";



GRANT ALL ON SEQUENCE "public"."posthdinstructions_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."posthdinstructions_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."posthdinstructions_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."weightdata" TO "anon";
GRANT ALL ON TABLE "public"."weightdata" TO "authenticated";
GRANT ALL ON TABLE "public"."weightdata" TO "service_role";



GRANT ALL ON SEQUENCE "public"."preweightpost_sessionid_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."preweightpost_sessionid_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."preweightpost_sessionid_seq" TO "service_role";



GRANT ALL ON TABLE "public"."remarks" TO "anon";
GRANT ALL ON TABLE "public"."remarks" TO "authenticated";
GRANT ALL ON TABLE "public"."remarks" TO "service_role";



GRANT ALL ON SEQUENCE "public"."remarks_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."remarks_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."remarks_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."schedules_schedule_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."schedules_schedule_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."schedules_schedule_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."shifts" TO "anon";
GRANT ALL ON TABLE "public"."shifts" TO "authenticated";
GRANT ALL ON TABLE "public"."shifts" TO "service_role";



GRANT ALL ON SEQUENCE "public"."shifts_shift_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."shifts_shift_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."shifts_shift_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."staff_with_counts" TO "anon";
GRANT ALL ON TABLE "public"."staff_with_counts" TO "authenticated";
GRANT ALL ON TABLE "public"."staff_with_counts" TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "anon";
GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";



GRANT ALL ON TABLE "public"."vascularaccess" TO "anon";
GRANT ALL ON TABLE "public"."vascularaccess" TO "authenticated";
GRANT ALL ON TABLE "public"."vascularaccess" TO "service_role";



GRANT ALL ON SEQUENCE "public"."vascularaccess_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."vascularaccess_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."vascularaccess_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."virology" TO "anon";
GRANT ALL ON TABLE "public"."virology" TO "authenticated";
GRANT ALL ON TABLE "public"."virology" TO "service_role";



GRANT ALL ON SEQUENCE "public"."virology_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."virology_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."virology_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."vw_bloodweek_adequacy" TO "anon";
GRANT ALL ON TABLE "public"."vw_bloodweek_adequacy" TO "authenticated";
GRANT ALL ON TABLE "public"."vw_bloodweek_adequacy" TO "service_role";



GRANT ALL ON TABLE "public"."vw_patients_bw_status" TO "anon";
GRANT ALL ON TABLE "public"."vw_patients_bw_status" TO "authenticated";
GRANT ALL ON TABLE "public"."vw_patients_bw_status" TO "service_role";



GRANT ALL ON TABLE "public"."vw_patients_groups" TO "anon";
GRANT ALL ON TABLE "public"."vw_patients_groups" TO "authenticated";
GRANT ALL ON TABLE "public"."vw_patients_groups" TO "service_role";



GRANT ALL ON TABLE "public"."vw_patients_pth_summary" TO "anon";
GRANT ALL ON TABLE "public"."vw_patients_pth_summary" TO "authenticated";
GRANT ALL ON TABLE "public"."vw_patients_pth_summary" TO "service_role";



GRANT ALL ON TABLE "public"."vw_patients_pth_yearly_splits" TO "anon";
GRANT ALL ON TABLE "public"."vw_patients_pth_yearly_splits" TO "authenticated";
GRANT ALL ON TABLE "public"."vw_patients_pth_yearly_splits" TO "service_role";



GRANT ALL ON TABLE "public"."vw_schedule_with_latest_results" TO "anon";
GRANT ALL ON TABLE "public"."vw_schedule_with_latest_results" TO "authenticated";
GRANT ALL ON TABLE "public"."vw_schedule_with_latest_results" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "service_role";































