# F01: Claude Agent SDK on the subscription login

**Test id:** F01 · **Date:** 2026-11-16 · **Plan:** PLAN.md rev 5, §2, §2.1, §3, §9

## Verdict: PARTIAL

The technical part passes. With `ANTHROPIC_API_KEY` unset and every `CLAUDE_*`/`ANTHROPIC_*` variable removed from the environment, `claude-agent-sdk` 0.2.182 runs on the stored claude.ai login (`apiKeySource: "none"`; `claude auth status` reports `authMethod: claude.ai`). An SDK session loads exactly what `claude -p` loads: the same 38 MCP servers (claude.ai connectors, local stdio and HTTP servers, plugin servers), 9 plugins, 90 skills, 130 slash commands and 446 tools. An in-process `create_sdk_mcp_server` tool works alongside them. Latency is fine once the user's own `SessionStart` hook is excluded: a fresh `connect()` takes about 0.4 s, and a short Haiku turn reaches its first text in about 0.8–1.6 s. The `claude -p` stream-json fallback also works, including `--resume`.

It is PARTIAL rather than PASS for three reasons:
- **Footprint is above the plan's guesses.** Each session is one Claude Code process of about 250–325 MB. With default settings it also starts its own copies of the user's local stdio MCP servers, about 240 MB more, so about 510 MB per live session.
- **The terms are not settled.** The login here is a **Team** plan (the company org), not Pro/Max. The docs do not explicitly allow personal SDK use on a subscription login. They tell developers using the SDK to use API keys.
- **`AskUserQuestion` is missing from the tool list** in both SDK and `-p` sessions, and PLAN §3 relies on it.

## Environment

| Item | Value |
|---|---|
| macOS | 26.6.1 (25G76), arm64 |
| Python | 3.11.13 (uv project) |
| Claude Code (PATH) | 2.1.325 |
| claude-agent-sdk | **0.2.182** from PyPI. It ships its own CLI binary, `_bundled/claude` 2.1.325 (333 MB on disk; the `.venv` is 368 MB), and uses it in preference to PATH. |
| Other deps pulled in | mcp 2.3.0, pydantic 2.14.3, anyio 4.16.0, starlette, uvicorn, sse-starlette and others (see `uv.lock`) |
| Account | `claude auth status`: `loggedIn: true`, `authMethod: claude.ai`, `subscriptionType: team`, `orgName: <my employer>` |

**Method note.** This agent runs inside the Claude desktop app. That app injects about 35 `CLAUDE_*`/`ANTHROPIC_*` variables, including `ANTHROPIC_BASE_URL` and host-auth hooks. Every script was therefore run through `spikes/f01-sdk/cleanenv.sh` (`env -i` with only HOME, USER, LOGNAME, SHELL, LANG, TMPDIR and PATH), which is what a launchd-started app would get. `common.assert_no_api_key()` aborts if any such variable leaks through.

**Usage:** 24 short Haiku queries in total (p1: 3, p3: 1, p4: 15, p5: 2, p6: 3). The connect-only timing scripts (p4b, p4c) sent no queries. No connector tool was called.

## Results

### 1. Auth: PASS

`./cleanenv.sh claude auth status`, trimmed:
```
"loggedIn": true, "authMethod": "claude.ai", "apiProvider": "firstParty",
"subscriptionType": "team", "orgName": "<my employer>", "loginExpiresAt": "2026-11-25T17:37:35Z"
```
`./cleanenv.sh uv run python p1_init.py default` reads the init message:
```
{'apiKeySource': 'none', 'model': 'claude-haiku-5-5', 'claude_code_version': '2.1.325', 'reply': 'ok'}
result: {'is_error': False, 'subtype': 'success', ...}
```
- `apiKeySource: "none"` and a successful reply mean the session ran on the claude.ai OAuth login stored in the Claude config. No API key was involved.
- The `-p` fallback (p6) reports the same: `apiKeySource: 'none'`.
- `ResultMessage.total_cost_usd` is still filled in (for example 0.0047). It is a notional figure; nothing is billed to an API key.
- The login carries an expiry (`loginExpiresAt`). Refresh of an expired token from a launchd-started process was **unverified**.

