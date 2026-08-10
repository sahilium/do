# `do` — v1.0 Implementation Summary

A declarative Linux execution layer backed by systemd user services and timers.

## Project structure

```
do/
├── bin/do               # executable; rewires `do <task>` -> `do run <task>`
├── lib/do.rb            # library entry point (requires all components)
├── lib/do/
│   ├── version.rb       # Do::VERSION
│   ├── error.rb         # Do::Error, Do::ValidationError
│   ├── cli.rb           # Thor CLI (Do::CLI) + Do::ConfigCommand subcommand
│   ├── config.rb        # TOML parse/load, default path, task construction,
│   │                    #   textual field editing and task removal
│   ├── task.rb          # Do::Task model, schedule constants, enabled defaults
│   ├── scheduler.rb     # Do::Scheduler: schedule -> OnCalendar expressions
│   ├── systemd.rb       # Do::UnitGenerator (unit file text) + Do::Systemd
│   │                    #   (systemctl --user / journalctl --user wrapper)
│   ├── validator.rb     # Do::Validator: stateless config validation
│   ├── executor.rb      # Do::Executor: safe no-shell command execution
│   └── manager.rb       # Do::Manager: applies config to systemd user manager
├── spec/
│   ├── spec_helper.rb
│   ├── config_spec.rb
│   ├── task_spec.rb
│   ├── validator_spec.rb
│   ├── scheduler_spec.rb
│   ├── systemd_spec.rb
│   ├── systemd_gen_spec.rb
│   ├── executor_spec.rb
│   ├── manager_spec.rb
│   └── cli_spec.rb
├── Gemfile
├── do.gemspec
├── README.md
├── CHANGELOG.md
└── LICENSE
```

## Commands implemented

| Command                    | Purpose                                              |
|----------------------------|------------------------------------------------------|
| `do run <task>`            | Execute a task immediately; returns exit status      |
| `do <task>`                | Shorthand for `do run <task>`                        |
| `do list`                  | Table of tasks, status, schedule, next run           |
| `do status <task>`         | Detail: enabled, running, schedule, next/last run    |
| `do logs <task> [--follow] [--tail N]` | journalctl --user for the service        |
| `do enable <task>`         | Activate the task's timer (writes `enabled = true`)  |
| `do disable <task>`        | Deactivate the timer (writes `enabled = false`)      |
| `do remove <task>`         | Remove units + TOML entry (confirmation / `--yes`)   |
| `do validate`              | Validate config without modifying the system         |
| `do reload`                | Sync generated units with config, reload systemd     |
| `do schedule <task>`       | Ensure a scheduled task's timer is generated/enabled |
| `do unschedule <task>`     | Disable + remove a timer, keep the TOML entry        |
| `do doctor`                | Environment and configuration diagnostics            |
| `do version`               | Print version                                        |
| `do help`                  | Show all commands                                    |
| `do config path`           | Print config file path                               |
| `do config show`           | Print parsed/effective configuration                 |

## TOML schema

```toml
[tasks.<name>]
command            = "string"          # required
schedule           = "once|hourly|daily|weekly|monthly"
time               = "HH:MM"
day                = "weekday|day-of-month"
working_directory  = "/absolute/path"
enabled            = true | false

[tasks.<name>.environment]
KEY = "value"                          # strings only
```

`enabled` defaults to `true` for scheduled tasks, `false` for manual-only.
The TOML file is the source of truth; generated units are derived artifacts.

## Schedule -> systemd mapping

| Schedule | OnCalendar / directive          |
|----------|---------------------------------|
| once     | `OnActiveSec=0`                 |
| hourly   | `*-*-* *:MM:00`                 |
| daily    | `*-*-* HH:MM:00`                |
| weekly   | `Dow *-*-* HH:MM:00`            |
| monthly  | `*-*-D HH:MM:00`                |

## Tests written (RSpec, 76 examples)

- **config_spec** — default path (XDG/HOME), TOML parsing, malformed TOML,
  environment tables, in-place field editing, task removal with nested tables.
- **task_spec** — enabled defaults, `scheduled?`, derived unit names.
- **validator_spec** — missing command, invalid schedule/time/day, unsupported
  fields, duplicate names, missing working directory, non-string environment,
  invalid unit names, `validate!` behavior.
- **scheduler_spec** — every schedule type, zero-padding, defaults, and error
  cases.
- **systemd_spec** — unit generation (marker, ExecStart, WorkingDirectory,
  Environment, OnCalendar, once) and the systemctl/journalctl wrapper against a
  fake binary.
- **executor_spec** — exit status, working directory, environment, empty
  command, missing executable.
- **manager_spec** — writes service+timer, skips manual tasks, removes stale
  `do`-managed units (never user units), enable/disable, refuses invalid
  config, unschedule.
- **cli_spec** — subprocess exit codes, shorthand, errors, version, validate,
  config path, list output.

Systemd is exercised through a fake `systemctl` script; no real user session is
required for the normal suite.

## Known limitations

- Linux + systemd user session required; no root.
- Commands run without a shell by default (no `~`/glob/env expansion). Shell
  behavior must be requested explicitly (`bash -lc '...'`).
- `once` fires a single time on timer activation.
- No retries/DAGs/event triggers/secrets/remote/daemon.
- `do list`/`status` report next-run by querying systemd; when the timer is not
  active the value is `-`.

## Running the project locally

```bash
# dependencies
gem install toml-rb thor rspec          # or: bundle install

# run the CLI directly
bundle exec ruby bin/do version
bundle exec ruby bin/do help

# point at a config (optional)
export DO_CONFIG=$HOME/.config/do/config.toml

# reload after editing config.toml
bundle exec ruby bin/do reload

# tests
bundle exec rspec
```
