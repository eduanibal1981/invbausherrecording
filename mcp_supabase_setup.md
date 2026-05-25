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

