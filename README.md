# CodexDock

CodexDock is an open-source developer control layer for private machine
registration, SSH connection, and long-running Codex/tmux sessions.

The public CLI uses CodexDock concepts:

```bash
codexdock init --device homepc --host 100.64.0.2 --ssh-user manoj
codexdock init --network personal --machine homepc --host 100.64.0.2 --ssh-user manoj
codexdock devices
codexdock connect homepc
codexdock sessions
codexdock sessions homepc
codexdock start homepc
codexdock attach homepc
codexdock send homepc continue
codexdock send homepc continue with the current task
codexdock logs homepc
codexdock stop homepc --yes
codexdock doctor homepc
codexdock doctor --all
codexdock devices --all
codexdock machines
codexdock create personal --role controller --control-url https://control.example --provision
codexdock invite --ttl 24h
codexdock invite personal --ttl 24h
codexdock register homepc --host 100.64.0.2 --ssh-user manoj
codexdock register homepc personal --host 100.64.0.2 --ssh-user manoj
codexdock register homepc personal --host 100.64.0.2 --ssh-user manoj --force
codexdock register macbook personal --control-url https://control.example --ssh-user manoj
codexdock register macbook personal --control-url https://control.example --join --enrollment-key <key>
codexdock adopt homepc --ssh-user manoj
codexdock adopt homepc --ssh-user manoj --force
codexdock machines personal
codexdock connect homepc personal
codexdock doctor homepc personal
codexdock doctor --repair-plan --target-os linux --role controller
codexdock doctor --repair --yes --target-os linux --role client
codexdock doctor --repair-plan --target-os linux --role codex-host --workspace ~/code
codexdock doctor --repair-plan --target-os linux --role codex-host --ssh-authorized-key-file ~/.ssh/id_ed25519.pub
codexdock doctor homepc --repair-plan --target-os linux --role codex-host
codexdock doctor homepc --repair --yes --target-os linux --role codex-host
codexdock codex sessions homepc personal
codexdock codex start homepc personal
codexdock codex attach homepc personal
codexdock codex send homepc personal continue
codexdock codex logs homepc personal
codexdock codex stop homepc personal --yes
```

Headscale and Tailscale are treated as managed OSS internals. CodexDock does
not rebuild private networking, WireGuard transport, NAT traversal, or peer
identity.
Release archives include `THIRD_PARTY_NOTICES.md` with upstream BSD 3-Clause
notices for these managed implementation components.

`create` stores a CodexDock network profile. `create --provision` also creates
the matching network identity on a controller through CodexDock-managed
internals. Provisioning first checks whether the controller user already
exists, so rerunning setup for the same network is safe. When a control URL is
provided, CodexDock prints the matching `invite` command so the controller can
issue an enrollment key and generate the usable `register --join` command for
another machine. Existing network profiles
are not overwritten unless `--force` is provided. Network roles are limited to
`client` and `controller`. Supplied control URLs are trimmed before they are
stored, and blank control URL values are rejected. Network aliases created by
`init`, `create`, or clean-machine `register --join` cannot be blank; quoted
surrounding whitespace is trimmed before storing, lookup, and generated
follow-up command guidance.

`init` bootstraps first-time local configuration by creating a network profile
and registering the first machine in one non-interactive command. `--device` is
the friendly alias for `--machine`; when `--network` is omitted, CodexDock uses
`personal`. It refuses to replace an existing machine unless `--force` is
provided.

`invite` issues an enrollment key from a controller for a CodexDock network and
prints the matching `register --join` command for another machine. When the
network argument is omitted, it uses the current network. CodexDock keeps
Headscale internal by resolving the controller user ID for the network before
creating the preauth key. `--ttl` values are trimmed before issuing the key,
and an explicitly blank `--ttl` is rejected.

After `init`, `devices`, `register <machine>`, `connect`, `sessions`, `start`,
`attach`, `send`, `logs`, `stop`, `machines`, and `doctor <machine>` use the current network stored in config.
If the config contains exactly one network, CodexDock can infer it even when
`current_network` is absent. The explicit `register <machine> <network>`,
`machines <network>`, `connect <machine>
<network>`, `doctor <machine> <network>`, and `codex ... <machine> <network>`
forms remain available when you want to name the network, and are required when
multiple networks exist without a current network. Operation commands reject
blank machine and network arguments before opening SSH or running remote tmux
commands.

