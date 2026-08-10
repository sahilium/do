# Changelog

All notable changes to this project are documented in this file.

## [0.1.0] - Unreleased

### Added
- Declarative TOML configuration at `~/.config/do/config.toml`.
- Task model with `command`, `schedule`, `time`, `day`, `working_directory`,
  `environment`, and `enabled`.
- Schedule types: `once`, `hourly`, `daily`, `weekly`, `monthly`, mapped to
  systemd `OnCalendar=` expressions.
- Systemd user service/timer generation with `Managed by do` marker.
- Commands: `run`, `list`, `status`, `logs`, `enable`, `disable`, `remove`,
  `validate`, `reload`, `schedule`, `unschedule`, `doctor`, `version`,
  `config path`, `config show`, plus `do <task>` shorthand.
- Stateless validator covering malformed TOML, missing fields, invalid
  schedules/times/days, duplicate names, missing directories, malformed
  environments, invalid unit names, and unsupported fields.
- RSpec suite with systemd mocked.
