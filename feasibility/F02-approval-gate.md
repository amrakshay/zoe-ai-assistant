# F02: Approval gate (PreToolUse hook vs allow rules, user-input tools, interactive commands, forking)

**Test id:** F02 · **Date:** 2026-11-16 (runs 13:00–13:30 UTC) · **Plan:** PLAN.md rev 5 §4, §5.1, §5.9, §5.10, §7; REVIEW.md B1, S2, S7

## Verdict: PASS (with three design changes)

A `PreToolUse` hook works as the approval gate. It fires before settings allow rules and `allowed_tools`. Its deny always wins, and its "ask" forces `can_use_tool` even when an allow rule matches. It can await for 70 s and then decide. Each of the seven questions has output that shows the answer.

Three results change the §7 design:
1. **A hook that raises fails OPEN** with the default `on_failure`. An allow rule then runs the tool. Set `on_failure="block"` on every gate matcher.
2. **A hook timeout fails closed** (the tool doesn't run). The documented default of 60 s was **not** enforced in a 70 s wait. Set an explicit `timeout`; the 4 h job auto-deny needs a timeout of at least 14,400 s, or a different mechanism.
3. **Plan mode writes `~/.claude/plans/*.md`** outside the repo. That write is auto-allowed, and `can_use_tool` is not called; only the hook saw it.

Also: in an **untrusted** workspace, project `permissions.allow` is ignored entirely. B1 still reproduces through `--settings` and `allowed_tools`, and real repos are trusted.

## Environment

| Item | Value |
|---|---|
| macOS | 26.6.1, arm64 |
| Claude Code | 2.1.325 (`claude --version`; also the SDK's bundled CLI, `_cli_version.py`) |
| claude-agent-sdk (Python) | 0.2.182 |
| Python | 3.12.13 (uv) |
| Model | `claude-haiku-5-5` |
| Isolation | `setting_sources=["project"]`, `mcp_servers={}`, `strict_mcp_config=True`, `plugins=[]`, env `ENABLE_CLAUDEAI_MCP_SERVERS=false`, `tools` limited to Bash/Read/Write/AskUserQuestion/ExitPlanMode |
| Init frame | `mcp_servers= []`. Five **builtin** plugins still listed (`cc-plugin-sec-default`, `-agents-md`, `-telemetry`, `-privacy`, `-plugin-authoring`); `plugins=[]` doesn't remove them |

Spike folder: `spikes/f02-gate/` (uv project; scripts, `logs/` and the temp git repo `repo/`, whose `.claude/settings.json` is `{"permissions":{"allow":["Bash(touch:*)"]}}`). The runs used about 28 short queries; total cost was under US$0.05.

---

## 1. Hook before allow rules

**Script:** `spikes/f02-gate/q1_hook_vs_allow.py <nohook|deny|ask> [project|flag|allowed_tools]`. Claude is asked to run `touch hello.txt`. `can_use_tool` logs every call and **denies**, so if `hello.txt` exists afterwards, `can_use_tool` was never consulted.

**First finding: the project allow rule is ignored in an untrusted workspace.** The CLI printed this on every run:
```
Ignoring 1 permissions.allow entry from .claude/settings.json: this workspace has not been trusted. Run Claude Code interactively here once and accept the trust dialog, or set projects[...].hasTrustDialogAccepted: true in ~/.claude.json.
```
I didn't edit `~/.claude.json` (user config). So with `project` as the only source, the rule had no effect: `nohook` gave `{'hook': 0, 'can_use_tool': 1} hello.txt exists: False` (`logs/q1_nohook.log`).

I then loaded the same allow rule two other ways: the same file passed via `ClaudeAgentOptions.settings` (the `--settings` flag), and `allowed_tools=["Bash(touch:*)"]`.

| Run | Hook calls | `can_use_tool` calls | `hello.txt` created | Log |
|---|---|---|---|---|
| nohook + `--settings` | 0 | **0** | **True** | `logs/q1_nohook_flag.log` |
| nohook + `allowed_tools` | 0 | **0** | **True** | `logs/q1_nohook_allowed_tools.log` |
| hook deny + `--settings` | 1 | 0 | False | `logs/q1_deny_flag.log` |
| hook deny + `allowed_tools` | 1 | 0 | False | `logs/q1_deny_allowed_tools.log` |
| hook ask + `--settings` | 1 | 1 | False | `logs/q1_ask_flag.log` |
| hook ask + `allowed_tools` | 1 | 1 | False | `logs/q1_ask_allowed_tools.log` |

(a) **B1 confirmed.** With a matching allow rule and no hook, the command runs and `can_use_tool` is never called:
```
[   1.67s] TOOL_USE: Bash {"command": "touch hello.txt", ...}
[   2.29s] TOOL_RESULT is_error= False (Bash completed with no output)
[   4.23s] MODE nohook allow source flag calls {'hook': 0, 'can_use_tool': 0} hello.txt exists: True
```
(b) **The hook fires first and wins.** Deny:
```
[   1.82s] PRE_TOOL_USE hook: Bash {"command": "touch hello.txt", ...}
[   1.83s] TOOL_RESULT is_error= True PreToolUse:Bash hook error: F02 test hook says deny
[   3.97s] MODE deny allow source flag calls {'hook': 1, 'can_use_tool': 0} hello.txt exists: False
```
The deny reason reaches Claude as a tool error, labelled "hook error".

**Unverified:** user-level `~/.claude/settings.json` allow rules (not loaded here, by rule). I also didn't test a trusted workspace's project rules directly. The `--settings` and `allowed_tools` paths show the same precedence, and the warning text implies a trusted repo's rules would apply.

## 2. The hook as the asker (long awaits, timeouts, failures)

**Script:** `spikes/f02-gate/q2_hook_wait.py <sleep_s> <allow|deny|raise> [matcher_timeout|none] [on_failure] [allowed_tools]`. The hook `await asyncio.sleep(N)` then returns a decision. `can_use_tool` denies, so a created file means the hook's allow was honoured.

| Sleep | Decision | `HookMatcher.timeout` | `on_failure` | Allow rule | Outcome | Log |
|---|---|---|---|---|---|---|
| 5 s | allow | unset | unset | no | ran; `can_use_tool` 0; turn 8.1 s | `logs/q2_5_allow.log` |
| 5 s | deny | unset | unset | no | blocked | `logs/q2_5_deny.log` |
| **70 s** | allow | **unset** | unset | no | **ran after 70.0 s**; no timeout fired | `logs/q2_70_allow.log` |
| 70 s | allow | 600 | unset | no | ran after 70.0 s | `logs/q2_70_allow_600.log` |
| 20 s | allow | **5** | unset | no | hook **cancelled at 5.0 s**; tool **not run** | `logs/q2_20_allow_5.log` |
| 20 s | allow | 5 | continue | **yes** | cancelled at 5.0 s; **not run** (fails closed even with an allow rule) | `logs/q2_20_allow_5_continue_allowed_tools.log` |
| 20 s | allow | 5 | block | yes | cancelled at 5.0 s; not run | `logs/q2_20_allow_5_block_allowed_tools.log` |
| 0 | **raise** | unset | **continue** | **yes** | **RAN, so it FAILS OPEN** | `logs/q2_0_raise_none_continue_allowed_tools.log` |
| 0 | raise | unset | **block** | yes | blocked | `logs/q2_0_raise_none_block_allowed_tools.log` |

(The `q2_20_allow_5_none_allowed_tools.log` run passed the literal string `"none"` as `on_failure` by mistake. It also failed closed.)

The 70 s wait with the default timeout:
```
[   1.54s] PRE_TOOL_USE hook start (Bash), awaiting 70.0s 'user click'
[  71.54s] PRE_TOOL_USE hook returning allow after 70.0s
[  72.23s] TOOL_RESULT is_error= False (Bash completed with no output)
```
Timeout expiry:
```
[   6.89s] hook sleep interrupted: CancelledError after 5.0s
[   6.89s] TOOL_RESULT is_error= True PreToolUse hook did not respond before its timeout (host client may be unreachable). The tool call was not executed; ...
```
An exception with the default `on_failure`, while an allow rule matches:
```
[   1.60s] PRE_TOOL_USE hook raising RuntimeError
Error in hook callback hook_0: ... error: gate bug (simulated)
[   2.24s] TOOL_RESULT is_error= False (Bash completed with no output)
... calls {'hook': 1, 'hook_returned': 0, 'can_use_tool': 0} hello.txt exists: True
```
With `on_failure="block"`, the result was `PreToolUse:Bash hook error: [callback]: failed; blocking because onFailure is "block"`.

**Answers.**
- A hook can await a simulated click and then return allow or deny.
- The SDK tolerated a 70 s wait.
- A per-matcher timeout exists (`HookMatcher.timeout`) and is enforced. On expiry the callback is cancelled (`CancelledError`) and the tool is **not** executed.
- The documented default timeout of 60 s (SDK `types.py` comment) did **not** fire at 70 s. The effective default is **unverified**, so always set it explicitly.
- I didn't test waits longer than 70 s; anything in the hours range is **unverified**.

## 3. Hook "ask" and `can_use_tool`

Yes. When the hook returns `permissionDecision: "ask"`, `can_use_tool` is invoked, **even when an allow rule matches**. Its decision is final: it denied here, and the file wasn't created.
```
[   1.49s] PRE_TOOL_USE hook: Bash {"command": "touch hello.txt", ...}
[   1.51s] CAN_USE_TOOL called: Bash {"command": "touch hello.txt", ...}
[   1.51s] TOOL_RESULT is_error= True denied by can_use_tool (test)
[   3.88s] MODE ask allow source flag calls {'hook': 1, 'can_use_tool': 1} hello.txt exists: False
```
(Same result with `allowed_tools`: `logs/q1_ask_allowed_tools.log`.) So hook "ask" → `can_use_tool` is a valid path, and the hook doesn't have to do the asking itself.

## 4. AskUserQuestion

**Script:** `spikes/f02-gate/q45_user_input_tools.py ask` · **Log:** `logs/q4_ask.log`

The tool arrives at the PreToolUse hook (`PRE_TOOL_USE hook saw: AskUserQuestion`) and then at `can_use_tool`. Input schema as received:
```json
{"questions": [{"question": "Which colour should the button be?",
                "header": "Button colour",
                "options": [{"label": "Red", "description": "Set the button colour to red"},
                            {"label": "Green", "description": "..."},
                            {"label": "Blue", "description": "..."}],
                "multiSelect": false}]}
```
The test answered with `PermissionResultAllow(updated_input={**input, "answers": {"Which colour should the button be?": "Green"}})`. Claude received the answer:
```
[   1.79s] TOOL_RESULT is_error= None Your questions have been answered: "Which colour should the button be?"="Green". ...
[   2.47s] ASSISTANT: You chose Green.
```
**Not tested:** `multiSelect: true` answer formatting, a free-text "Other" answer, and multiple questions in one call (all **unverified**). The answers dict is keyed by question text.

## 5. ExitPlanMode

**Script:** `spikes/f02-gate/q45_user_input_tools.py plan allow|deny` · **Logs:** `logs/q5_plan_allow.log`, `logs/q5_plan_deny.log`

Yes, `ExitPlanMode` arrives at **both** the PreToolUse hook (`permission_mode= plan`) and `can_use_tool`. The input that `can_use_tool` received:
```json
{"plan": "# Plan: create notes.txt containing \"hi\"\n\n## Context\n...\n## Steps\n1. Write the text `hi` to `notes.txt` ...\n## Verification\n- Run `cat notes.txt` ...",
 "planFilePath": "~/.claude/plans/plan-how-to-create-iridescent-yeti.md"}
```
In the deny run, the model's `ToolUseBlock` input was `{}`, but `can_use_tool` still got the full `plan`. The CLI fills it in from the plan file. Render the card from the `can_use_tool` input, not from the stream.

- **allow** → the tool result is `User has approved your plan. You can now start coding. ...` plus the approved plan.
- **deny** with a message → the tool result is `is_error=True Request changes: name the file greeting.txt instead.`, and Claude read the feedback back. This is the "Request changes" path.

**Side effect:** before calling ExitPlanMode, Claude wrote the plan with `Write` to `~/.claude/plans/plan-how-to-create-*.md`. The hook saw that Write, but `can_use_tool` was **not** called (plan mode auto-allows its own plan file). Two files from this test remain there:
- `~/.claude/plans/plan-how-to-create-iridescent-yeti.md`
- `~/.claude/plans/plan-how-to-create-robust-eich.md`

I left them in place; delete them if you don't want them. A hook that denies all Write outside the worktree would break plan mode. The hook policy needs an explicit rule for `~/.claude/plans/`.

## 6. Failing fast on interactive commands

**Script:** `spikes/f02-gate/q6_interactive.py [probe]` · **Logs:** `logs/q6_interactive.log`, `logs/q6_pty_typescript.txt`. Times are measured from the PreToolUse hook to PostToolUse/PostToolUseFailure.

| Command | Result | Time |
|---|---|---|
| TTY probe | `stdin_tty=1` (not a tty), `stdout_tty=1`, `tty` → `not a tty`, `/dev/fd/0` is char device `0x3000002` (= `/dev/null`), `sys.stdin.read()` → `''`, `/dev/tty` → `device not configured` | 1.40 s |
| `python3 -c "input('pw: ')"` | exit 1, `EOFError: EOF when reading a line` | **0.07 s** |
| `python3 -c "import getpass; getpass.getpass('pw: ')"` (reads `/dev/tty`) | exit 1, `termios.error: (19, 'Operation not supported by device')`, then EOF | **0.11 s** |
| `ssh -o BatchMode=no git@example.invalid` | exit 255, `Pseudo-terminal will not be allocated because stdin is not a terminal.` / `Could not resolve hostname example.invalid` | **0.28 s** |

**The core under a pty.** I re-ran the probe under `script -q` (which gives the Python core a controlling tty). `script -q /dev/null python3 -c ...` printed `core isatty True True` and `core /dev/tty openable`. The Bash tool's child **still** had no `/dev/tty` (`dev_tty=unavailable`, stdin `/dev/null`). Claude Code detaches the Bash process from any controlling terminal, so the result doesn't depend on how the app is launched.

**Answer:** stdin is `/dev/null` (immediate EOF), and there is no TTY and no `/dev/tty`. Prompting commands fail in well under 1 s; none hung.

**Caveats:**
- ssh failed at DNS (`.invalid` never resolves; no host was contacted), so its **password-prompt path is unverified**. It would need `/dev/tty` or `SSH_ASKPASS`.
- A GUI askpass (`SSH_ASKPASS`, git credential helpers, macOS Keychain dialogs) could still pop up a window. **Unverified.**

## 7. Fork and two writers

**Scripts:** `spikes/f02-gate/q7_fork_two_writers.py`, plus `spikes/f02-gate/q7_dump_chain.py <sid>` (read-only parent-chain dump) · **Logs:** `logs/q7_fork.log`, `logs/q7_chain.log`. Transcripts under `~/.claude/projects/` were only read (hashed and parsed).

**Fork:**
```
ORIGINAL f5f65b01-…  {'lines': 28, 'sha': '93e027c6b16b0198'}
ASSISTANT (fork): PINEAPPLE. I'll also remember MANGO.
FORK 9079961b-…  differs from original: True  fork transcript: {'lines': 33, ...}
original unchanged after fork: True {'lines': 28, 'sha': '93e027c6b16b0198'}
```
`resume=<id>, fork_session=True` → new session_id, the full context carried over, and the original file byte-identical.

**Two writers:** an SDK client (`resume=A`, "say hello") and `claude -p --resume A "say hi"` were started together on the original session. Both reported `session_id = A`, both succeeded, and both appended to the same file (28 → 52 lines). All 52 lines parse as JSON, so there was **no byte-level corruption**. But the conversation **forked inside the file**:
```
ae4abc78 <- de4b3cdb user      13:29:12.798 sdk-py          'say hello'
b193d535 <- ad41b852 assistant 13:29:12.937 claude-desktop  'No response requested.'   <- CLI patched SDK's in-flight turn
42ff9e1e <- b193d535 user      13:29:13.561 claude-desktop  'say hi'
ebd313fb <- ad41b852 assistant 13:29:13.729 sdk-py          'Hello!'                   <- same parent as CLI's entry
35630bd4 <- 7cab4300 assistant 13:29:14.671 claude-desktop  'Hi!'
```
- Parent `ad41b852` has two children (`branches={'ad41b852': 2}`). The CLI loaded the file mid-turn, saw the SDK's unanswered "say hello", and wrote a synthetic `No response requested.` there.
- The SDK's real reply `Hello!` sits on a side branch. The latest leaf (`Hi!`) chain doesn't include it, so a later `--resume` that follows the latest leaf would lose the SDK's turn. I didn't run a third resume to confirm this, so it is **unverified**.
- `ad41b852` itself is a non-text entry (likely an attachment or system record). Its exact type is **unverified**.
- The CLI subprocess recorded `entrypoint=claude-desktop`, inherited from the host environment.

**Answer:** two writers don't corrupt the JSONL, but they interleave and split the conversation tree. The §5.10 rule "never two writers; take-back forks" is necessary, and `fork_session` works for it.

---

## Implications for PLAN.md §7 (gate design that works)

1. **Register one catch-all gate:** `HookMatcher(matcher=None, hooks=[gate], timeout=<explicit>, on_failure="block")` on `PreToolUse`. `on_failure="block"` is **mandatory**. Without it, any exception in the gate (a policy bug, a lost app socket) lets settings allow rules run the tool (§2, fail-open run).
2. **Hook decides:**
   - **allow:** the allowlist (§4, built-ins, job exact-command list). Allow from the hook bypasses `can_use_tool`, as shown in Q2.
   - **deny:** denied paths and tools. Deny wins over every allow rule (Q1).
   - **For "ask", either design works.**
     - **(A) The hook asks itself:** await the app, then return allow or deny. Tested up to 70 s.
     - **(B) The hook returns `"ask"`:** `can_use_tool` is guaranteed to be called, even past allow rules (Q3), and does the card.
     - **Recommendation: (B) for interactive approvals.** `can_use_tool` has no separate timeout (none was observed), and approvals go through one callback path that sees `AskUserQuestion` and `ExitPlanMode` anyway. Keep (A) only for job approvals if you want them queued in the hook. The §9 open item "does hook ask reach `can_use_tool`" is now **resolved: yes**.
3. **Timeouts:** set `HookMatcher.timeout` explicitly. Expiry = tool not run, which matches "timeout counts as deny". The 60 s default wasn't enforced at 70 s, so don't rely on it. For the **4 h job auto-deny**, either set a timeout of 14,400 s or more (untested beyond 70 s, **unverified**), or have the hook return "ask" and hold the wait in `can_use_tool`. The long-wait behaviour of `can_use_tool` is also **unverified**.
4. **`can_use_tool` handles:**
   - `AskUserQuestion`: answer with `updated_input={**input, "answers": {question_text: label}}` (verified).
   - `ExitPlanMode`: render from `input["plan"]`; allow = approve, deny with message = "Request changes" (verified).
   - Hook-escalated "ask".
   - The final catch-all.
5. **Plan-mode carve-out:** allow `Write` to `~/.claude/plans/*.md` only when `permission_mode == "plan"` (the hook input carries `permission_mode`). Otherwise either deny it (which breaks plan mode, consistent with "persona never uses plan mode") or accept it.
6. **Workspace trust:** project allow rules don't apply in an untrusted repo, so job worktrees may behave differently from the main checkout. That doesn't matter once the hook is the gate, but don't rely on repo allow rules for job convenience.
7. **Interactive commands:** keep "Bash has no terminal and stdin is closed, so it fails fast" in §5.9. Verified: EOF on stdin, no `/dev/tty`, under 0.3 s, even if the core has a tty. GUI askpass and Keychain prompts remain **unverified**.
8. **Handoff:** keep §5.10 as written. Two writers produce a branched transcript (Q7). `fork_session=True` gives a clean new id and leaves the original untouched.
9. **Builtin plugins:** five `cc-plugin-*@builtin` plugins load even with `plugins=[]` and `setting_sources=["project"]`. They are part of Claude Code; note them in the footprint and egress review. What they do at runtime is **unverified**.

## How to re-run

```bash
cd feasibility/spikes/f02-gate
uv sync                                   # claude-agent-sdk 0.2.182
# Q1 / Q3
for s in project flag allowed_tools; do for m in nohook deny ask; do uv run q1_hook_vs_allow.py $m $s; done; done
# Q2
uv run q2_hook_wait.py 5 allow; uv run q2_hook_wait.py 5 deny
uv run q2_hook_wait.py 70 allow; uv run q2_hook_wait.py 70 allow 600
uv run q2_hook_wait.py 20 allow 5 continue allowed_tools
uv run q2_hook_wait.py 0 raise none continue allowed_tools   # fail-open demo
uv run q2_hook_wait.py 0 raise none block allowed_tools
# Q4 / Q5 (Q5 writes a plan file to ~/.claude/plans/)
uv run q45_user_input_tools.py ask
uv run q45_user_input_tools.py plan allow; uv run q45_user_input_tools.py plan deny
# Q6 (and under a pty)
uv run q6_interactive.py
script -q /tmp/q6.txt uv run q6_interactive.py probe < /dev/null
# Q7 (reads ~/.claude/projects/ only)
uv run q7_fork_two_writers.py
uv run q7_dump_chain.py <original-session-id>
```
Scripts print timestamped `PRE_TOOL_USE`, `CAN_USE_TOOL`, `TOOL_USE`, `TOOL_RESULT` and `RESULT` lines. Each Q1/Q2 run ends with a summary line that has the call counts and whether `hello.txt` exists.
