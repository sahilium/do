# do

![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.1-blue)
![Gem](https://img.shields.io/gem/v/do_run)
![Downloads](https://img.shields.io/gem/dt/do_run)
![CI](https://img.shields.io/github/actions/workflow/status/sahilium/do/ci.yml?label=CI)
![License](https://img.shields.io/github/license/sahilium/do)

`do` is a **declarative execution layer for Linux**. It translates a small
TOML configuration into **systemd user services and timers**, giving you a
friendly control plane without reinventing scheduling.

`do` is *not* a scheduler, service manager, shell, or configuration-management
system. It is the declarative control plane on top of systemd.

## Why it exists

Linux already has excellent primitives for running and scheduling work:
systemd services and timers. What's missing is a small, human-friendly,
declarative way to describe a task and have that translated into systemd units
automatically. `do` fills that gap. Say what to run, when to run it, and under
what environment/who directory; `do` turns that into working units.

## Installation

```bash
gem install do_run
```

The executable is `do`.

For development:

```bash
bundle exec ruby bin/do
```

Requires Linux with a running systemd **user** session.

## Configuration format

Configuration lives in a single TOML file:

```text
~/.config/do/config.toml
```

The TOML file is the **source of truth**. Generated systemd units are derived
artifacts and are never the primary configuration mechanism.

### Example

```toml
[tasks.backup]
command = "restic backup ~/Documents"
schedule = "daily"
time = "02:00"
enabled = true

[tasks.update]
command = "do update"
schedule = "weekly"
day = "sunday"
time = "10:00"
enabled = true

[tasks.report]
command = "~/bin/generate-report"
working_directory = "~/projects/report"
schedule = "monthly"
day = "1"
time = "18:00"

[tasks.report.environment]
REPORT_FORMAT = "markdown"
```

### Task schema

| Field               | Required | Notes                                                        |
|---------------------|----------|--------------------------------------------------------------|
| `command`           | yes      | Command to execute (an argument list, executed without a shell) |
| `schedule`          | no       | `once`, `hourly`, `daily`, `weekly`, `monthly`. Omit for manual-only (default). |
| `time`              | no       | Clock time in `HH:MM`. Defaults to `00:00`.                  |
| `day`               | no       | Weekday name (`sunday`) for `weekly`; day-of-month (`1`) for `monthly`. |
| `working_directory` | no       | Directory the command runs in.                               |
| `environment`       | no       | Table mapping `KEY = "value"` to export to the command.      |
| `enabled`           | no       | `true` for scheduled tasks that should run, `false` otherwise. |

**`enabled` default behavior:** defaults to `true` when the task has a
schedule, and `false` for manual-only (unscheduled) tasks. An explicit value
always wins.

**Commands are not shell strings.** A `command` is split into an argument list
lexically. No `~` expansion, no globbing, no environment interpolation, no
shell operators. If you genuinely need shell behavior, ask for it explicitly:

```toml
command = "bash -lc 'commit && push'"
```

## Running a task

```bash
do run backup        # run immediately; returns the command's exit status
do backup            # shorthand for `do run backup`
```

Manual execution never alters a scheduled timer.

## Scheduling a task

Schedules are declared in the TOML file; `do reload` turns them into systemd
user timers.

```bash
do reload            # generate/update units, remove stale ones, reload systemd
do schedule backup   # ensure a scheduled task's timer exists and is enabled
do unschedule backup # disable and remove the timer (keeps the TOML entry)
```

Schedule types and their systemd `OnCalendar=` mappings:

| Schedule | Meaning                                   | Example                          |
|----------|-------------------------------------------|----------------------------------|
| `once`   | Run once when the timer is activated      | `OnActiveSec=0`                  |
| `hourly` | Every hour at the configured minute       | `*-*-* *:30:00`                  |
| `daily`  | Every day at `time`                       | `*-*-* 02:00:00`                 |
| `weekly` | Every week on `day` at `time`             | `Sun *-*-* 10:00:00`             |
| `monthly`| Every month on day-of-month `day` at time | `*-*-1 09:00:00`                 |

`do` never implements its own timer loop; it always maps onto systemd's native
calendar syntax.

## Enabling / disabling tasks

```bash
do enable backup     # activates the timer (writes enabled = true, reloads)
do disable backup    # deactivates the timer (writes enabled = false, reloads)
```

Disabling never deletes the TOML configuration.

## Inspecting status

```bash
do list              # table of tasks, status, schedule, next run
do status backup     # enabled/disabled, running, schedule, next/last run
do validate          # validate the configuration without changing anything
do doctor            # check the environment and configuration
```

## Viewing logs

```bash
do logs backup               # journalctl --user for the task's service
do logs backup --follow      # follow new lines
do logs backup --tail 100    # last 100 lines
```

## Removing tasks

```bash
do remove backup             # asks for confirmation
do remove backup --yes       # skip confirmation; removes TOML entry + units
do remove backup --yes --keep-config  # keep the TOML entry, remove only units
```

Removal requires confirmation unless `--yes` is provided.

## Other commands

```bash
do validate      # validate the configuration
do reload        # sync units with the configuration
do doctor        # environment/configuration diagnostics
do version       # print the version
do help          # show all commands
do config path   # print the config file path
do config show   # print the parsed/effective configuration
```

## Architecture

```
do/
├── bin/do               # executable (thin ARGV dispatch + CLI)
├── lib/do.rb            # requires the library
├── lib/do/
│   ├── cli.rb           # Thor CLI + subcommands
│   ├── config.rb        # TOML parsing, default path, config editing
│   ├── task.rb          # task model + `enabled` defaults
│   ├── scheduler.rb     # declarative schedule -> OnCalendar expressions
│   ├── systemd.rb       # unit generation + systemctl/journalctl wrapper
│   ├── executor.rb      # safe no-shell command execution
│   ├── validator.rb     # stateless configuration validation
│   └── manager.rb       # applies config to the systemd user manager
├── spec/                # RSpec suite (systemd mocked)
├── do.gemspec
├── Gemfile
├── README.md
└── CHANGELOG.md
```

## systemd integration

Each scheduled task generates two user units under
`~/.config/systemd/user/`:

```text
do-backup.service
do-backup.timer
```

`do` manages units through the current user's systemd user manager
(`systemctl --user ...`), never system-wide units, never requiring root. All
generated files carry a `Managed by do` marker. `do reload`:

1. Parses and validates the TOML.
2. Generates/updates the required units.
3. Removes obsolete `do`-managed units.
4. Runs `systemctl --user daemon-reload`.
5. Enables/disables timers according to configuration.

Units **not** carrying the `do` marker are never touched.

## v1.0 limitations

- Linux with a systemd user session is required.
- Command execution is shell-free by default; shell behavior must be requested
  explicitly.
- No retries, DAGs, event triggers, secrets, remote/container/distributed
  execution, or a persistent daemon.
- `once` runs once on timer activation (no calendar persistence).
- No automatic dependency installation.

## Development

```bash
bundle install
bundle exec rspec
```

The normal test suite mocks systemd and does not require a real user session.
