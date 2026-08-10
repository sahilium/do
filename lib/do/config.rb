require 'toml-rb'
require_relative 'task'
require_relative 'error'

module Do
  # Loads and represents the declarative TOML configuration.
  #
  # The TOML file is the source of truth. Everything else `do` produces is a
  # derived artifact. This class only parses the file; validation is performed
  # by {Validator}.
  class Config
    KNOWN_TASK_FIELDS = %w[
      command schedule time day working_directory environment enabled
    ].freeze

    # Default location when no path is given.
    def self.default_path
      dir = ENV.fetch('XDG_CONFIG_HOME', nil)
      dir = File.join(Dir.home, '.config') if dir.nil? || dir.empty?
      File.join(dir, 'do', 'config.toml')
    end

    # @return [Array<String>] validation errors found while parsing.
    def self.parse(raw_text, source: 'config.toml')
      parsed = TomlRB.parse(raw_text)
      new(parsed, source: source)
    rescue TomlRB::ParseError, Psych::SyntaxError => e
      raise ValidationError, ["Malformed TOML in #{source}: #{e.message}"]
    rescue StandardError => e
      raise ValidationError, ["Failed to parse #{source}: #{e.message}"]
    end

    def self.load(path = default_path)
      raise Error, "Configuration file does not exist: #{path}" unless File.exist?(path)

      raw = File.read(path)
      config = parse(raw, source: path)
      config.path = path
      config
    end

    attr_reader :raw, :tasks
    attr_accessor :path

    def initialize(raw, source: nil)
      @raw = raw || {}
      @source = source
      @tasks = build_tasks(@raw['tasks'])
    end

    def task(name)
      @tasks.find { |t| t.name == name }
    end

    def [](key)
      @raw[key]
    end

    # Edit a scalar field inside a task's table without re-serializing the
    # whole file (preserving user comments/formatting elsewhere). Used by
    # `enable`/`disable`.
    def set_task_field(task_name, field, toml_value)
      text = File.read(@path)
      idx = block_start_index(text, task_name)
      return edit_field_anywhere(text, task_name, field, toml_value) if idx.nil?

      lines = text.lines
      block_end = block_end_index(lines, idx)
      match = (idx...block_end).find { |i| lines[i] =~ /\A#{Regexp.escape(field)}\s*=/ }
      if match
        lines[match] = "#{field} = #{toml_value}\n"
      else
        lines.insert(idx + 1, "#{field} = #{toml_value}\n")
      end
      File.write(@path, lines.join)
    end

    # Remove a task's table from the file. Used by `do remove`. Also removes
    # any nested tables under the same task (e.g. `[tasks.name.environment]`).
    def remove_task(task_name)
      text = File.read(@path)
      idx = block_start_index(text, task_name)
      raise Error, "task '#{task_name}' not present in configuration" if idx.nil?

      lines = text.lines
      block_end = task_block_end(lines, idx, task_name)
      removed = lines[0...idx] + lines[block_end..]
      # Collapse leftover blank lines around the removed block (best effort).
      File.write(@path, removed.join.gsub(/\n{3,}/, "\n\n"))
    end

    private

    # Continue past nested tables that belong to the same task.
    def task_block_end(lines, idx, task_name)
      i = idx + 1
      while i < lines.length
        line = lines[i]
        break if line.start_with?('[') && !line.start_with?("[tasks.#{task_name}.") &&
                 !line.start_with?("[tasks.\"#{task_name}\".")

        i += 1
      end
      i
    end

    def block_start_index(text, task_name)
      re = /\[tasks\.#{Regexp.escape(task_name)}\]\s*\z|\[tasks\."#{Regexp.escape(task_name)}"\]\s*\z/
      text.lines.index { |l| l.start_with?('[tasks.') && l =~ re }
    end

    def block_end_index(lines, idx)
      i = idx + 1
      i += 1 while i < lines.length && !lines[i].start_with?('[')
      i
    end

    # Fallback: file may have been edited/scrambled; attempt a field swap
    # outside a knowing block. Keeps commands non-destructive toward comments.
    def edit_field_anywhere(text, task_name, field, toml_value)
      header = "[tasks.#{task_name}]"
      return unless text.include?(header)

      _ = text
      hmm = text.gsub(/^(\s*)#{Regexp.escape(field)}\s*=.*/, "  #{field} = #{toml_value}")
      File.write(@path, hmm) if hmm != text
    end

    def build_tasks(raw_tasks)
      return [] if raw_tasks.nil?

      unless raw_tasks.is_a?(Hash)
        raise ValidationError, ["'tasks' must be a table of task definitions in #{@source}"]
      end

      raw_tasks.map do |name, fields|
        fields ||= {}
        unless fields.is_a?(Hash)
          raise ValidationError, ["task '#{name}' definitions must be tables in #{@source}"]
        end

        env = fields['environment']
        unless env.nil? || env.is_a?(Hash)
          raise ValidationError, ["environment for task '#{name}' must be a table in #{@source}"]
        end

        Task.new(
          name: name.to_s,
          command: fields['command'],
          schedule: fields['schedule'],
          time: fields['time'],
          day: fields['day'],
          working_directory: fields['working_directory'],
          environment: env,
          enabled: fields['enabled'],
          raw: fields
        )
      end
    rescue TypeError => e
      raise ValidationError, ["Invalid configuration structure: #{e.message}"]
    end
  end
end