### 2. What loads in an SDK session

Script: `p1_init.py {default|explicit|isolated}`. Each run writes `out/init_<mode>.json`.

| | default (`setting_sources=None`) | `["user","project","local"]` | isolated (`[]`) | `claude -p` stream-json (p6) |
|---|---|---|---|---|
| MCP servers | 38 | 38 (identical) | 29 | 38 (identical to SDK) |
| Plugins | 9 | 9 | 5 (built-ins only) | 9 |
| Skills | 90 | 90 | 19 | 90 |
| Slash commands | 130 | 130 | 55 | 130 |
| Agents | 8 | 8 | 6 | 8 |
| Tools | 446 | 446 | 264 | 446 |

- **Default and the explicit `["user","project","local"]` are identical** in every list. The SDK's docstring says `None` means "all sources loaded (matches CLI defaults)".
- **The SDK session and the `-p` CLI session are identical** in names, statuses, plugins, skills, agents and tools (comparison script inline in the transcript; data in `out/init_default.json` and `out/streamjson.json`).

**MCP servers (default):**
- **claude.ai connectors (29).** These load even in isolated mode, because they come from the account, not from settings files.
  - *connected:* Claude Data, Claude Docs, Meetings, Google Calendar, Google Drive, Gmail, Slack, Figma, Canva, Atlassian.
  - *needs-auth:* Google Cloud BigQuery, Atlassian MCP, Google Slides, Google Sheets, Datadog, Google Docs, ZoomInfo, Scrunch, Salesforce, Salesloft, Zoom for Claude, Lovable, Notion, monday.com, Linear, Intercom, HubSpot, Box, Asana.
- **User-config servers (dropped by isolated):** tradingview-mcp (stdio), web_search (stdio), voicemode (stdio), GitLab (HTTP), grafana-mcp (SSE), company-mcp-server (HTTP, *failed*: DCR 404).
- **Plugin MCP:** `plugin:engineering:datadog` (needs-auth), `plugin:engineering:google calendar` and `plugin:engineering:gmail` (failed; `claude mcp list` says "Not configured").
- **Not in the session list.** `claude mcp list` also shows `plugin:engineering:slack`, `:atlassian`, `:linear` and `:notion`. These are missing from the session's init list. A likely cause, **unverified**, is that duplicates of claude.ai connectors are dropped.
- **Status drift.** Google Slides, Sheets and Docs show `✔ Connected` in `claude mcp list` but `needs-auth` in the session init. The cause is **unverified**.

**Plugins (default):** company-plugin-a, company-plugin-b (0.17.0), engineering (1.2.0), cowork-plugin-management (0.2.2), plus the built-ins cc-plugin-sec-default, cc-plugin-agents-md, cc-plugin-telemetry, cc-plugin-privacy and cc-plugin-plugin-authoring.

**Skills (default, 90):**
- User skills: create-portrait-image, purge-tenant-data, work-context.
- Plugin skills: `company-plugin-a:*` (27), `company-plugin-b:*` (13), `engineering:*` (10), `cowork-plugin-management:*` (2).
- `anthropic-skills:*` (16).
- Built-ins (19): deep-research, design, design-sync, dataviz, update-config, verify, debug, code-review, simplify, batch, fewer-permission-prompts, doctor, loop, schedule, claude-api, workflow-authoring, run, run-skill-generator, plugin-authoring.

**Agents:** claude, Explore, general-purpose, Plan, statusline-setup, web-fetch, plus two review agents from plugins.

**Built-in tools (29):** Task, Bash, CronCreate, CronDelete, CronList, DesignSync, Edit, EnterWorktree, ExitWorktree, ListAgents, ListMcpResourcesTool, Monitor, NotebookEdit, PublishPlugin, PushNotification, Read, ReadMcpResourceDirTool, ReadMcpResourceTool, RemoteTrigger, ReportFindings, ScheduleWakeup, SendMessage, ShareOnboardingGuide, Skill, TaskStop, ToolSearch, WebSearch, Workflow, Write.

