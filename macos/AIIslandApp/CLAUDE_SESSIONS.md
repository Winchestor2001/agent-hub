# Claude accounts and logical sessions

AI Island manages two independently signed-in Claude subscription accounts and
continues a local project conversation through manual transcript forks. Existing
Codex usage and configuration browsing remain available.

## Start a session

1. Build with `sh scripts/build-ai-island-app.sh` and open `dist/AI Island.app`.
2. Open **Settings → Accounts → Open Claude Accounts & Sessions** or use the
   menu bar **Claude Accounts & Sessions** item.
3. Add **Claude A** and **Claude B**. Select each account and click **Sign in**.
   Complete Claude's login in Terminal with a different subscription identity.
4. Click **Check auth**. Both accounts must use Claude subscription authentication.
5. Choose an existing local git project, enter a logical session name, select
   Claude A, and click **Create & start**.
6. Work in the Claude Code Terminal window. AI Island shows account usage after
   Claude supplies its first statusline rate-limit payload.
7. Select Claude B and click **Readiness**. Authenticate or approve any MCP
   servers in that account before switching. The isolated login Terminal can
   also run account-specific MCP commands after you export the config directory
   shown in diagnostics.
8. Click **Continue with selected account**, or use the Island continuation
   button. Confirm the manual switch. Repeat with Claude A to return.

The readiness check runs again immediately before stopping the source and before
starting the target. It checks auth, duplicate account identity, project settings,
MCP connectivity/approval, readable context, and git state. An unknown MCP result
blocks continuation instead of being reported as ready. Project-level `CLAUDE.md`,
`.claude/`, skills, agents, MCP declarations, and the working tree stay in the
existing project. Global account settings and global MCP authorization stay
private to their account.

## Storage and credentials

The manager stores data in `~/.claude-manager/`:

| Directory | Contents |
| --- | --- |
| `accounts/<uuid>/claude-config/` | Each account's Claude-owned configuration and authentication storage |
| `sessions/<logical-id>/<physical-id>/` | Unique transcript snapshots for forks |
| `state/sessions.sqlite` | Accounts, projects, logical/physical sessions, handoffs, usage, readiness, locks, events |
| `state/` | Generated Terminal launchers and launch-specific hooks settings |
| `locks/` | OS locks for runners, login, and handoff operations |

Directories are private to the current macOS user. The app never reads or copies
OAuth credentials or Keychain values. Claude Code handles its own login and
Keychain storage. Each launch sets both `CLAUDE_CONFIG_DIR` and
`CLAUDE_SECURESTORAGE_CONFIG_DIR` to the selected account directory, and discards
inherited API keys, OAuth overrides, alternate providers, and injected settings.
Account identity is stored as a SHA-256 digest to detect duplicate sign-ins;
no access token is stored in SQLite. Readiness output contains names and fixed
statuses, not MCP commands, URLs, headers, or raw CLI output. Transcript snapshots
contain conversation content, including tool results, and receive private file
permissions. Treat them as private project data.

## Handoff and recovery

A handoff checks the target, records the operation, sends SIGTERM to the verified
source process group, waits for the runner to reap Claude and confirm that its
descendants exited, and verifies that the transcript is stable. It records
`git branch --show-current`, `git status --porcelain`, and `git rev-parse HEAD`.
It never commits, stashes, resets, or switches branches. A branch/HEAD change
during stopping blocks the handoff for review.

The adapter takes the transcript path and session ID from official hooks. It
validates the transcript and takes a unique snapshot. It then launches the target
with `--resume <snapshot.jsonl> --fork-session --session-id <new-uuid>`.
The target's SessionStart hook confirms the new physical session before updating
the logical session's active pointer. A failed target restores the source pointer
and retains both the original transcript and snapshot. The source's private
config directory is never copied to the target.

SQLite reservations prevent two manager sessions from writing to the same
project, and OS locks prevent duplicate runners. **Cancel pending launch** releases
a reservation only before a runner claims it. **Recover stopped session** is for
a crashed runner: it requires both the runner and Claude's entire process group
to be absent. A live or unverified PID retains its lock. The manager does not use
SIGKILL to force transcript flushing.

Work through the manager-launched Terminal. Processes launched independently of
the manager do not participate in its locks. Do not manually resume a managed
physical session in another terminal. Inside a managed process, `/clear` or
`/resume` can change the session ID; the manager detects this and blocks handoff
from an outdated transcript for review.

## Compatibility and usage

Research baseline: Claude Code **2.1.284** on macOS. Its CLI supports JSONL paths
for `--resume`, explicit UUIDs for forked sessions, config-scoped Keychain names,
and the hooks/statusline fields used here. The adapter requires version 2.1.251
or later and the necessary CLI flags; unknown behavior fails safely at launch.
Filesystem details are contained in `LocalClaudeCodeAdapter`. The UI never
searches for the newest JSONL file.

Hooks: SessionStart, Stop, SessionEnd, PostToolUse, PostCompact, and StopFailure.
Only session identity, transcript path, git state, and fixed event labels are
persisted; tool payloads and assistant text from hooks are discarded. Usage comes
from the official statusline `rate_limits.five_hour` and `seven_day` payloads.
The higher utilization drives the account indicator. Missing usage is **unknown**,
and snapshots older than five minutes are **last known**. Idle accounts are not
queried through a private OAuth endpoint. Reset times are shown when supplied by
Claude. No background switching or rotation exists.

References: [CLI reference](https://code.claude.com/docs/en/cli-reference),
[hooks](https://code.claude.com/docs/en/hooks),
[statusline](https://code.claude.com/docs/en/statusline), and
[settings](https://code.claude.com/docs/en/settings).

## Verification

Run the isolated process/storage tests:

```sh
swift test --package-path macos/AIIslandApp --disable-build-manifest-caching
```

These use synthetic auth metadata and a fixture CLI, exercise real subprocesses,
SQLite, hooks, locks, dirty git state, failure rollback, and A → B → A forks.
They do not authenticate real Claude accounts or validate Anthropic model recall.

Run the opt-in native UI check with an absolute report path:

```sh
"dist/AI Island.app/Contents/MacOS/AIIsland" \
  --accounts-regression-report /tmp/claude-accounts-ui.txt
```

It uses fixture accounts in a separate directory beside the report, renders
account/session/history/diagnostic views, checks warning/limit Island states,
and saves a PNG. Existing native checks remain available through
`--usage-regression-report` and `--settings-regression-report`.

For real acceptance, sign in to two different subscriptions, ask A to make a
small project change and retain a distinctive context detail, switch to B, and
ask B to explain that detail and continue the change. Switch back to A and repeat.
Verify different config paths and session IDs in diagnostics, the same logical
session name, dirty files still present, and both completed handoffs in history.
Until this is performed, real cross-account continuation is **unverified**.
