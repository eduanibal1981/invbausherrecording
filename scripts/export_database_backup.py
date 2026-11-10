import os
import json
import shutil
import requests
from datetime import datetime

PROJECT_REF = os.environ.get("SUPABASE_PROJECT_REF", "gyshsorklnpudckucpva")
TOKEN = os.environ.get("SUPABASE_ACCESS_TOKEN", "")
BASE_URL = f"https://api.supabase.com/v1/projects/{PROJECT_REF}/database/query"
HEADERS = {
    "Authorization": f"Bearer {TOKEN}",
    "Content-Type": "application/json"
}

BACKUP_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backups")
os.makedirs(BACKUP_DIR, exist_ok=True)

def run_query(sql):
    response = requests.post(BASE_URL, headers=HEADERS, json={"query": sql})
    if response.status_code not in (200, 201):
        raise Exception(f"Query failed [{response.status_code}]: {response.text}")
    return response.json()

def format_sql_value(val):
    if val is None:
        return "NULL"
    elif isinstance(val, bool):
        return "TRUE" if val else "FALSE"
    elif isinstance(val, (int, float)):
        return str(val)
    elif isinstance(val, (dict, list)):
        escaped_json = json.dumps(val).replace("'", "''")
        return f"'{escaped_json}'::jsonb"
    elif isinstance(val, str):
        escaped = val.replace("'", "''")
        return f"'{escaped}'"
    else:
        escaped = str(val).replace("'", "''")
        return f"'{escaped}'"

def dump_table_rows(schema, table_name):
    print(f"Fetching {schema}.{table_name}...")
    all_rows = []
    offset = 0
    batch_size = 1000

    while True:
        query = f'SELECT * FROM "{schema}"."{table_name}" LIMIT {batch_size} OFFSET {offset};'
        rows = run_query(query)
        if not rows:
            break
        all_rows.extend(rows)
        offset += len(rows)
        if len(rows) < batch_size:
            break

    print(f"  -> {len(all_rows)} rows retrieved from {schema}.{table_name}")
    return all_rows

def build_insert_statements(schema, table_name, rows, on_conflict_clause=""):
    if not rows:
        return f"-- Table {schema}.{table_name} has 0 rows\n"
    
    statements = []
    cols = list(rows[0].keys())
    col_clause = ", ".join(f'"{c}"' for c in cols)
    
    batch = []
    batch_size = 100
    
    for i, row in enumerate(rows):
        vals = [format_sql_value(row.get(c)) for c in cols]
        batch.append(f"({', '.join(vals)})")
        
        if len(batch) >= batch_size or i == len(rows) - 1:
            sql = f'INSERT INTO "{schema}"."{table_name}" ({col_clause})\nVALUES\n  ' + ",\n  ".join(batch)
            if on_conflict_clause:
                sql += f"\n{on_conflict_clause}"
            sql += ";\n"
            statements.append(sql)
            batch = []
            
    return "\n".join(statements)