`register` stores a user-chosen machine alias. When the private network client
is available, CodexDock records the current machine's private-network IP.
`machines` shows the registered machines with live private-network status when
available: `online`, `offline`, or `unknown`. Live status can match either the
registered alias, DNS name, or stored private-network IP. Commands that create
or refresh machine profiles reject non-positive `--ssh-port` values before
writing config or contacting managed network internals. They also validate
`--session` as a tmux session name, limited to letters, numbers, underscores,
and hyphens, and require non-empty `--agent` and `--workspace` values.
Surrounding whitespace on machine profile fields such as host, SSH user, role,
session, agent, and workspace is trimmed before validation and storage. Machine
aliases created by `init`, `register`, and `adopt` cannot be blank; quoted
surrounding whitespace is trimmed before storing, lookup, and generated
follow-up command guidance.

`devices --all` also shows visible private-network peers that are not yet
registered, with an `adopt` hint for bringing them into the current network
profile. Peers already represented by a registered machine alias, stored host,
DNS name, or private-network IP are not shown as adoptable duplicates.

`register --join` asks the managed private-network client to join the network
using the network control URL. On a clean second machine, `register --join
--control-url <url>` creates the local network profile before registering the
machine. Join requires a nonblank control URL and passes the trimmed URL to the
managed private-network client. `--enrollment-key` supports non-interactive
joins without printing the key in normal output. When supplied, the enrollment
key cannot be blank. `register --force` replaces an existing local machine
profile after any requested join succeeds, which lets you safely refresh stale
host, SSH, workspace, session, or agent settings without deleting the network
profile.

`adopt` adds a visible private-network peer to the current network profile so a
second machine can start using `connect`, `doctor`, and Codex session commands
for a peer that has already joined the network. `adopt --force` refreshes an
existing local machine profile from live private-network status.

When `connect` runs, CodexDock resolves a stored alias through private-network
status and verifies basic SSH reachability before opening an interactive SSH
session. Offline, unresolved, or unreachable aliases fail before interactive
SSH starts and point back to `codexdock machines <network>` for the current
status view.

`doctor` reports local config readiness, private-network client availability,
system `ssh` availability, and the managed OSS components CodexDock depends on
internally. `doctor <machine> <network>` verifies SSH connectivity plus remote
`tmux`, agent command, and workspace readiness for a registered target. Agent
binary checks quote unsafe command names before sending them over SSH. Remote
failures include copyable SSH checks or setup commands where CodexDock can
infer one. `doctor --all` runs those remote readiness checks for every
registered machine in the current network and reports all machine failures
before returning a non-zero summary.

`doctor --repair-plan` prints conservative CodexDock-managed setup steps for a
machine role, including concrete Linux controller package installation steps.
It does not execute privileged installer commands. When provided for repair
planning or execution, `--workspace` cannot be blank.

`doctor --repair --yes` runs the generated repair steps. Use
`doctor --repair-plan` first to inspect the exact commands.

For a Windows WSL machine that will host Codex/tmux sessions, use the
`codex-host` repair role from inside the Linux environment. It keeps the
managed private-network client internal, installs and starts OpenSSH, installs
`tmux`, creates the session workspace, and reminds the user to install and
authenticate Codex for that Linux user. The OpenSSH step uses `systemctl` when
available and falls back to `service ssh start`, which fits common WSL setups.
Pass `--ssh-authorized-key-file ~/.ssh/id_ed25519.pub` when you want the repair
plan to install a Mac public key into the WSL user's
`~/.ssh/authorized_keys` idempotently. Explicit SSH authorized key values and
key file paths cannot be blank. Key files use the first line as the public key;
that first line cannot be blank.

After a machine is registered and reachable over SSH, the same repair plan can
be rendered or executed remotely through `doctor <machine>`. Without
`--workspace`, remote repair uses the workspace stored in the machine profile.
Execution still requires `--yes`.

`sessions` lists remote tmux sessions across all registered machines in the
current network. `sessions <machine>` limits the view to one registered
machine. Network-wide `sessions` reports per-machine failures while still
listing sessions from reachable machines, then returns a non-zero summary if
any machine failed. `start`, `send`, and `stop` print confirmations after the
remote tmux command succeeds. Before starting a session, `start` checks SSH connectivity,
remote `tmux`, the configured agent command, and the workspace so setup
problems fail before tmux is launched; if the session is already running, it
reports that state instead of claiming a new launch. Workspaces written as
`~/...` are expanded against the remote SSH user's `$HOME` before tmux starts
Codex. `attach` checks that the configured tmux session exists before opening
interactive SSH and points back to `start` when needed. `send` rejects empty
prompts, checks that the session exists before injecting text, and warns on
very long prompts. `logs` checks that the session exists before capturing
recent output, and `--lines` must be positive. `stop` checks that the session
exists before killing it, warns before killing a running session, and requires
either `--yes` or `--force`.

