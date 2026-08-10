require "tmpdir"
require "fileutils"
require "time"

require_relative "../lib/do"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.around(:each) do |example|
    Dir.mktmpdir("do-spec") do |dir|
      @tmpdir = dir
      example.run
    end
  end
end

def with_config(text, name: "config.toml")
  path = File.join(@tmpdir, name)
  File.write(path, text)
  yield path
end

def write_config(tasks)
  path = File.join(@tmpdir, "config.toml")
  toml = tomldump(tasks)
  File.write(path, toml)
  path
end

# Minimal hand-rolled TOML writer for specs, enough for our flat task schema.
def tomldump(tasks)
  out = []
  tasks.each do |name, fields|
    out << "[tasks.#{name}]"
    fields.each do |k, v|
      out << "#{k} = #{toml_scalar(v)}"
    end
    out << ""
  end
  out.join("\n").gsub(/\n\n+\z/, "\n")
end

def toml_scalar(v)
  case v
  when true then "true"
  when false then "false"
  when nil then raise "nil scalar"
  when Hash
    "{\n" + v.map { |k, val| "    #{k} = #{toml_scalar(val)}" }.join("\n") + "\n  }"
  else
    %("#{v}")
  end
end