**Missing tools.** These are **absent** in SDK, `-p` and isolated sessions alike: `AskUserQuestion`, `WebFetch`, `Glob`, `Grep`, `TodoWrite`.
- The desktop host sets `CLAUDE_CODE_ENABLE_ASK_USER_QUESTION_TOOL`. That suggests `AskUserQuestion` is opt-in outside interactive mode, but this is **unverified (not tested)**.

**Other observations:**
- **The init message only arrives after the first query** (`init_before_query: False`), in both the SDK and `-p`. The core cannot inspect the tool list before the first turn.
- **The user's `SessionStart` hook runs in SDK sessions.** `~/.claude/settings.json` has one (matcher `startup`, `register_claude_code_agent.py`). See Q4.

### 3. In-process MCP: PASS

Script: `p3_inproc.py`. It creates server `va` with one tool, `echo`, sets `allowed_tools=["mcp__va__echo"]` and uses the default setting sources.
```
va_status = [('va', 'connected')]
mcp_server_count = 39            # 38 user/account servers + va
connected_others = ['tradingview-mcp', 'web_search', 'GitLab', 'grafana-mcp', 'voicemode', 'claude.ai Claude Data', ... 'claude.ai Atlassian']
va_tools_in_init = ['mcp__va__echo']
handler_calls = [{'text': 'ping-123'}]          # the Python handler ran in our process
events = [tool_use mcp__va__echo {'text':'ping-123'}, tool_result 'echo: ping-123', text 'echo: ping-123', result success]
```

### 4. Latency

Scripts:
- `p4_latency.py 3 default`
- `p4_latency.py 2 nohooks`: all setting sources, hooks disabled with a flag-level `--settings '{"disableAllHooks":true}'`; nothing in `~/.claude` was changed.
- `p4b_connect.py` and `p4c_nohooks.py`: connect-only, no queries.

Model: `claude-haiku-5-5`. Clock: `time.perf_counter`. "First text" means the first `text_delta` stream event (`include_partial_messages=True`).

**Main table:**

| Metric | default (3 runs): median (range), s | hooks off (2 runs): median (range), s |
|---|---|---|
| `connect()` returns | **11.008** (11.008–11.468) | **0.406** (0.402–0.409) |
| connect start → init message (init only after query 1) | 11.059 (11.058–11.553) | 0.454 (0.450–0.458) |
| query sent → init | 0.051 (0.051–0.085) | 0.048 (0.048–0.048) |
| query sent → first streamed text (new client) | 0.883 (0.871–1.195) | 1.278 (1.008–1.549) |
| 2nd query on connected client → first text | 0.834 (0.789–0.929) | 1.639 (0.780–2.498) |
| resume by id: connect start → first text | 1.603 (1.492–1.651) | 1.608 (1.577–1.640) |
| resume: `connect()` alone | 0.440 (0.416–0.510) | 0.489 (0.439–0.539) |

- Resume kept the same `session_id` in every run (`resume_same_session_id: True`).
- The 2.498 s outlier in the hooks-off column is a single API-side slow turn. With only 2 runs, that column's medians are weak.

**Why `connect()` takes 11 s.** Connect-only timing, 3 runs each, no queries (`out/connect_only.json`, `out/connect_nohooks.json`):

| Variant | `connect()` median (range), s |
|---|---|
| fresh, default settings | 10.997 (10.958–11.526) |
| fresh, default + `--strict-mcp-config` | 11.005 (10.900–11.021) |
| fresh, isolated (`setting_sources=[]`) | 0.321 (0.318–0.334) |
| fresh, default + hooks disabled | **0.383** (0.375–0.631) |
| resume, default settings | 0.433 (0.428–0.443) |

The ~10.6 s is the user's own `SessionStart` hook. It has matcher `startup`, so it runs on fresh sessions but not on resume, and it does not run when hooks are disabled. It is not SDK overhead. The hook script was not run directly, because running it may register an agent remotely.

### 5. Footprint

Script: `p5_footprint.py 30 {default|isolated}`. It takes `ps -o rss`, connects, runs one turn, then samples the process tree every 1 s for 30 s. CPU % is the cumulative `ps` CPU time used during the window divided by 30 s. Hooks were disabled for this test.

**Python process:**