## Development

```bash
GOCACHE=/tmp/codexdock-gocache GOMODCACHE=/tmp/codexdock-gomodcache go test ./...
```

Run a local CLI smoke test with an isolated temporary config:

```bash
GOCACHE=/tmp/codexdock-gocache GOMODCACHE=/tmp/codexdock-gomodcache ./scripts/smoke-test.sh
```

Run the full local simulated E2E workflow with fake managed internals:

```bash
GOCACHE=/tmp/codexdock-gocache GOMODCACHE=/tmp/codexdock-gomodcache ./scripts/e2e-local-sim.sh
```

Preview the remote Mac-to-WSL validation flow without opening SSH:

```bash
CODEXDOCK_HOST=100.64.0.2 CODEXDOCK_USER=manoj ./scripts/e2e-remote.sh --print-plan
CODEXDOCK_ADOPT=1 CODEXDOCK_USER=manoj ./scripts/e2e-remote.sh --print-plan
```

Run a local preflight before the remote validation:

```bash
CODEXDOCK_HOST=100.64.0.2 CODEXDOCK_USER=manoj ./scripts/e2e-remote.sh --preflight
CODEXDOCK_ADOPT=1 CODEXDOCK_USER=manoj ./scripts/e2e-remote.sh --preflight
```

Preflight does not build or start a remote session. It checks local inputs and
tool availability, including `go` for the validation build unless
`CODEXDOCK_BIN` points to an executable local CodexDock binary. It writes
`preflight.txt` plus `result.txt` to the report directory, and returns exit
code `2` when required inputs or local tools are missing, or when configured
numeric, flag, control URL, binary path, and target architecture values are
invalid.
Remote E2E environment values are trimmed before validation, report context
writing, and generated runbook scripts, so pasted values with surrounding
spaces produce the same commands as clean values. Explicit whitespace-only
values still fail validation anywhere the value is required or supplied.
`CODEXDOCK_ADOPT`, `CODEXDOCK_PREPARE`, and `CODEXDOCK_REQUIRE_SCP` must be
`0` or `1`; target host/user values and `CODEXDOCK_CONTROL_URL` cannot be
blank when set; workspace, agent, and prompt values cannot be blank; and
`CODEXDOCK_SESSION` must contain only letters, numbers, underscores, or
hyphens. SSH authorized key values cannot be blank when set, and key files
must have a nonblank first line. When more than one input is invalid,
`preflight.txt` reports all of them on the `invalid=` line separated by
semicolons.

Write a physical-run handoff bundle before moving between machines:

```bash
CODEXDOCK_REPORT_DIR=.dev-logs/e2e-remote/physical-run \
  CODEXDOCK_HOST=100.64.0.2 \
  CODEXDOCK_USER=manoj \
  CODEXDOCK_PREPARE=1 \
  CODEXDOCK_TARGET_ARCH=amd64 \
  CODEXDOCK_SSH_AUTHORIZED_KEY_FILE=~/.ssh/id_ed25519.pub \
  ./scripts/e2e-remote.sh --write-runbook
```

