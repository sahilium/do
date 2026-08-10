module Do
  # A single declared task parsed from the TOML configuration.
  #
  # Tasks are plain Ruby objects; the {Validator} is responsible for deciding
  # whether their field values are acceptable. This class only carries data
  # and exposes a few derived helpers.
  class Task
    SCHEDULES = %w[once hourly daily weekly monthly].freeze
    WEEKDAY_NAMES = %w[monday tuesday wednesday thursday friday saturday sunday].freeze
    WEEKDAY_NUMBERS = {
      "monday" => 1, "tuesday" => 2, "wednesday" => 3, "thursday" => 4,
      "friday" => 5, "saturday" => 6, "sunday" => 7
    }.freeze

    attr_reader :name, :command, :schedule, :time, :day,
                :working_directory, :environment, :raw

    def initialize(name:, command:, schedule: nil, time: nil, day: nil,
                   working_directory: nil, environment: {}, enabled: nil, raw: {})
      @name = name
      @command = command
      @schedule = schedule
      @time = time
      @day = day
      @working_directory = working_directory
      @environment = environment || {}
      @enabled = enabled
      @raw = raw
    end

    # `enabled` is true by default for scheduled tasks and false for
    # manual-only (unscheduled) tasks.
    def enabled?
      return scheduled? if @enabled.nil?
      return @enabled == "true" || @enabled == true if @enabled.is_a?(String)

      !!@enabled
    end

    def scheduled?
      !@schedule.nil? && @schedule != ""
    end

    # Return the service unit name systemd will use for this task.
    def service_unit
      "do-#{name}.service"
    end

    def timer_unit
      "do-#{name}.timer"
    end
  end
end