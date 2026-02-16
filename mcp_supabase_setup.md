# Supabase MCP Connection Plan

This guide outlines the steps to connect the Supabase MCP server to the Codex environment securely.

## 1. Security Setup (Environment Variable)
**Crucial:** Never hardcode the token in the config file. Set the token in your current shell session (PowerShell example below).

```powershell
$env:SUPABASE_ACCESS_TOKEN="your_token_here"
2. Global Configuration
Add the server definition to your Global Codex Config (usually config.toml), not the project-specific config.

Config Block:

Ini, TOML
[mcp_servers.supabase-gyshsorklnpudckucpva]
enabled = true
url = "[https://mcp.supabase.com/mcp?project_ref=gyshsorklnpudckucpva](https://mcp.supabase.com/mcp?project_ref=gyshsorklnpudckucpva)"
bearer_token_env_var = "SUPABASE_ACCESS_TOKEN"
3. Authentication
Run the one-time MCP authentication command to establish the link.

Bash
codex mcp login supabase-gyshsorklnpudckucpva
4. Verification
Verify that the server is active and responding correctly.

Check Server List:

Bash
codex mcp list
Test Execution:
Run a specific command to fetch the project URL:

Bash
codex exec "Using mcp__supabase-gyshsorklnpudckucpva__get_project_url, return only the project URL."


Yes. I analyzed it via Supabase MCP and found the nurse-assignment SQL path.

Main assignment RPC: public.sync_all_patients_staffid()
Supporting trigger function: public.update_groupsofpatients_staffid()
Extra function present but not wired by trigger: public.update_patients_staffid()
What each does:

sync_all_patients_staffid() updates patients.nstaffid by joining:
patients.(hall_main, day_main, shift_main) to groupsofpatients.(ghall, gday, gshift)
only when groupsofpatients.staffid IS NOT NULL
only when groupsofpatients.ismain = true
only when patients.status = 'Active'
only when value changed (IS DISTINCT FROM)
update_groupsofpatients_staffid() trigger logic propagates one staffid change to day-sets:
Saturday/Monday/Wednesday as one set
Sunday/Tuesday/Thursday as one set
same ghall + gshift
Trigger bound in DB:
trg_groups_patients_staffid on groupsofpatients
AFTER INSERT OR UPDATE OF staffid
executes update_groupsofpatients_staffid()
Important finding:

sync_all_patients_staffid() does not clear patients.nstaffid to NULL when no match or when staffid becomes null.
So stale nurse assignments can remain unless your app/manual SQL explicitly clears them (your Flutter screen currently does extra cleanup on remove).
If you want, I can now generate the exact SQL migration to make sync_all_patients_staffid() fully reconcile (assign + unassign).