The runbook mode does not run SSH or contact TrentPlatform. It writes
`wsl-install-codexdock.sh`, `mac-stage-wsl-codexdock.sh`,
`mac-preflight.sh`, `mac-run.sh`, `wsl-prepare.sh`, `finalize-trent.sh`, and
`runbook.txt` into the report directory. Use the WSL-local install script first
when SSH into WSL is not ready yet; it builds CodexDock inside WSL into
`$HOME/.local/bin/codexdock` so `wsl-prepare.sh` can start SSH, install tmux,
create the workspace, and install managed internals before Mac-side `scp` is
possible. Once SSH is reachable, use the Mac staging script to install the
current Linux CodexDock binary from the Mac, run the Mac preflight, execute the
full remote validation, and intentionally finalize the successful report in
TrentPlatform. It refuses to write runnable scripts until the required target
values are present:
`CODEXDOCK_HOST` and `CODEXDOCK_USER` for direct mode, or `CODEXDOCK_USER` for
`CODEXDOCK_ADOPT=1`; `CODEXDOCK_SSH_PORT` and `CODEXDOCK_LOG_LINES` must be
positive integers, flag values must be `0` or `1`, and target host/user values
plus `CODEXDOCK_CONTROL_URL`, workspace, agent, and prompt cannot be blank
when set. `CODEXDOCK_SESSION` must contain only letters, numbers, underscores,
or hyphens. SSH authorized key values cannot be blank when set, and key files
must have a nonblank first line before runbook files are written. The generated Mac
scripts also pin Go build caches under `/tmp` so an inherited shell cache
setting cannot break the validation build. If `CODEXDOCK_BIN` is set while
writing the runbook, the generated Mac preflight and run scripts preserve that
binary path.
The generated `finalize-trent.sh` sources
`.dev-logs/trent-codexdock.env` by default when the TrentPlatform bootstrap
helper has written reusable project and roadmap IDs there; set
`CODEXDOCK_TRENT_ENV_FILE` to point it at a different sourceable env file.
Because the runbook includes a Mac-to-WSL staging script, its generated
`mac-preflight.sh` also requires `scp` and records `local_scp` in
`preflight.txt`. All preflight reports record `local_go`; when
`CODEXDOCK_BIN` is provided and executable, the full validation records that
binary's `codexdock version` output instead of building from source, so Go is
not required for the Mac validation run.
`CODEXDOCK_TARGET_ARCH` controls the Linux binary architecture used by
`mac-stage-wsl-codexdock.sh`; it defaults to `amd64` and can be set to `arm64`
for ARM64 Windows/WSL hosts. Generated Mac preflight and run scripts preserve
the selected target architecture in their environment so reports match the
staged binary. Runbook generation rejects other architecture values before
writing scripts.

Run the remote validation when the target has SSH, tmux, the configured agent,
and the configured workspace:

```bash
CODEXDOCK_HOST=100.64.0.2 CODEXDOCK_USER=manoj ./scripts/e2e-remote.sh
CODEXDOCK_CONTROL_URL=https://control.example CODEXDOCK_HOST=100.64.0.2 CODEXDOCK_USER=manoj ./scripts/e2e-remote.sh
CODEXDOCK_ADOPT=1 CODEXDOCK_USER=manoj ./scripts/e2e-remote.sh
CODEXDOCK_PREPARE=1 CODEXDOCK_HOST=100.64.0.2 CODEXDOCK_USER=manoj ./scripts/e2e-remote.sh
CODEXDOCK_PREPARE=1 CODEXDOCK_SSH_AUTHORIZED_KEY_FILE=~/.ssh/id_ed25519.pub CODEXDOCK_HOST=100.64.0.2 CODEXDOCK_USER=manoj ./scripts/e2e-remote.sh
CODEXDOCK_BIN="$HOME/.local/bin/codexdock" CODEXDOCK_HOST=100.64.0.2 CODEXDOCK_USER=manoj ./scripts/e2e-remote.sh
```

Remote validation uses a dedicated tmux session named `codexdock-e2e` by
default so it can safely exercise confirmed stop without killing your normal
`codex` session. Set `CODEXDOCK_SESSION=codex` only when you intentionally want
the validation to use the standard session name.

Remote validation writes a command report by default under
`.dev-logs/e2e-remote/<timestamp>`. Set `CODEXDOCK_REPORT_DIR=/path/to/report`
to choose the destination. It rejects unsupported `CODEXDOCK_TARGET_ARCH`
values before writing report files. It also rejects a provided `CODEXDOCK_BIN`
unless it points to an executable file. The report contains the command,
stdout, and stderr for build or binary-version proof, init/adopt, optional
prepare, targeted doctor, network-wide doctor, start, targeted sessions,
network-wide sessions, send, logs, confirmed stop, and a post-stop targeted
session check.

If the remote validation fails after the session has started but before the
normal stop step runs, the harness attempts a best-effort cleanup stop and
writes `cleanup_stop.cmd`, `cleanup_stop.out`, and `cleanup_stop.err` into the
same report directory.

Every remote validation report also includes `result.txt` with `status`,
`exit_code`, `network`, `machine`, `session`, `session_started`,
`session_stopped`, `cleanup_attempted`, and `cleanup_exit_code` fields.
Full remote reports include `context.txt` with the selected network, machine,
SSH target, optional control URL, workspace, session, agent, prompt,
SSH key-source flags, `require_scp`, and `target_arch`. Preflight reports also
include a `preflight` field.

