require_relative 'error'
require_relative 'scheduler'

module Do
  # Generates the systemd user unit files that `do` manages, and wraps the
  # `systemctl --user` / `journalctl --user` commands used to control them.
  #
  # Generated unit files carry a clear "Managed by do" marker so they can be
  # safely detected, updated, and removed later. Units not carrying this marker
  # are never touched by `do`.
  module UnitGenerator
    MANAGED_MARKER = '# Managed by do. Do not edit by hand.'.freeze

    module_function

    def service_content(task, source_path: nil)
      env_lines = task.environment.map { |k, v| "Environment=#{k}=#{v}" }
      [
        managed_header(source_path),
        '',
        '[Unit]',
        "Description=do task: #{task.name}",
        '',
        '[Service]',
        'Type=oneshot',
        "ExecStart=#{task.command}"
      ].concat(
        if task.working_directory
          ["WorkingDirectory=#{task.working_directory}"]
        else
          []
        end
      ).concat(
        env_lines,
        ['', '[Install]', 'WantedBy=default.target']
      ).join("\n") + "\n"
    end

    def timer_content(task, source_path: nil)
      on_calendar = Scheduler.on_calendar(task)
      calendar_line =
        if on_calendar&.start_with?('OnActiveSec=')
          on_calendar
        else
          "OnCalendar=#{on_calendar}"
        end
      [
        managed_header(source_path),
        '',
        '[Unit]',
        "Description=do task: #{task.name} (timer)",
        '',
        '[Timer]',
        calendar_line
      ].concat(
        if task.schedule == 'once'
          []
        else
          ['Persistent=true']
        end
      ).push(
        '', '[Install]', 'WantedBy=timers.target'
      ).join("\n") + "\n"
    end

    def managed_header(source_path)
      lines = [MANAGED_MARKER]
      lines << "# Source: #{source_path}" if source_path
      lines.join("\n")
    end
  end

  # Wraps systemd user session commands. All calls run through the current
  # user's systemd user manager; `do` never touches system-wide units.
  class Systemd
    attr_reader :systemctl_bin, :journalctl_bin

    def initialize(systemctl_bin: ENV.fetch('SYSTEMCTL', 'systemctl'),
                   journalctl_bin: ENV.fetch('JOURNALCTL', 'journalctl'))
      @systemctl_bin = systemctl_bin
      @journalctl_bin = journalctl_bin
    end

    def user_available?
      shell_system([@systemctl_bin, '--user', 'is-system-running'],
                   out: File::NULL, err: File::NULL)
    end

    def unit_dir
      dir = ENV.fetch('XDG_CONFIG_HOME', nil)
      dir = File.join(Dir.home, '.config') if dir.nil? || dir.empty?
      File.join(dir, 'systemd', 'user')
    end

    def exists?(unit)
      run(['show', '-p', 'Id', '--no-pager', unit]).success?
    end

    def enabled?(unit)
      run(['is-enabled', '--no-pager', unit]).success?
    end

    def active?(unit)
      run(['is-active', '--no-pager', unit]).success?
    end

    def enable(unit)
      run(['enable', '--now', unit])
    end

    def disable(unit)
      run(['disable', '--now', unit])
    end

    def start(unit)
      run(['start', unit])
    end

    def stop(unit)
      run(['stop', unit])
    end

    def daemon_reload
      run(['daemon-reload'])
    end

    def status(unit, extra: '--no-pager')
      run(['status', unit, extra])
    end

    # @return [Time, nil] formatted next-elapsed time from a timer unit.
    def next_time(unit)
      require 'time'
      value = show_prop(unit, 'NextElapseUSecRealtime')
      return nil if value.nil? || value.empty?

      Time.parse(value).localtime
    rescue ArgumentError
      nil
    end

    # @return [Time, nil] when the service last transitioned to active.
    def last_active(unit)
      value = show_prop(unit, 'ActiveEnterTimestamp')
      value.nil? || value.empty? ? nil : Time.parse(value).localtime
    end

    # @return [Integer, nil] exit status of the last run of a service.
    def last_exit_status(unit)
      value = show_prop(unit, 'ExecMainStatus')
      value.nil? || value.empty? ? nil : value.to_i
    end

    def active_state(unit)
      show_prop(unit, 'ActiveState')
    end

    # @return [String, nil] a whitespace-trimmed value for +prop+.
    def show_prop(unit, prop)
      require 'time'
      out = run(['show', '-p', prop, '--no-pager', unit]).out
      m = out.match(/^#{Regexp.escape(prop)}=(.+)$/)
      m ? m[1].strip : nil
    end

    def logs(unit, follow: false, tail: nil)
      args = ['-u', unit, '--no-pager']
      args << '-f' if follow
      args << "-n #{tail}" if tail
      system(*[@journalctl_bin, '--user', *args].flatten)
    end

    # Run a systemctl --user command, returning an Open3 result-like struct
    # exposing #success?, #out, #err, #exitstatus.
    def run(args)
      require 'open3'
      @out, @err, @status = Open3.capture3(@systemctl_bin, '--user', *args)
      OpenStructish.new(@status.exitstatus, @out, @err, @status.success?)
    end

    private

    def shell_system(args, **opts)
      SystemRaw.new(args, opts)
    end

    # Minimal result holder so tests and callers share one shape.
    class OpenStructish
      attr_reader :exitstatus, :out, :err

      def initialize(exitstatus, out, err, success)
        @exitstatus = exitstatus
        @out = out
        @err = err
        @success = success
      end

      def success?
        @success
      end
    end

    class SystemRaw
      def initialize(args, opts)
        @args = args
        @ok = system(*args, **opts)
      end

      def success?
        @ok
      end
    end
  end
end