| | RSS |
|---|---|
| Bare Python 3.11 (before import) | 21.5 MB |
| SDK imported, idle 3 s | **68.4 MB** (68.6 MB on the second run); import took 0.48–0.81 s |
| Same process later, idle with a live session | 38.7–41.2 MB; `ps` shows RSS falling as macOS reclaims pages |

**Process tree, default settings, idle after one turn** (`out/footprint_default_run1.json`):

| Process | RSS right after turn | RSS after 30 s | CPU, 30 s idle |
|---|---|---|---|
| python (core) | 70.9 MB | 41.2 MB | 0.43 % |
| └ `claude` (SDK `_bundled/claude`) | 324.8 MB | **273.0 MB** | 1.03 % |
| &nbsp;&nbsp;└ node tradingview-mcp (stdio) | 80.5 MB | 67.9 MB | 0.0 % |
| &nbsp;&nbsp;└ ucode mcp web-search (stdio) | 40.4 MB | 33.8 MB | 0.0 % |
| &nbsp;&nbsp;└ uvx voicemode-mcp-launcher | 23.8 MB | 17.4 MB | 0.0 % |
| &nbsp;&nbsp;&nbsp;&nbsp;└ voicemode python | 131.0 MB | 117.8 MB | 0.0 % |
| **Children total** | | **509.9 MB** | |

**Process tree, isolated settings** (`out/footprint_isolated.json`):

| Process | RSS after 30 s | CPU, 30 s idle |
|---|---|---|
| python (core) | 38.7 MB | 0.30 % |
| └ `claude` | **248.3 MB** | 0.83 % |

Notes:
- **Every SDK session starts its own copies of the user's stdio MCP servers.** HTTP, SSE and claude.ai servers create no local process.
- The core's idle CPU figure includes the sampler itself, which runs `ps` every second. The real idle cost is lower.
- The `claude` process keeps about 1 % CPU while idle.

### 6. Fallback: `claude -p` stream-json: PASS

Script: `p6_streamjson.py`. It runs `claude -p --input-format stream-json --output-format stream-json --verbose --model claude-haiku-5-5 --settings '{"disableAllHooks":true}'`, sends two turns over stdin, closes stdin, then runs `--resume <id>` in a new process.
```
init_before_first_input: False
turn1_send_to_first_text_s: 1.063   turn1_reply: noted          (prompt: remember code word PELICAN)
turn2_send_to_first_text_s: 1.148   turn2_reply: two
same_process_session_id_stable: True    session_id: b68a18be-…    exit_code: 0
resume_spawn_to_first_text_s: 2.064     resume_reply: PELICAN        resume_session_id: b68a18be-… (same)
cli_init: {'apiKeySource': 'none', 'model': 'claude-haiku-5-5', 'claude_code_version': '2.1.325'}
```
- **Startup time.** No init line appears until the first input arrives. The script waited 6 s for one before sending, so `spawn_to_init_s` = 6.08 is an artifact. The usable cold-start figure is **process spawn → first text = 2.06 s** on the resume run. That includes process start, MCP setup and the API turn, and is comparable to the SDK's 1.6 s resume figure.
- The session id is taken from the output stream and stays stable across turns.

### 7. Docs check: UNRESOLVED for this account

- https://code.claude.com/docs/en/legal-and-compliance says: "Advertised usage limits for Pro, Max, and Ultra plans assume ordinary, individual usage of Claude Code and the Agent SDK." The same page says OAuth is for subscription purchasers' "ordinary use of Claude Code and other native Anthropic applications". It says developers building products with the Agent SDK "should use API key authentication", and that third parties may not offer claude.ai login.
- https://code.claude.com/docs/en/agent-sdk/overview says third-party developers may not offer claude.ai login "including agents built on the Claude Agent SDK", and that SDK use is governed by the Commercial Terms.
- **Neither page explicitly allows or forbids** a single user running the SDK locally on their own subscription login. The first quote implies it is expected for individual plans.
- **This login is a Team plan owned by the employer.** Using it for a personal assistant is a question for employer and IT policy, not only Anthropic's terms. **Update 2026-11-17: IT confirmed this use is fine** (reported by me).

## Implications for PLAN.md

