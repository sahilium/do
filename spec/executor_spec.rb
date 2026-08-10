RSpec.describe Do::Executor do
  def task(**over)
    Do::Task.new(**{ name: "t", command: "ruby -e 'exit 7'" }.merge(over))
  end

  def workdir
    d = File.join(@tmpdir, "wd")
    Dir.mkdir(d)
    d
  end

  it "returns the process exit status" do
    executor = Do::Executor.new
    expect(executor.run(task(command: "ruby -e 'exit 7'"))).to eq(7)
    expect(executor.run(task(command: "ruby -e 'exit 0'"))).to eq(0)
  end

  it "runs from the configured working directory" do
    wd = workdir
    marker = File.join(@tmpdir, "out.txt")
    cmd = "ruby -e 'File.write(ARGV[0], Dir.pwd)' #{marker}"
    expect(Do::Executor.new.run(task(command: cmd, working_directory: wd))).to eq(0)
    expect(File.read(marker)).to eq(wd)
  end

  it "passes environment variables to the child" do
    marker = File.join(@tmpdir, "env.txt")
    cmd = %(ruby -e 'File.write(ARGV[0], ENV.fetch("GREETING", "UNSET"))' ) + marker
    expect(Do::Executor.new.run(task(command: cmd, environment: { "GREETING" => "hello" }))).to eq(0)
    expect(File.read(marker)).to eq("hello")
  end

  it "raises for an empty command" do
    expect { Do::Executor.new.run(task(command: "   ")) }
      .to raise_error(Do::Error, /empty command/)
  end

  it "raises for a missing executable" do
    expect { Do::Executor.new.run(task(command: "/no/such/binary")) }
      .to raise_error(Errno::ENOENT)
  end
end