Provision a fresh TrentPlatform org through the A2A signup flow, create a
scoped CodexDock agent PAT, and bootstrap the CodexDock metadata used by the
publish and closure helpers:

```bash
CODEXDOCK_TRENT_ORG_NAME=CodexDock123 \
  CODEXDOCK_TRENT_ORG_LABEL=CodexDock \
  CODEXDOCK_TRENT_ADMIN_EMAIL=admin@example.com \
  CODEXDOCK_TRENT_ADMIN_PASSWORD='<strong-password>' \
  CODEXDOCK_TRENT_TOKEN_FILE=/tmp/trentplatform-codexdock-admin.json \
  CODEXDOCK_TRENT_ENV_FILE=.dev-logs/trent-codexdock.env \
  ./scripts/trent-provision-org.sh
. .dev-logs/trent-codexdock.env
```

The provision helper calls the public TrentPlatform signup endpoint, creates a
scoped PAT with metadata, data, and query scopes, writes the token JSON file
with mode `600`, and then runs `trent-bootstrap.sh` using that token. Use a
unique org name that starts with a letter and contains only letters and
numbers.

If you already have a scoped TrentPlatform PAT, skip org provisioning and
bootstrap the CodexDock metadata directly:

```bash
CODEXDOCK_TRENT_TOKEN_FILE=/tmp/trentplatform-codexdock-admin.json \
  CODEXDOCK_TRENT_ENV_FILE=.dev-logs/trent-codexdock.env \
  ./scripts/trent-bootstrap.sh
. .dev-logs/trent-codexdock.env
```

Bootstrap creates the `CodexDock` namespace, `Project`, `Artifact`, and
`RoadmapItem` objects, a CodexDock project record, and starter roadmap rows for
the implementation scope. It also seeds a `GitHub repository` artifact pointing
to `https://github.com/edisontrent17/codexdock`; set
`CODEXDOCK_TRENT_REPOSITORY_URL` before bootstrap if you need a different
repository URL. The script uses the TrentPlatform A2A-documented metadata and
data endpoints, and requires a bearer token with
`metadata:write` and `data:write` access. It prints reusable
`CODEXDOCK_TRENT_PROJECT`, `CODEXDOCK_TRENT_REPOSITORY_ARTIFACT`, and
`CODEXDOCK_TRENT_ROADMAP_IDS` assignments from the created TrentPlatform
records; export those values before recording or finalizing E2E reports.
Bootstrap fields that later receive records are
created with writable field types used by the current TrentPlatform
record-storage path, with explicit text lengths for report content and scope
summaries. Set `CODEXDOCK_TRENT_ENV_FILE` when you want those assignments
written to a sourceable file for later report publishing and roadmap closure.
The Trent record, close, and finalizer helpers source
`.dev-logs/trent-codexdock.env` by default when it exists, and auto-export the
assignments so values written by the bootstrap helper are visible to child
scripts. Explicit `CODEXDOCK_TRENT_PROJECT`,
`CODEXDOCK_TRENT_REPOSITORY_ARTIFACT`, and `CODEXDOCK_TRENT_ROADMAP_IDS`
environment values take precedence over values loaded from that file. Set
`CODEXDOCK_TRENT_ENV_FILE` to use a different sourceable env file.

Publish a validation report to TrentPlatform after a preflight or remote run:

```bash
CODEXDOCK_TRENT_TOKEN_FILE=/tmp/trentplatform-codexdock-admin.json \
  CODEXDOCK_TRENT_PROJECT=111764 \
  ./scripts/trent-record-e2e.sh .dev-logs/e2e-remote/<timestamp>
```

The helper reads `result.txt`, optional `context.txt`, optional
`preflight.txt`, and any command artifacts in the report directory, then
creates a `CodexDock.Artifact` record. Full-run artifacts include the first
line of each recorded `.cmd` file and byte counts for matching `.out` and
`.err` files, so TrentPlatform keeps a compact manifest of the local evidence
used by the closure gate. Manifest command lines keep sensitive flag names such
as `--ssh-authorized-key` and `--enrollment-key`, but redact their values
before publishing. Use
`CODEXDOCK_TRENT_TOKEN` instead of
`CODEXDOCK_TRENT_TOKEN_FILE` when providing the bearer token directly. The
default artifact type is `plan`; override it with
`CODEXDOCK_TRENT_ARTIFACT_TYPE` only if the target TrentPlatform metadata
allows that picklist value.

