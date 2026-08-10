require 'thor'
require 'shellwords'
require 'time'
require_relative 'version'
require_relative 'error'
require_relative 'config'
require_relative 'task'
require_relative 'scheduler'
require_relative 'systemd'
require_relative 'validator'
require_relative 'executor'
require_relative 'manager'

module Do
  # `do config path` / `do config show`.
  class ConfigCommand < Thor
    namespace 'config'

    desc 'path', 'Print the configuration file path.'
    def path
      say ENV['DO_CONFIG'] || Do::Config.default_path
    end

    desc 'show', 'Print the parsed/effective configuration.'
    def show
      cfg_path = ENV['DO_CONFIG'] || Do::Config.default_path
      raise Do::Error, "Configuration file does not exist: #{cfg_path}" unless File.exist?(cfg_path)

      config = Do::Config.load(cfg_path)
      errors = Do::Validator.validate(config)
      unless errors.empty?
        errors.each { |e| say "Error: #{e}", :red }
        exit(1)
      end
      say "path: #{cfg_path}"
      say 'tasks:'
      config.tasks.each do |task|
        say "  #{task.name}:"
        say "    command:          #{task.command}"
        say "    schedule:         #{task.schedule || 'manual'}"
        say "    time:             #{task.time || '-'}"
        say "    day:              #{task.day || '-'}"
        say "    working_directory: #{task.working_directory || '-'}"
        say "    enabled:          #{task.enabled?}"
        say "    environment:      #{task.environment.inspect}" unless (task.environment || {}).empty?
      end
    end
  end

  # Thor-based CLI. Every command follows the Unix-friendly style:
  #
  #   do run backup
  #   do list
  #   do status backup
  #
  # Configuration is loaded lazily per command so that short commands like
  # `do version` don't need a valid config file.
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    # `run` is a Thor reserved word; we want it as a real command.
    def self.is_thor_reserved_word?(_word, _type)
      false
    end

    # Commands that are taken literally rather than treated as task names by
    # the shorthand `do <task>` form.
    BUILTINS = %w[
      run list status logs enable disable remove validate reload
      schedule unschedule doctor version help config
    ].freeze

    class << self
      def dispatch(meth, given_args, given_opts, config)
        super
      rescue Do::Error => e
        warn "Error: #{e.message}"
        exit 1
      end
    end

    desc 'run <task>', 'Execute a task immediately.'
    def run(task = nil)
      task = require_task!(task)
      say "> do run #{task.name}: #{task.command}"
      code = Executor.new.run(task)
      say "  finished (exit #{code})"
      exit(code) if code != 0
    end

    desc 'list', 'List configured tasks.'
    def list
      config = load_config!(validate: false)
      say header = 'TASK        STATUS     SCHEDULE            NEXT'
      say '-' * header.length
      config.tasks.each do |task|
        say format_list_row(task, systemd)
      end
    end

    desc 'status <task>', 'Show detail for a single task.'
    def status(task = nil)
      task = require_task!(task)
      show_task_status(task)
    end

    desc 'logs <task>', "Show logs for a task's service."
    option :follow, aliases: '-f', type: :boolean, desc: 'Follow new log lines.'
    option :tail, aliases: '-n', type: :numeric, desc: 'Show last N lines.'
    def logs(task = nil)
      task = require_task!(task)
      units = units_for(task)
      raise Do::Error, "task '#{task.name}' has no generated service unit." if units[:service].nil?

      say "Journal for #{units[:service]} (#{task.name}):" if $stdout.tty?
      ok = systemd.logs(units[:service], follow: options[:follow], tail: options[:tail])
      exit(1) unless ok
    end

    desc 'enable <task>', 'Mark a scheduled task enabled and activate its timer.'
    def enable(task = nil)
      change_enabled(task, true)
    end

    desc 'disable <task>', 'Mark a scheduled task disabled without removing it.'
    def disable(task = nil)
      change_enabled(task, false)
    end

    desc 'remove <task>', "Remove a task's generated units (confirmation required)."
    option :yes, type: :boolean, aliases: '-y', desc: 'Skip confirmation.'
    option :'keep-config', type: :boolean, desc: 'Only remove generated units, keep the TOML entry.'
    def remove(task = nil)
      config = load_config!(validate: false)
      task = require_task!(task, config)
      manager = Manager.new(systemd: systemd, config: config)

      confirm!("Remove generated units for task '#{task.name}'?") unless options[:yes]
      manager.remove_units_for(task)
      if options[:'keep-config']
        say "Removed generated units for '#{task.name}' (kept configuration)."
      else
        config.remove_task(task.name)
        say "Removed task '#{task.name}' from configuration and removed its units."
      end
    end

    desc 'validate', 'Validate the configuration without modifying the system.'
    def validate
      path = config_path
      raise Do::Error, "Configuration file does not exist: #{path}" unless File.exist?(path)

      config = Config.load(path)
      errors = Validator.validate(config)
      if errors.empty?
        say "OK: configuration is valid (#{config.tasks.size} task(s))."
      else
        errors.each { |e| say "Error: #{e}", :red }
        exit(1)
      end
    end

    desc 'reload', 'Generate/update units, remove stale ones, and reload systemd.'
    def reload
      config = load_config!(validate: true)
      Manager.new(systemd: systemd, config: config).reload
      say "Reloaded units for #{config.tasks.size} task(s)."
    end

    desc 'schedule <task>', 'Generate the timer for a scheduled task and enable it.'
    def schedule(task = nil)
      config = load_config!(validate: true)
      task = require_task!(task, config)
      unless task.scheduled?
        raise Do::Error,
              "task '#{task.name}' has no schedule in the configuration."
      end

      Manager.new(systemd: systemd, config: config).reload
      say "Scheduled task '#{task.name}' (#{task.schedule})."
    end

    desc 'unschedule <task>', "Disable and remove a task's timer (keeps the TOML entry)."
    def unschedule(task = nil)
      config = load_config!(validate: false)
      task = require_task!(task, config)
      Manager.new(systemd: systemd, config: config).unschedule(task)
      say "Unscheduled task '#{task.name}'."
    end

    desc 'doctor', 'Report on the environment and configuration.'
    def doctor
      run_doctor
    end

    desc 'config', 'Work with the configuration file.'
    subcommand 'config', ConfigCommand

    desc 'version', 'Show the version.'
    def version
      say Do::VERSION
    end

    private

    def systemd
      @systemd ||= Systemd.new
    end

    def config_path
      ENV['DO_CONFIG'] || Config.default_path
    end

    def load_config!(validate: true)
      path = config_path
      unless File.exist?(path)
        raise Do::Error,
              "Configuration file does not exist: #{path}\nCreate it or run 'do config path'."
      end

      config = Config.load(path)
      Validator.validate!(config) if validate
      config
    end

    def require_task!(name, config = nil)
      config ||= load_config!(validate: false)
      t = config.task(name.to_s)
      raise_does_not_exist(name) unless t
      t
    end

    def raise_does_not_exist(name)
      raise Do::Error,
            "task '#{name}' does not exist.\nRun 'do list' to see configured tasks."
    end

    def units_for(task)
      { service: task.scheduled? ? task.service_unit : nil,
        timer: task.scheduled? ? task.timer_unit : nil }
    end

    def format_list_row(task, sd)
      sched = schedule_label(task)
      next_time =
        if task.scheduled? && task.enabled?
          t = sd.next_time(task.timer_unit)
          t ? t.strftime('%a %H:%M') : '-'
        else
          '-'
        end
      format('%-10s  %-9s  %-18s  %s',
             task.name, (task.enabled? ? 'enabled' : 'disabled'), sched, next_time)
    end

    def schedule_label(task)
      return 'manual' unless task.scheduled?

      case task.schedule
      when 'once' then 'once'
      when 'hourly' then 'hourly'
      when 'daily' then "daily #{task.time || '00:00'}"
      when 'weekly' then "weekly #{short_day(task.day)} #{task.time || '00:00'}"
      when 'monthly' then "monthly day #{task.day || '1'} #{task.time || '00:00'}"
      else task.schedule.to_s
      end
    end

    def short_day(day)
      day.to_s[0, 3].capitalize
    end

    def show_task_status(task)
      sd = systemd
      service = task.scheduled? ? task.service_unit : nil
      timer = task.scheduled? ? task.timer_unit : nil

      state = active_state_label(sd, timer, service)
      say "task:      #{task.name}"
      say "status:    #{task.enabled? ? 'enabled' : 'disabled'}"
      say "running:   #{running_label(sd, service)}"
      say "schedule:  #{schedule_label(task)}"
      if timer
        t = sd.next_time(timer)
        say "next:      #{t ? t.strftime('%a %Y-%m-%d %H:%M') : 'unknown'}"
        say "active:    #{state || '-'}"
      end
      return unless service

      last = sd.last_active(service)
      code = sd.last_exit_status(service)
      say "last run:  #{last ? last.strftime('%Y-%m-%d %H:%M') : 'never'}"
      say "last exit: #{code.nil? ? '-' : code}"
    end

    def active_state_label(sd, timer, service)
      if timer && sd.active?(timer)
        'timer active'
      elsif service && sd.active?(service)
        'service active'
      else
        'inactive'
      end
    end

    def running_label(sd, service)
      return 'no unit' if service.nil?

      sd.active?(service) ? 'yes' : 'no'
    end

    def change_enabled(task_or_name, value)
      config = load_config!(validate: false)
      task = require_task!(task_or_name, config)
      unless task.scheduled?
        raise Do::Error,
              "manual-only task '#{task.name}' has no timer to #{value ? 'enable' : 'disable'}."
      end

      config.set_task_field(task.name, 'enabled', value.to_s)
      refreshed = Config.load(config.path)
      Validator.validate!(refreshed)
      Manager.new(systemd: systemd, config: refreshed).reload
      say "#{value ? 'Enabled' : 'Disabled'} task '#{task.name}'."
    end

    def confirm!(prompt)
      unless $stdin.tty?
        raise Do::Error, 'confirmation required; pass --yes for non-interactive removal.'
      end

      print "#{prompt} [y/N] "
      ans = $stdin.gets
      return if ans && ans.strip.downcase == 'y'

      say 'Aborted.'
      exit(1)
    end

    def run_doctor
      check('Ruby', true, Ruby::VERSION)
      systemctl_ok = systemctl_present?
      check('systemctl', systemctl_ok, systemctl_ok ? nil : 'not found in PATH')
      check('systemd user manager', systemd.user_available?, nil) if systemctl_ok
      check('configuration file', File.exist?(config_path), config_path)

      if File.exist?(config_path)
        begin
          config = Config.load(config_path)
          errors = Validator.validate(config)
          if errors.empty?
            check('configuration validity', true, nil)
            check_generated_units(config)
            check_enabled_timers(config)
            check_commands(config)
            check_working_dirs(config)
          else
            check('configuration validity', false, errors.first)
          end
        rescue Do::Error => e
          check('configuration validity', false, e.message)
        end
      end
      check('journal', journalctl_present?, nil)
    end

    def check(name, ok, detail)
      mark = ok ? "\u2713" : "\u2717"
      say "#{mark} #{name}#{"  (#{detail})" if detail}"
    end

    def systemctl_present?
      systemd = systemctl_bin
      systemd && !systemd.empty?
    end

    def journalctl_present?
      systemctl_bin # journalctl assumed present alongside systemctl
    end

    def systemctl_bin
      ENV['SYSTEMCTL'] || (system_detect('systemctl') ? 'systemctl' : nil)
    end

    def system_detect(bin)
      system("command -v #{bin} >/dev/null 2>&1")
    rescue StandardError
      false
    end

    def check_generated_units(config)
      dir = Systemd.new.unit_dir
      expected = config.tasks.select(&:scheduled?).flat_map do |t|
        [t.service_unit, t.timer_unit]
      end
      stale = Dir.glob(File.join(dir, 'do-*.{service,timer}')).select do |f|
        !expected.include?(File.basename(f)) && managed_file?(f)
      end
      check('generated units (no stale)', stale.empty?,
            stale.empty? ? nil : "stale: #{stale.join(', ')}")
    end

    def managed_file?(path)
      File.read(path).include?('Managed by do')
    rescue StandardError
      false
    end

    def check_enabled_timers(config)
      sd = systemd
      problems = config.tasks.select(&:scheduled?).filter_map do |t|
        next if !t.enabled? && !sd.exists?(t.timer_unit)
        next if t.enabled? && sd.enabled?(t.timer_unit)

        "timer '#{t.timer_unit}' not #{t.enabled? ? 'enabled' : 'disabled'}"
      end
      check('timers match config', problems.empty?, problems.empty? ? nil : problems.join('; '))
    end

    def check_commands(config)
      missing = config.tasks.filter_map do |t|
        bin = Shellwords.split(t.command).first
        executable_in_path?(bin) ? nil : t.name
      end
      check('commands resolvable', missing.empty?,
            (missing.empty? ? nil : "not found: #{missing.join(', ')}"))
    end

    def executable_in_path?(bin)
      return false if bin.nil? || bin.empty?
      return File.executable?(bin) if bin.include?('/')

      system("command -v #{bin} >/dev/null 2>&1")
    rescue StandardError
      false
    end

    def check_working_dirs(config)
      bad = config.tasks.select(&:working_directory).reject do |t|
        File.directory?(File.expand_path(t.working_directory))
      end
      check('working directories exist', bad.empty?,
            (bad.empty? ? nil : "missing: #{bad.map(&:name).join(', ')}"))
    end
  end
end
