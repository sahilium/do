require_relative 'config'
require_relative 'scheduler'
require_relative 'task'
require_relative 'error'

module Do
  # Stateless validation over a parsed {Config}. Returns human-readable error
  # strings and never touches the system.
  module Validator
    module_function

    # @param config [Config] parsed configuration
    # @return [Array<String>] validation errors (empty when valid)
    def validate(config)
      errors = []
      errors.concat(validate_commands(config))
      errors.concat(validate_task_fields(config))
      errors.concat(validate_duplicates(config))
      errors.concat(validate_schedules(config))
      errors.concat(validate_unit_names(config))
      errors.concat(validate_directories(config))
      errors.concat(validate_environment(config))
      errors
    end

    def valid?(config)
      validate(config).empty?
    end

    # @raise [ValidationError] when config is invalid
    def validate!(config)
      errors = validate(config)
      raise ValidationError, errors unless errors.empty?

      true
    end

    def validate_commands(config)
      config.tasks.flat_map do |task|
        if task.command.nil? || task.command.to_s.strip.empty?
          ["task '#{task.name}' is missing required field 'command'"]
        else
          []
        end
      end
    end

    def validate_task_fields(config)
      config.tasks.flat_map do |task|
        unknown = task.raw.keys - Config::KNOWN_TASK_FIELDS
        unknown.map { |field| "unsupported field '#{field}' for task '#{task.name}'" }
      end
    end

    def validate_duplicates(config)
      lowered = config.tasks.map { |t| t.name.downcase }
      lowered
        .select { |n| lowered.count(n) > 1 }.uniq
        .map { |n| "duplicate task name '#{n}'" }
    end

    def validate_schedules(config)
      config.tasks.flat_map { |task| schedule_errors(task) }
    end

    def validate_unit_names(config)
      config.tasks.flat_map do |task|
        name = task.name.to_s
        if name.empty?
          ['task has an empty name']
        elsif name.start_with?('.') || name =~ %r{[\s/]|\.}
          ["task name '#{name}' is not a valid systemd unit name " \
           "(must not contain spaces, '/', dots, or start with a dot)"]
        else
          []
        end
      end
    end

    def validate_directories(config)
      config.tasks.flat_map do |task|
        wd = task.working_directory
        next [] if wd.nil? || wd.empty?

        if File.directory?(File.expand_path(wd))
          []
        else
          ["working directory '#{wd}' for task '#{task.name}' does not exist"]
        end
      end
    end

    def validate_environment(config)
      config.tasks.flat_map do |task|
        (task.environment || {}).flat_map do |key, value|
          if key.is_a?(String) && value.is_a?(String)
            []
          else
            ["environment for task '#{task.name}' must map strings to strings"]
          end
        end
      end
    end

    def schedule_errors(task)
      sched = task.schedule
      return [] if sched.nil? || sched.empty?

      unless Task::SCHEDULES.include?(sched)
        return ["invalid schedule for task '#{task.name}'. " \
                'Expected: once, hourly, daily, weekly, or monthly.']
      end

      # Driving the calendar generator lets us reuse the exact same parsing
      # rules that will later be used to emit the systemd unit.
      begin
        Scheduler.on_calendar(task)
        []
      rescue Do::Error => e
        ["invalid schedule for task '#{task.name}': #{e.message}"]
      end
    end
  end
end
