-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE public.antibiotics (
  abid bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  abname text,
  doseregim text,
  dosetotal integer,
  startdate date,
  pcid bigint,
  enddate date,
  dosetoday integer,
  iscompleted boolean,
  lastgiven date,
  CONSTRAINT antibiotics_pkey PRIMARY KEY (abid),
  CONSTRAINT antibiotics_pcid_fkey FOREIGN KEY (pcid) REFERENCES public.patients(pcid)
);
CREATE TABLE public.anticoagulant (
  antiid bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  antiname text,
  antidose text,
  dateoforder date,
  pcid bigint,
  CONSTRAINT anticoagulant_pkey PRIMARY KEY (antiid),
  CONSTRAINT anticoagulant_pcid_fkey FOREIGN KEY (pcid) REFERENCES public.patients(pcid)
);
CREATE TABLE public.bloodweek (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL UNIQUE,
  created_at timestamp with time zone DEFAULT now(),
  cbchb real,
  cbcplt real,
  cbcwbc real,
  bca real,
  bpo4 real,
  balk real,
  ue1k real,
  ue1gfr real,
  ureapre real CHECK (ureapre IS NULL OR ureapre > 0::double precision),
  ureapost real CHECK (ureapost IS NULL OR ureapost > 0::double precision),
  dateofresult timestamp with time zone,
  effurr real,
  effktv real,
  lablastsyncat timestamp with time zone,
  pcid bigint NOT NULL,
  drreviewed text,
  month text NOT NULL,
  year integer NOT NULL,
  staffenter text,
  needcolect boolean,
  monthnum smallint DEFAULT 
CASE month
    WHEN 'January'::text THEN 1
    WHEN 'February'::text THEN 2
    WHEN 'March'::text THEN 3
    WHEN 'April'::text THEN 4
    WHEN 'May'::text THEN 5
    WHEN 'June'::text THEN 6
    WHEN 'July'::text THEN 7
    WHEN 'August'::text THEN 8
    WHEN 'September'::text THEN 9
    WHEN 'October'::text THEN 10
    WHEN 'November'::text THEN 11
    WHEN 'December'::text THEN 12
    ELSE NULL::integer
END,
  ufdone double precision CHECK (ufdone IS NULL OR ufdone >= 0::double precision),
  timetaken double precision CHECK (timetaken IS NULL OR timetaken >= 1.5::double precision AND timetaken <= 6::double precision),
  wtpost double precision CHECK (wtpost IS NULL OR wtpost > 0::double precision),
  isdrrevbw boolean,
  CONSTRAINT bloodweek_pkey PRIMARY KEY (id),
  CONSTRAINT bloodweek_pcid_fkey FOREIGN KEY (pcid) REFERENCES public.patients(pcid)
);
CREATE TABLE public.bloodweekgroups (
  groupname text NOT NULL,
  doday text UNIQUE,
  nextmonth integer,
  datetocollect date,
  CONSTRAINT bloodweekgroups_pkey PRIMARY KEY (groupname)
);
CREATE TABLE public.dialyzer (
  dzid bigint GENERATED ALWAYS AS IDENTITY NOT NULL UNIQUE,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  pcid bigint,
  dztype text,
  dzcomment text,
  datesync date,
  CONSTRAINT dialyzer_pkey PRIMARY KEY (dzid),
  CONSTRAINT dialyzer_pcid_fkey FOREIGN KEY (pcid) REFERENCES public.patients(pcid)
);
CREATE TABLE public.doppplerslinks (
  id bigint NOT NULL DEFAULT nextval('doppplerslinks_id_seq'::regclass),
  pcid text NOT NULL,
  piclink text,
  thumbnail_url text,
  medium_url text,
  large_url text,
  full_url text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT doppplerslinks_pkey PRIMARY KEY (id)
);
CREATE TABLE public.dryweight (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  createdat timestamp with time zone NOT NULL DEFAULT now(),
  dryweight real,
  pcid bigint,
  lastsyncdate timestamp without time zone,
  orderdate date,
  CONSTRAINT dryweight_pkey PRIMARY KEY (id),
  CONSTRAINT dryweight_pcid_fkey FOREIGN KEY (pcid) REFERENCES public.patients(pcid)
);
CREATE TABLE public.ecg_links (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  pcid bigint NOT NULL,
  piclink text,
  thumbnail_url text,
  medium_url text,
  large_url text,
  full_url text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  clinicalnote text,
  CONSTRAINT ecg_links_pkey PRIMARY KEY (id),
  CONSTRAINT ecg_links_pcid_fkey FOREIGN KEY (pcid) REFERENCES public.patients(pcid)
);
CREATE TABLE public.groupsofpatients (
  ghall text NOT NULL,
  gshift text NOT NULL,
  gday text NOT NULL,
  gcount integer,
  staffid integer,
  ismcollected boolean NOT NULL DEFAULT false,
  ismain boolean,
  CONSTRAINT groupsofpatients_pkey PRIMARY KEY (ghall, gshift, gday)
);
CREATE TABLE public.halls (
  hallname text NOT NULL,
  totalbeds integer NOT NULL,
  CONSTRAINT halls_pkey PRIMARY KEY (hallname)
);
CREATE TABLE public.history (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL UNIQUE,
  created_at timestamp with time zone,
  isdm boolean,
  ishtn boolean,
  isihd boolean,
  pdiagnosis text,
  pallergy text,
  diaglastsyncat timestamp with time zone,
  pcid bigint NOT NULL,
  phistory text,
  CONSTRAINT history_pkey PRIMARY KEY (id),
  CONSTRAINT history_pcid_fkey FOREIGN KEY (pcid) REFERENCES public.patients(pcid)
);
CREATE TABLE public.inr (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  pcid bigint,
  result real,
  routinday text,
  CONSTRAINT inr_pkey PRIMARY KEY (id),
  CONSTRAINT inr_pcid_fkey FOREIGN KEY (pcid) REFERENCES public.patients(pcid)
);
CREATE TABLE public.ironprofile (
  created_at timestamp with time zone DEFAULT now(),
  irontsat real,
  ironferritin real,
  tttmedical text,
  ironnote text,
  pthlastsyncat timestamp with time zone,
  pcid bigint NOT NULL,
  invdate date NOT NULL,
  ironyear integer NOT NULL,
  isdrreviron boolean,
  CONSTRAINT ironprofile_pkey PRIMARY KEY (pcid, invdate)
);
CREATE TABLE public.labdays (
  labday text NOT NULL,
  CONSTRAINT labdays_pkey PRIMARY KEY (labday)
);
CREATE TABLE public.labnormalrange (
  labcode text NOT NULL,
  minvalue real,
  maxvalue real,
  CONSTRAINT labnormalrange_pkey PRIMARY KEY (labcode)
);
CREATE TABLE public.logs (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  pcid integer,
  action text,
  data text,
  staffid integer,
  CONSTRAINT logs_pkey PRIMARY KEY (id)
);
CREATE TABLE public.medicationstb (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  medicbone text,
  medicHb text,
  medicOther text,
  pcid bigint,
  note text,
  CONSTRAINT medicationstb_pkey PRIMARY KEY (id),
  CONSTRAINT medicationstb_pcid_fkey FOREIGN KEY (pcid) REFERENCES public.patients(pcid)
);
CREATE TABLE public.parathyroid (
  created_at timestamp with time zone DEFAULT now(),
  pthresult real,
  pthdate timestamp with time zone NOT NULL,
  treatmentnote text,
  pthscan text,
  pthlastsyncat timestamp with time zone,
  pcid bigint NOT NULL,
  pthyear integer NOT NULL,
  isdrrevpth boolean,
  CONSTRAINT parathyroid_pkey PRIMARY KEY (pthdate, pcid),
  CONSTRAINT parathyroid_pcid_fkey FOREIGN KEY (pcid) REFERENCES public.patients(pcid)
);
CREATE TABLE public.patientremarks (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL UNIQUE,
  pcid bigint NOT NULL,
  remarkid bigint,
  created_at timestamp without time zone DEFAULT now(),
  dodate date,
  source text,
  iscollected boolean,
  colldate date,
  CONSTRAINT patientremarks_pkey PRIMARY KEY (id)
);
CREATE TABLE public.patients (
  pcid bigint NOT NULL UNIQUE,
  created_at timestamp with time zone DEFAULT now(),
  name text NOT NULL,
  phone text,
  email text UNIQUE,
  plastsyncat timestamp with time zone,
  labgroup text DEFAULT 'Non Assigned'::text,
  dstaffid bigint,
  nstaffid bigint,
  inposition boolean,
  outpostioncause text,
  sex text,
  hall_main text,
  status text DEFAULT 'Active'::text CHECK (status = ANY (ARRAY['Active'::text, 'On Admission'::text, 'On Travel'::text, 'Other'::text])),
  height real,
  returndate date,
  ourunit boolean,
  birthdate date,
  lastposthdupdate date,
  nextduebw date,
  dialyzer text,
  vaccess text,
  heparin text,
  lastbwcollected text,
  lastlabnote text,
  day_main text,
  shift_main text,
  isdrreviwed boolean,
  has_doppler boolean,
  has_ecg boolean,
  CONSTRAINT patients_pkey PRIMARY KEY (pcid)
);
CREATE TABLE public.posthdinstructions (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL UNIQUE,
  created_at timestamp with time zone DEFAULT now(),
  posthdmedic text,
  pcid bigint NOT NULL,
  lastinstrucsync timestamp with time zone,
  day text,
  dose text,
  isneedupdate boolean DEFAULT false,
  CONSTRAINT posthdinstructions_pkey PRIMARY KEY (id),
  CONSTRAINT posthdinstructions_pcid_fkey FOREIGN KEY (pcid) REFERENCES public.patients(pcid)
);
CREATE TABLE public.remarks (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  remake text,
  lastsync timestamp without time zone,
  retype text,
  CONSTRAINT remarks_pkey PRIMARY KEY (id)
);
CREATE TABLE public.savebyjson (
  id bigint NOT NULL DEFAULT nextval('savebyjson_id_seq'::regclass),
  datajson jsonb NOT NULL CHECK (jsonb_typeof(datajson) = 'array'::text),
  tablename text NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  isupsert boolean,
  staffid integer,
  CONSTRAINT savebyjson_pkey PRIMARY KEY (id)
);
CREATE TABLE public.saveoffline (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  staffid integer,
  datakeep text,
  datatype text,
  isallsync boolean,
  new_up text,
  CONSTRAINT saveoffline_pkey PRIMARY KEY (id)
);
CREATE TABLE public.schedules (
  scheduleid bigint GENERATED ALWAYS AS IDENTITY NOT NULL UNIQUE,
  pcid bigint NOT NULL,
  created_at timestamp without time zone DEFAULT now(),
  day text,
  shift text NOT NULL,
  ispwithus boolean,
  schedtype text,
  hallname text,
  tempdate date,
  replaceday date,
  CONSTRAINT schedules_pkey PRIMARY KEY (scheduleid),
  CONSTRAINT schedules_pcid_fkey FOREIGN KEY (pcid) REFERENCES public.patients(pcid)
);
CREATE TABLE public.shifts (
  shift text,
  shiftid bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  CONSTRAINT shifts_pkey PRIMARY KEY (shiftid)
);
CREATE TABLE public.staff (
  medicalstaffid bigint NOT NULL UNIQUE,
  created_at timestamp with time zone DEFAULT now(),
  name text NOT NULL UNIQUE,
  phone text,
  email text,
  dlastsyncat timestamp with time zone,
  staffrole text,
  leavegodate date,
  leavbackdate date,
  isonwork boolean,
  userid uuid NOT NULL,
  fullname text,
  fcm_token text,
  CONSTRAINT staff_pkey PRIMARY KEY (medicalstaffid),
  CONSTRAINT staff_userid_fkey FOREIGN KEY (userid) REFERENCES auth.users(id)
);
CREATE TABLE public.testtable (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  name text,
  CONSTRAINT testtable_pkey PRIMARY KEY (id)
);
CREATE TABLE public.users (
  id uuid NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  usertype text,
  CONSTRAINT users_pkey PRIMARY KEY (id),
  CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id)
);
CREATE TABLE public.vascularaccess (
  vasid bigint GENERATED ALWAYS AS IDENTITY NOT NULL UNIQUE,
  created_at timestamp with time zone DEFAULT now(),
  haspcath boolean,
  hasavf boolean,
  hasavg boolean,
  vasclastsyncat timestamp with time zone,
  pcid bigint NOT NULL,
  vascularhist text,
  vascurrent text,
  appointnextdate date,
  CONSTRAINT vascularaccess_pkey PRIMARY KEY (vasid),
  CONSTRAINT vascularaccess_pcid_fkey FOREIGN KEY (pcid) REFERENCES public.patients(pcid)
);
CREATE TABLE public.virology (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL UNIQUE,
  created_at timestamp with time zone DEFAULT now(),
  vilastsyncat timestamp with time zone,
  pcid bigint NOT NULL,
  hcv boolean,
  hbv boolean,
  hiv boolean,
  invdate timestamp with time zone,
  hcvpcr text,
  CONSTRAINT virology_pkey PRIMARY KEY (id),
  CONSTRAINT virology_pcid_fkey FOREIGN KEY (pcid) REFERENCES public.patients(pcid)
);
CREATE TABLE public.weightdata (
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  preweight real,
  postweight real,
  lastsyncdate timestamp without time zone,
  pcid bigint,
  ufkept real,
  tolerance boolean DEFAULT true,
  sessionid bigint GENERATED ALWAYS AS IDENTITY NOT NULL UNIQUE,
  bfr integer,
  drywt real,
  CONSTRAINT weightdata_pkey PRIMARY KEY (sessionid),
  CONSTRAINT weightdata_pcid_fkey FOREIGN KEY (pcid) REFERENCES public.patients(pcid)
);