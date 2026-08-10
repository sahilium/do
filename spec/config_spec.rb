RSpec.describe Do::Config do
  describe '.default_path' do
    around do |ex|
      old_home = Dir.home
      old_cfg = ENV.fetch('XDG_CONFIG_HOME', nil)
      ENV.delete('XDG_CONFIG_HOME')
      ENV['HOME'] = '/home/testuser'
      ex.run
    ensure
      ENV['HOME'] = old_home
      ENV['XDG_CONFIG_HOME'] = old_cfg
    end

    it 'uses ~/.config/do/config.toml when XDG_CONFIG_HOME is unset' do
      expect(described_class.default_path).to eq('/home/testuser/.config/do/config.toml')
    end

    it 'honors XDG_CONFIG_HOME' do
      ENV['XDG_CONFIG_HOME'] = '/custom/config'
      expect(described_class.default_path).to eq('/custom/config/do/config.toml')
    end
  end

  describe '.parse' do
    it 'parses a valid task table' do
      config = described_class.parse(<<~TOML)
        [tasks.backup]
        command = "restic backup ~/Documents"
        schedule = "daily"
        time = "02:00"
        enabled = true
      TOML

      task = config.task('backup')
      expect(task).not_to be_nil
      expect(task.command).to eq('restic backup ~/Documents')
      expect(task.schedule).to eq('daily')
      expect(task.time).to eq('02:00')
      expect(task).to be_enabled
    end

    it 'parses nested environment tables' do
      config = described_class.parse(<<~TOML)
        [tasks.report]
        command = "/bin/report"
        [tasks.report.environment]
        FORMAT = "markdown"
      TOML
      expect(config.task('report').environment).to eq('FORMAT' => 'markdown')
    end

    it 'returns an empty task set when no tasks key exists' do
      expect(described_class.parse('other = 1').tasks).to eq([])
    end

    it 'raises a ValidationError on malformed TOML' do
      expect do
        described_class.parse("[tasks\nbroken")
      end.to raise_error(Do::ValidationError, /Malformed TOML/)
    end
  end

  describe '#set_task_field' do
    it 'edits an existing field in place' do
      path = write_config('backup' => { 'command' => 'echo hi', 'enabled' => true })
      config = described_class.load(path)
      config.set_task_field('backup', 'enabled', 'false')

      reloaded = described_class.load(path)
      expect(reloaded.task('backup').enabled?).to be(false)
    end

    it 'inserts a missing field without disturbing other tasks' do
      path = write_config(
        'backup' => { 'command' => 'echo hi', 'schedule' => 'daily' },
        'other' => { 'command' => 'echo other' }
      )
      config = described_class.load(path)
      config.set_task_field('backup', 'enabled', 'true')

      text = File.read(path)
      expect(text).to include('[tasks.backup]')
      expect(text).to include('enabled = true')
      expect(described_class.load(path).task('other')).not_to be_nil
    end
  end

  describe '#remove_task' do
    it 'removes the task table and its nested tables' do
      path = write_config('report' => { 'command' => '/bin/report', 'schedule' => 'monthly' })
      text = File.read(path)
      text << "  [tasks.report.environment]\n  FORMAT = \"x\"\n"
      File.write(path, text)

      config = described_class.load(path)
      config.remove_task('report')

      expect(described_class.load(path).task('report')).to be_nil
      expect(described_class.load(path).tasks).to eq([])
    end
  end
end
