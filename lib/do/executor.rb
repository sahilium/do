require "shellwords"
require_relative "error"

module Do
  # Executes a task's command as an argument list, without a shell.
  #
  # The `command` string is split into argv tokens lexically (respecting
  # quoting but performing no variable expansion, `~` expansion, or globbing).
  # This is the safe, declarative default described in the spec. Tasks that
  # genuinely need shell features must request them explicitly, e.g. by
  # prefixing with `bash -lc '...'`.
  class Executor
    attr_reader :systemd

    def initialize(systemd: Systemd.new)
      @systemd = systemd
    end

    # Run the task immediately and return its exit status. The timer schedule
    # is never altered by manual execution.
    #
    # @return [Integer] process exit status
    def run(task)
      argv = Shellwords.split(task.command)
      raise Error, "task '#{task.name}' has an empty command" if argv.empty?

      env_overrides = task.environment || {}
      options = {}
      if task.working_directory
        options[:chdir] = File.expand_path(task.working_directory)
      end

      pid = Process.spawn(env_overrides, *argv, options)
      _pid, status = Process.wait2(pid)
      status.exitstatus || 0
    end
  end
end