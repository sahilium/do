require "fileutils"

RSpec.describe Do::Manager do
  def fake_systemctl
    bin = File.join(@tmpdir, "fake-systemctl")
    log = File.join(@tmpdir, "calls.log")
    File.write(bin, <<~SH)
      #!/bin/sh
      echo "$@" >> #{log}
      exit 0
    SH
    File.chmod(0o755, bin)
    [bin, log]
  end

  around(:each) do |example|
    old_cfg = ENV["XDG_CONFIG_HOME"]
    ENV["XDG_CONFIG_HOME"] = @tmpdir
    example.run
  ensure
    ENV["XDG_CONFIG_HOME"] = old_cfg
  end

  def config_for(path)
    Do::Config.load(path)
  end

  it "writes service and timer units for scheduled tasks" do
    path = write_config(
      "backup" => { "command" => "/bin/echo backup", "schedule" => "daily", "time" => "02:00" }
    )
    bin, = fake_systemctl
    manager = Do::Manager.new(systemd: Do::Systemd.new(systemctl_bin: bin), config: config_for(path))

    manager.reload

    unit_dir = File.join(@tmpdir, "systemd", "user")
    expect(File.exist?(File.join(unit_dir, "do-backup.service"))).to be(true)
    expect(File.exist?(File.join(unit_dir, "do-backup.timer"))).to be(true)
    expect(File.read(File.join(unit_dir, "do-backup.timer"))).to include("OnCalendar=*-*-* 02:00:00")
  end

  it "does not write timer units for manual-only tasks" do
    path = write_config("cleanup" => { "command" => "/bin/echo clean" })
    bin, = fake_systemctl
    manager = Do::Manager.new(systemd: Do::Systemd.new(systemctl_bin: bin), config: config_for(path))
    manager.reload

    unit_dir = File.join(@tmpdir, "systemd", "user")
    expect(File.exist?(File.join(unit_dir, "do-cleanup.timer"))).to be(false)
    expect(File.exist?(File.join(unit_dir, "do-cleanup.service"))).to be(false)
  end

  it "removes stale do-managed units that are no longer expected" do
    path = write_config("keep" => { "command" => "/bin/echo keep", "schedule" => "daily" })
    unit_dir = File.join(@tmpdir, "systemd", "user")
    FileUtils.mkdir_p(unit_dir)
    File.write(File.join(unit_dir, "do-gone.service"), "# Managed by do\n[Service]\n")
    File.write(File.join(unit_dir, "do-gone.timer"), "# Managed by do\n[Timer]\n")
    # A user-created unit that must never be touched.
    File.write(File.join(unit_dir, "my-own.service"), "[Service]\n")

    bin, = fake_systemctl
    manager = Do::Manager.new(systemd: Do::Systemd.new(systemctl_bin: bin), config: config_for(path))
    manager.reload

    expect(File.exist?(File.join(unit_dir, "do-gone.service"))).to be(false)
    expect(File.exist?(File.join(unit_dir, "do-gone.timer"))).to be(false)
    expect(File.exist?(File.join(unit_dir, "my-own.service"))).to be(true)
  end

  it "enables timers for enabled scheduled tasks" do
    path = write_config(
      "backup" => { "command" => "/bin/echo backup", "schedule" => "daily", "enabled" => true }
    )
    bin, log, = fake_systemctl
    manager = Do::Manager.new(systemd: Do::Systemd.new(systemctl_bin: bin), config: config_for(path))
    manager.reload
    expect(File.read(log)).to include("enable --now do-backup.timer")
  end

  it "disables timers for disabled scheduled tasks" do
    path = write_config(
      "backup" => { "command" => "/bin/echo backup", "schedule" => "daily", "enabled" => false }
    )
    bin, log, = fake_systemctl
    manager = Do::Manager.new(systemd: Do::Systemd.new(systemctl_bin: bin), config: config_for(path))
    manager.reload
    expect(File.read(log)).to include("disable --now do-backup.timer")
  end

  it "refuses to reload when the configuration is invalid" do
    path = write_config("t" => { "schedule" => "fortnightly" })
    bin, = fake_systemctl
    manager = Do::Manager.new(systemd: Do::Systemd.new(systemctl_bin: bin), config: config_for(path))
    expect { manager.reload }.to raise_error(Do::ValidationError, /invalid schedule/)
  end

  it "unschedule removes the task's units" do
    path = write_config("keep" => { "command" => "x", "schedule" => "daily" })
    bin, = fake_systemctl
    sd = Do::Systemd.new(systemctl_bin: bin)
    manager = Do::Manager.new(systemd: sd, config: config_for(path))
    manager.reload
    unit_dir = File.join(@tmpdir, "systemd", "user")

    task = config_for(path).task("keep")
    manager.unschedule(task)
    expect(File.exist?(File.join(unit_dir, "do-keep.timer"))).to be(false)
    expect(File.exist?(File.join(unit_dir, "do-keep.service"))).to be(false)
  end
end