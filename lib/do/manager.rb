require 'fileutils'
require_relative 'systemd'
require_relative 'validator'
require_relative 'error'

module Do
  # Orchestrates the lifecycle of generated units against the systemd user
  # manager. This is the layer that turns config into reality: writing unit
  # files, detecting and removing stale `do`-managed units, reloading systemd,
  # and enabling/disabling schedulers.
  class Manager
    attr_reader :systemd

    def initialize(systemd: Systemd.new, config: nil)
      @systemd = systemd
      @config = config
    end

    attr_writer :config

    # Apply the configuration to the user systemd manager.
    #
    # Never overwrites units without the `do` marker. Refuses to run when the
    # configuration is invalid.
    def reload(config = @config)
      Validator.validate!(config)
      dir = @systemd.unit_dir
      FileUtils.mkdir_p(dir)

      expected = {}
      config.tasks.each do |task|
        next unless task.scheduled?

        expected[task.service_unit] =
          UnitGenerator.service_content(task, source_path: config.path)
        expected[task.timer_unit] = UnitGenerator.timer_content(task, source_path: config.path)
      end

      write_units(dir, expected)
      remove_stale_units(dir, expected.keys)
      @systemd.daemon_reload
      apply_enabled(config)
      :ok
    end

    # Remove a task's generated units (if any) and reload. Does not touch the
    # TOML configuration.
    def unschedule(task, _config = @config)
      remove_units_for(task)
      @systemd.daemon_reload
      :ok
    end

    # Remove all units a task owns, regardless of whether the task is
    # scheduled. Used by `do remove`.
    def remove_units_for(task)
      [task.service_unit, task.timer_unit].each do |unit|
        path = File.join(@systemd.unit_dir, unit)
        FileUtils.rm_f(path) if File.exist?(path) && managed?(path)
        @systemd.disable(unit) if @systemd.exists?(unit)
      end
      @systemd.daemon_reload
      :ok
    end

    private

    def write_units(dir, expected)
      expected.each do |unit, content|
        path = File.join(dir, unit)
        existing = File.exist?(path) ? File.read(path) : nil
        File.write(path, content) if existing != content
      end
    end

    # Remove `do`-managed units that are no longer expected (deleted task or
    # a schedule was removed). Only files carrying the managed marker are
    # considered; user-created units are never touched.
    def remove_stale_units(dir, expected)
      stale = Dir.glob(File.join(dir, 'do-*.{service,timer}')).select do |path|
        basename = File.basename(path)
        !expected.include?(basename) && managed?(path)
      end
      stale.each do |path|
        FileUtils.rm_f(path)
        disable_if_known(File.basename(path))
      end
    end

    def disable_if_known(unit)
      @systemd.disable(unit) if @systemd.exists?(unit)
    end

    def managed?(path)
      File.read(path).lines.any? { |l| l.include?('Managed by do') }
    rescue Errno::ENOENT
      false
    end

    def apply_enabled(config)
      config.tasks.each do |task|
        next unless task.scheduled?

        if task.enabled?
          @systemd.enable(task.timer_unit)
          @systemd.start(task.timer_unit)
        else
          @systemd.disable(task.timer_unit)
          @systemd.stop(task.timer_unit) if @systemd.active?(task.timer_unit)
        end
      end
    end
  end
end
