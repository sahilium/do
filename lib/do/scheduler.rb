require_relative "error"

module Do
  # Translates a task's declarative schedule into a systemd calendar
  # expression ({#on_calendar}) suitable for use in an `OnCalendar=` directive.
  #
  # `do` does not implement its own timer loop; it only maps a small, fixed set
  # of schedule shapes onto systemd's native calendar syntax.
  class Scheduler
    TIME_RE = /\A([01]?\d|2[0-3]):([0-5]\d)\z/

    # @return [String, nil] the systemd OnCalendar expression, or nil when the
    #   task is manual-only.
    def self.on_calendar(task)
      case task.schedule
      when nil, "" then nil
      when "once"   then once_calendar
      when "hourly" then hourly_calendar(task)
      when "daily"  then daily_calendar(task)
      when "weekly" then weekly_calendar(task)
      when "monthly" then monthly_calendar(task)
      else
        raise Error, "unsupported schedule '#{task.schedule}'"
      end
    end

    def self.once_calendar
      # OnActiveSec=0 fires the service exactly once, when the timer is
      # activated. The reload/enable workflow activates the timer, so `once`
      # means "run once now when scheduled", without repeating.
      "OnActiveSec=0"
    end

    def self.hourly_calendar(task)
      _, min = split_time(task, fallback: [0, 0])
      "*-*-* *:#{pad(min)}:00"
    end

    def self.daily_calendar(task)
      hour, min = split_time(task, fallback: [0, 0])
      "*-*-* #{pad(hour)}:#{pad(min)}:00"
    end

    def self.weekly_calendar(task)
      hour, min = split_time(task, fallback: [0, 0])
      dow = weekday_short(task)
      "#{dow} *-*-* #{pad(hour)}:#{pad(min)}:00"
    end

    def self.monthly_calendar(task)
      hour, min = split_time(task, fallback: [0, 0])
      dom = monthly_day(task)
      "*-*-#{dom} #{pad(hour)}:#{pad(min)}:00"
    end

    def self.weekday_short(task)
      day = task.day&.to_s&.downcase
      Task::WEEKDAY_NUMBERS[day] or
        raise Error, "invalid day '#{task.day}'; expected a day name like 'monday'"
      day[0, 3].capitalize
    end

    def self.weekday_number(task)
      day = task.day&.to_s&.downcase
      Task::WEEKDAY_NUMBERS[day] or
        raise Error, "invalid day '#{task.day}'; expected a day name like 'monday'"
    end

    def self.monthly_day(task)
      day = task.day&.to_s
      if day.nil? || day.empty?
        "1"
      elsif day =~ /\A([1-9]|[12]\d|3[01])\z/
        day
      else
        raise Error, "invalid monthly day '#{task.day}'; expected a day-of-month 1-31"
      end
    end

    def self.split_time(task, fallback:)
      return fallback if task.time.nil? || task.time.empty?

      m = TIME_RE.match(task.time.to_s)
      raise Error, "invalid time '#{task.time}'; expected HH:MM" unless m

      [m[1].to_i, m[2].to_i]
    end

    def self.pad(value)
      value.to_s.rjust(2, "0")
    end
  end
end