**Keep**
- SDK as the brain (§2). Subscription auth works with no API key, and connectors, plugins and skills load the same way as in the CLI.
- In-process SDK MCP servers for `ui`, `mac` and the other built-in tools (§4).
- Resume by id. Resume `connect()` takes about 0.44 s, and the session id stays stable and works with `claude -p --resume`.
- The `-p` stream-json fallback. It is proven, so the §2 Brain fallback can stay as written.

**Change**
- **§2.1 footprint.** Replace "likely 100–300 MB each" with the measured figures:
  - about 250–325 MB per Claude Code process;
  - plus about 240 MB of per-session stdio MCP servers under default settings;
  - so up to about 510 MB per live session, or about 1.5 GB at the 1 + 2 session cap.
- **§2.1 "Core memory, idle ≤ 80 MB".** It holds: 68 MB measured after import. It is tight, though, and that is before httpx and app code. The 0.5–0.8 s import time fits within the 1.5 s "core ready" budget.
- **Choose setting sources per session type.**
  - Conversation sessions need connectors and skills, but not tradingview or voicemode. Note that voicemode is itself a voice MCP and would conflict with the app's mic.
  - Use `setting_sources` together with an explicit `mcp_servers`/`--strict-mcp-config` list, or the planned allowlist, so local stdio servers are not started in every session.
  - claude.ai connectors still load with `setting_sources=[]`. The approval gate (B1/B2) must account for that.
- **Hooks.** The user's `SessionStart` hook adds about 10.6 s to every fresh session.
  - Either pass `--settings '{"disableAllHooks":true}'`, which also disables any user `PreToolUse` hooks (fine, since our gate is an SDK callback hook), or scope it.
  - Re-check that SDK `hooks=` callbacks still fire with `disableAllHooks` (**unverified**).
- **§3 AskUserQuestion.** It is absent from the tool list in SDK and `-p` sessions. Phase 0 must confirm that `CLAUDE_CODE_ENABLE_ASK_USER_QUESTION_TOOL=1` (or an equivalent option) enables it, or redesign questions as an in-process `ui.ask` tool.
- **§9.** Tick "SDK uses my subscription login" and "connectors and plugins load". Add: "Terms and employer policy for using the Team login for a personal assistant".

**Add**
- **Clean environment.** The core must start the SDK with a clean environment. When it is launched from inside Claude desktop, it would otherwise inherit `ANTHROPIC_BASE_URL` and host-auth variables.
- **Install size.** The SDK bundles its own 333 MB `claude` binary (2.1.325), separate from the PATH install. Pin `cli_path` to the user's `claude` if the two should stay in step, or accept two versions.
- **Init only after the first query.** Init arrives only after the first query, so tool and connector health cannot be read at connect time. Use `claude mcp list` or the first turn.
- **Pre-warm.** It is cheap. A connected idle client costs about 250 MB and about 1 % CPU, and saves about 0.4 s of connect time. Off by default is still right for footprint.
- **Login expiry.** Watch `loginExpiresAt`. Test token refresh in a long-lived core (**unverified**).

## How to re-run

```sh
cd feasibility/spikes/f01-sdk
uv sync                                                   # claude-agent-sdk 0.2.182 per uv.lock
./cleanenv.sh claude auth status                          # Q1
./cleanenv.sh uv run python p1_init.py default            # Q1/Q2, also: explicit, isolated  (1 query each)
./cleanenv.sh uv run python p3_inproc.py                  # Q3 (1 query)
./cleanenv.sh uv run python p4_latency.py 3 default       # Q4 (9 queries); also: 3 nohooks
./cleanenv.sh uv run python p4b_connect.py <session_id>   # Q4 connect-only, no queries
./cleanenv.sh uv run python p4c_nohooks.py                # Q4 connect-only with hooks off, no queries
./cleanenv.sh uv run python p5_footprint.py 30 default    # Q5 (1 query); also: 30 isolated
./cleanenv.sh uv run python p6_streamjson.py              # Q6 (3 queries)
./cleanenv.sh claude mcp list                             # CLI-side MCP view for Q2
```
Raw outputs are in `spikes/f01-sdk/out/*.json`.