def main():
    start_time = datetime.now()
    print("=" * 60)
    print(f"Starting Complete Supabase Database Backup for project: {PROJECT_REF}")
    print(f"Timestamp: {start_time.isoformat()}")
    print("=" * 60)

    # 1. Copy full schema
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    fullschema_src = os.path.join(repo_root, "supabase", "fullschema.sql")
    schema_dest = os.path.join(BACKUP_DIR, "schema.sql")
    if os.path.exists(fullschema_src):
        shutil.copyfile(fullschema_src, schema_dest)
        print(f"[1/5] Schema definition copied to {schema_dest}")

    # 2. Backup Auth Schema (Users and Identities)
    print("\n[2/5] Backing up Auth schema...")
    auth_users = dump_table_rows("auth", "users")
    auth_identities = dump_table_rows("auth", "identities")
    
    auth_sql_path = os.path.join(BACKUP_DIR, "data_auth.sql")
    with open(auth_sql_path, "w", encoding="utf-8") as f:
        f.write("-- =====================================================\n")
        f.write(f"-- Supabase Auth Schema Backup\n")
        f.write(f"-- Generated on: {datetime.now().isoformat()}\n")
        f.write(f"-- Project: {PROJECT_REF}\n")
        f.write("-- =====================================================\n\n")
        f.write("BEGIN;\n")
        f.write("SET session_replication_role = 'replica';\n\n")
        
        f.write("-- 1. auth.users\n")
        f.write(build_insert_statements("auth", "users", auth_users, on_conflict_clause="ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email, encrypted_password = EXCLUDED.encrypted_password, updated_at = EXCLUDED.updated_at"))
        f.write("\n")
        
        f.write("-- 2. auth.identities\n")
        f.write(build_insert_statements("auth", "identities", auth_identities, on_conflict_clause="ON CONFLICT (provider, id) DO NOTHING"))
        f.write("\n")
        
        f.write("SET session_replication_role = 'origin';\n")
        f.write("COMMIT;\n")
    print(f"Auth backup written to {auth_sql_path}")

    # 3. Discover and order all public tables
    print("\n[3/5] Discovering public tables...")
    public_tables_info = run_query("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE' ORDER BY table_name;")
    all_public_tables = [row["table_name"] for row in public_tables_info]

    ordered_priority = [
        # Lookups & base configs
        "halls", "shifts", "remarks", "labdays", "labnormalrange", "staff", "employees", "medicationstb",
        # Groupings & Roster
        "hall_schedule_config", "groupsofpatients", "duty_roster",
        # Patients
        "patients", "patientremarks",
        # Clinical & Investigation records
        "schedules", "bloodweek", "bloodweekgroups", "parathyroid", "ironprofile", "vascularaccess",
        "doppplerslinks", "ecg_links", "antibiotics", "anticoagulant", "dialyzer", "dryweight",
        "history", "inr", "posthdinstructions", "weightdata", "virology", "logs", "users"
    ]
    
    # Add any tables that might exist but weren't explicitly listed
    for t in all_public_tables:
        if t not in ordered_priority:
            ordered_priority.append(t)

    # 4. Dump all public tables
    print("\n[4/5] Backing up public tables data...")
    public_data = {}
    summary = {
        "project_ref": PROJECT_REF,
        "backup_date": datetime.now().isoformat(),
        "auth_users_count": len(auth_users),
        "auth_identities_count": len(auth_identities),
        "tables": {}
    }

    public_sql_path = os.path.join(BACKUP_DIR, "data_public.sql")
    with open(public_sql_path, "w", encoding="utf-8") as f:
        f.write("-- =====================================================\n")
        f.write(f"-- Supabase Public Schema Data Backup\n")
        f.write(f"-- Generated on: {datetime.now().isoformat()}\n")
        f.write(f"-- Project: {PROJECT_REF}\n")
        f.write("-- =====================================================\n\n")
        f.write("BEGIN;\n")
        f.write("SET statement_timeout = 0;\n")
        f.write("SET client_encoding = 'UTF8';\n")
        f.write("SET standard_conforming_strings = on;\n")
        f.write("SET check_function_bodies = false;\n")
        f.write("SET row_security = off;\n")
        f.write("-- Disable FK checks and triggers during bulk data restore\n")
        f.write("SET session_replication_role = 'replica';\n\n")

        for table in ordered_priority:
            if table not in all_public_tables:
                continue
            rows = dump_table_rows("public", table)
            public_data[table] = rows
            summary["tables"][table] = len(rows)
            f.write(f"-- -----------------------------------------------------\n")
            f.write(f"-- Data for public.{table} ({len(rows)} records)\n")
            f.write(f"-- -----------------------------------------------------\n")
            f.write(build_insert_statements("public", table, rows))
            f.write("\n")

        # Sequences reset
        f.write("-- -----------------------------------------------------\n")
        f.write("-- Reset Sequences to prevent primary key collisions\n")
        f.write("-- -----------------------------------------------------\n")
        f.write("""DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT table_name, column_name, column_default
        FROM information_schema.columns
        WHERE table_schema = 'public' AND column_default LIKE 'nextval(%'
    ) LOOP
        EXECUTE format(
            'SELECT setval(pg_get_serial_sequence(%L, %L), coalesce(max(%I), 1)) FROM %I',
            r.table_name, r.column_name, r.column_name, r.table_name
        );
    END LOOP;
END $$;\n\n""")

        f.write("-- Re-enable FK checks and triggers\n")
        f.write("SET session_replication_role = 'origin';\n")
        f.write("COMMIT;\n")

    print(f"Public data backup written to {public_sql_path}")

    # 5. Save JSON fallback
    json_path = os.path.join(BACKUP_DIR, "data_all.json")
    print(f"\n[5/5] Writing universal JSON export to {json_path}...")
    complete_json = {
        "metadata": {
            "project_ref": PROJECT_REF,
            "backup_date": datetime.now().isoformat(),
            "total_tables": len(summary["tables"]),
            "total_auth_users": len(auth_users)
        },
        "auth": {
            "users": auth_users,
            "identities": auth_identities
        },
        "public": public_data
    }
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(complete_json, f, indent=2, ensure_ascii=False)

    # Write summary
    summary_path = os.path.join(BACKUP_DIR, "summary.json")
    with open(summary_path, "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2)

    # 6. Write Restore Guide
    guide_path = os.path.join(BACKUP_DIR, "RESTORE_GUIDE.md")
    with open(guide_path, "w", encoding="utf-8") as f:
        f.write(f"""# Database Restore Guide

This backup was generated on **{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}** from project **`{PROJECT_REF}`**.

## Backup Files Included

| File | Purpose | Contents |
| :--- | :--- | :--- |
| `schema.sql` | Database schema | Tables, views, functions, triggers, and RLS policies |
| `data_auth.sql` | Supabase Authentication | User credentials, password hashes, and identities ({len(auth_users)} users) |
| `data_public.sql` | Application Data | All {len(summary['tables'])} public tables ({sum(summary['tables'].values())} total rows) |
| `data_all.json` | Universal JSON Backup | Complete structured JSON dump of all schemas & data |
| `summary.json` | Backup Statistics | Breakdown of row counts per table |

---

## How to Restore to a New Supabase Project

### Step 1: Create the New Project
1. Go to [supabase.com/dashboard](https://supabase.com/dashboard) and create your new project.
2. Note your new **Project Reference**, **Database Password**, and **Region**.

### Step 2: Run the SQL Files (in Order)

You can run the files via the **Supabase Dashboard SQL Editor** or via `psql`:

#### Using psql:
```bash
# Get your connection string from: Project Settings -> Database -> Connection string (URI)
NEW_DB_URL="postgresql://postgres.[NEW_REF]:[PASSWORD]@aws-0-[REGION].pooler.supabase.com:6543/postgres"

# 1. Apply Schema
psql "$NEW_DB_URL" -f backups/schema.sql

# 2. Restore Auth Users (so staff passwords and logins remain identical)
psql "$NEW_DB_URL" -f backups/data_auth.sql

# 3. Restore Public Application Data
psql "$NEW_DB_URL" -f backups/data_public.sql
```

#### Using Supabase Web Dashboard:
1. Open the new project in Supabase.
2. Go to the **SQL Editor**.
3. Run `backups/schema.sql`.
4. Run `backups/data_auth.sql`.
5. Run `backups/data_public.sql`.
6. Run the PostgREST cache reload:
   ```sql
   NOTIFY pgrst, 'reload schema';
   ```

### Step 3: Update Flutter Application
In `lib/main.dart`, update the Supabase URL and anonKey:
```dart
await Supabase.initialize(
  url: 'https://[NEW_PROJECT_REF].supabase.co',
  anonKey: '[NEW_ANON_KEY]',
);
```
""")

    duration = (datetime.now() - start_time).total_seconds()
    print("\n" + "=" * 60)
    print(f"SUCCESS! Database backup completed in {duration:.2f} seconds.")
    print(f"Auth users backed up: {len(auth_users)}")
    print(f"Public tables backed up: {len(summary['tables'])}")
    print(f"Total rows backed up: {sum(summary['tables'].values())}")
    print(f"Backup directory: {BACKUP_DIR}")
    print("=" * 60)

if __name__ == "__main__":
    main()
