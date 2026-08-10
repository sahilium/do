require 'English'
RSpec.describe Do::CLI do
  # Invoke the CLI in a subprocess so real exit codes and captured output are
  # observable, using a config path isolated to the temp dir.
  def run_cli(args, env: {})
    lib = File.expand_path('../lib', __dir__)
    out = IO.popen(
      env.merge('DO_CONFIG' => @config_path, 'RUBYLIB' => lib),
      ['ruby', File.join(lib, '../bin/do'), *args],
      chdir: __dir__,
      err: %i[child out]
    )
    output = out.read
    out.close
    [$CHILD_STATUS.exitstatus, output]
  end

  def boot_with(tasks)
    @config_path = write_config(tasks)
  end

  it 'runs a task and returns its exit status' do
    boot_with('hi' => { 'command' => "ruby -e 'exit 4'" })
    code, = run_cli(%w[run hi])
    expect(code).to eq(4)
  end

  it "supports the shorthand 'do <task>' for run" do
    boot_with('hi' => { 'command' => "ruby -e 'exit 2'" })
    code, = run_cli(['hi'])
    expect(code).to eq(2)
  end

  it 'prints an actionable error for a missing task' do
    boot_with({})
    code, out = run_cli(%w[run nope])
    expect(code).to eq(1)
    expect(out).to include("task 'nope' does not exist")
    expect(out).to include('do list')
  end

  it 'prints the version' do
    code, out = run_cli(['version'])
    expect(code).to eq(0)
    expect(out).to eq("#{Do::VERSION}\n")
  end

  it 'validate reports an invalid config and exits non-zero' do
    @config_path = write_config('t' => { 'schedule' => 'fortnightly' })
    code, out = run_cli(['validate'])
    expect(code).to eq(1)
    expect(out).to include('invalid schedule')
  end

  it 'validate passes a valid config' do
    boot_with('t' => { 'command' => 'echo hi' })
    code, out = run_cli(['validate'])
    expect(code).to eq(0)
    expect(out).to include('valid')
  end

  it 'config path prints the configured path' do
    boot_with({})
    code, out = run_cli(%w[config path])
    expect(code).to eq(0)
    expect(out.strip).to eq(@config_path)
  end

  it 'list shows task rows' do
    boot_with('backup' => { 'command' => 'echo hi', 'schedule' => 'daily', 'time' => '02:00' })
    code, out = run_cli(['list'])
    expect(code).to eq(0)
    expect(out).to match(/TASK\s+STATUS\s+SCHEDULE/)
    expect(out).to match(/backup\s+enabled\s+daily 02:00/)
  end
end
