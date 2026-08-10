require "open3"

RSpec.describe Do::Systemd do
  # Build a fake systemctl that records all invocations and returns scripted
  # behavior based on the subcommand, so the wrapper can be tested without a
  # real user session.
  def make_fake(rules: {}, log_name: "stack.log")
    bin = File.join(@tmpdir, "fake-systemctl")
    log = File.join(@tmpdir, log_name)
    body = rules.map do |(cmd, behavior)|
      out, err, code = behavior
      out_esc = out.to_s.gsub(/["\\]/) { |c| "\\#{c}" }
      "  if [ \"$2\" = \"#{cmd}\" ]; then printf '%s' #{out_esc.inspect}; exit #{code}; fi"
    end.join("\n")
    File.write(bin, <<~SH)
      #!/bin/sh
      echo "$@" >> #{log}
      cmd="$2"
      #{body}
      exit 0
    SH
    File.chmod(0o755, bin)
    [Do::Systemd.new(systemctl_bin: bin), log]
  end

  describe "#unit_dir" do
    it "defaults to ~/.config/systemd/user" do
      old = ENV["XDG_CONFIG_HOME"]
      ENV["XDG_CONFIG_HOME"] = "/custom"
      expect(Do::Systemd.new.unit_dir).to eq("/custom/systemd/user")
      ENV["XDG_CONFIG_HOME"] = old
    end

    it "falls back to HOME/.config when XDG_CONFIG_HOME is unset" do
      old_home = ENV["HOME"]
      old_cfg = ENV["XDG_CONFIG_HOME"]
      ENV.delete("XDG_CONFIG_HOME")
      ENV["HOME"] = "/home/x"
      expect(Do::Systemd.new.unit_dir).to eq("/home/x/.config/systemd/user")
      ENV["HOME"] = old_home
      ENV["XDG_CONFIG_HOME"] = old_cfg
    end
  end

  describe "#enable" do
    it "runs enable --now with the --user prefix" do
      sd, log, = make_fake(rules: { "enable" => ["", "", 0] })
      sd.enable("do-x.timer")
      expect(File.read(log)).to include("--user enable --now do-x.timer")
    end
  end

  describe "#enabled?" do
    it "returns true when is-enabled succeeds" do
      sd, = make_fake(rules: { "is-enabled" => ["enabled", "", 0] })
      expect(sd.enabled?("do-x.timer")).to be(true)
    end

    it "returns false when is-enabled fails" do
      sd, = make_fake(rules: { "is-enabled" => ["", "", 3] })
      expect(sd.enabled?("do-x.timer")).to be(false)
    end
  end

  describe "#active?" do
    it "reflects is-active success" do
      sd, = make_fake(rules: { "is-active" => ["active", "", 0] })
      expect(sd.active?("do-x.timer")).to be(true)
      sd, = make_fake(rules: { "is-active" => ["", "", 3] })
      expect(sd.active?("do-x.timer")).to be(false)
    end
  end

  describe "#show_prop" do
    it "parses a Property=value line" do
      sd, = make_fake(rules: { "show" => ["NextElapseUSecRealtime=Mon 2026-08-11 02:00:00 IST", "", 0] })
      expect(sd.show_prop("do-x.timer", "NextElapseUSecRealtime"))
        .to eq("Mon 2026-08-11 02:00:00 IST")
    end
  end

  describe "#next_time" do
    it "parses the realtime next-elapse property into a Time" do
      sd, = make_fake(rules: { "show" => ["NextElapseUSecRealtime=Mon 2026-08-11 02:00:00 IST", "", 0] })
      expect(sd.next_time("do-x.timer")).to be_a(Time)
    end

    it "returns nil when the property is empty" do
      sd, = make_fake(rules: { "show" => ["", "", 0] })
      expect(sd.next_time("do-x.timer")).to be_nil
    end
  end

  describe "#logs" do
    it "passes --user -u <unit> and -f when following" do
      log_file = File.join(@tmpdir, "jlog")
      jbin = File.join(@tmpdir, "fake-journalctl")
      File.write(jbin, "#!/bin/sh\necho \"journalctl --user $@\" >> #{log_file}\n")
      File.chmod(0o755, jbin)
      sd = Do::Systemd.new(journalctl_bin: jbin)
      sd.logs("do-x.service", follow: true)
      expect(File.read(log_file)).to include("--user -u do-x.service --no-pager -f")
    end
  end
end