Validate a full remote run before closing roadmap items:

```bash
./scripts/validate-e2e-report.sh --full .dev-logs/e2e-remote/<timestamp>
```

Full validation requires a successful non-preflight `result.txt` plus the
expected command artifacts for build, init or adopt, doctor, start, sessions,
send, logs, stop, and post-stop session checks. Required `.cmd` artifacts must
be non-empty, contain the expected CodexDock step command tokens, and target
the reported machine for machine-scoped steps. Command artifacts that carry
selected context arguments must match those context values, such as
`init --network <network> --host <host> --ssh-user <ssh_user> --ssh-port <ssh_port>`,
`init --control-url <control_url>` or `create --control-url <control_url>` when
a control URL is reported, `create <network>`,
`adopt --ssh-user <ssh_user> --ssh-port <ssh_port>`,
`init/adopt --workspace <workspace> --session <session> --agent <agent>`,
`send <machine> <prompt>`, and `logs --lines <log_lines>`. It also requires
`context.txt` with the run configuration fields, including SSH target, optional
control URL, workspace, session, agent, prompt, SSH key-source flags,
`require_scp`, and `target_arch`; the context `network`, `machine`, and
`session` values must match `result.txt`, context `adopt` must match the direct
`init` or `adopt` report artifacts, and context `prepare` must match the
optional prepare artifacts. Result `network`, `machine`, and `session` values
cannot be blank. Context `network`, `machine`, `ssh_user`, `workspace`, `agent`,
and `prompt` values cannot be blank; direct `init` reports also require a
nonblank context `host`. Context `session` must contain only letters, numbers,
underscores, or hyphens. The context `ssh_port` and `log_lines` values must be
positive integers, `require_scp` must be `0` or `1`, SSH key-source flags must
be `yes` or `no`, and `target_arch` must be one of `amd64` or `arm64`.
When prepare ran with an SSH authorized key source, `prepare.cmd` must include
`--ssh-authorized-key`.
Closure-relevant `result.txt` and `context.txt` fields must appear exactly once;
duplicate keys are rejected. For successful full reports, `cleanup_attempted`
must be `yes` or `no`; when it is `no`, `cleanup_exit_code` must be
`not_applicable`.

After a successful full remote validation report, close the remaining
real-machine roadmap items in TrentPlatform:

```bash
CODEXDOCK_TRENT_TOKEN_FILE=/tmp/trentplatform-codexdock-admin.json \
  ./scripts/trent-close-roadmap.sh .dev-logs/e2e-remote/<timestamp>
```

This helper refuses failed reports and preflight-only reports. By default it
marks the managed internals, machine discovery, SSH connect, and Codex/tmux
roadmap records as `done`; override the item list with
`CODEXDOCK_TRENT_ROADMAP_IDS` if the project metadata changes.

To perform the guarded finalization sequence in one command, validate the full
report, publish the report artifact, and close the roadmap items:

```bash
CODEXDOCK_TRENT_TOKEN_FILE=/tmp/trentplatform-codexdock-admin.json \
  CODEXDOCK_TRENT_PROJECT=111764 \
  ./scripts/trent-finalize-e2e.sh .dev-logs/e2e-remote/<timestamp>
```

The finalizer refuses failed, preflight-only, incomplete, or content-mismatched
reports before it publishes anything to TrentPlatform. It only closes roadmap
items after the artifact publish succeeds.

Build the local binary:

```bash
VERSION=0.1.0 COMMIT=unknown BUILD_DATE=2026-06-28T00:00:00Z ./scripts/build.sh
./dist/codexdock version
```

Build release archives for macOS and Linux:

```bash
VERSION=0.1.0 COMMIT=unknown BUILD_DATE=2026-06-28T00:00:00Z ./scripts/package.sh
```

Each archive is written with a matching `.sha256` checksum file in `dist/`.

Install a packaged archive into a user-owned prefix:

```bash
PREFIX="$HOME/.local" ./scripts/install.sh dist/codexdock_0.1.0_darwin_arm64.tar.gz
PREFIX="$HOME/.local" ./scripts/install.sh dist/codexdock_0.1.0_linux_amd64.tar.gz
```

The installer verifies a sibling `.sha256` file when present, copies the
`codexdock` binary to `$PREFIX/bin/codexdock`, and prints the installed
version. Set `BINDIR` when you want to install directly into another bin
directory.
