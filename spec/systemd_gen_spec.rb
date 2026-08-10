RSpec.describe Do::UnitGenerator do
  def task(**over)
    Do::Task.new(name: 'backup', command: '/bin/restic backup /x',
                 schedule: 'daily', time: '02:00', **over)
  end

  describe '.service_content' do
    it 'includes the managed marker and source path' do
      content = described_class.service_content(task, source_path: '/cfg.toml')
      expect(content).to include('Managed by do')
      expect(content).to include('# Source: /cfg.toml')
    end

    it 'writes the ExecStart command directly' do
      content = described_class.service_content(task)
      expect(content).to include('ExecStart=/bin/restic backup /x')
    end

    it 'includes WorkingDirectory when set' do
      content = described_class.service_content(task(working_directory: '/tmp'))
      expect(content).to include('WorkingDirectory=/tmp')
    end

    it 'emits Environment lines for each variable' do
      content = described_class.service_content(task(environment: { 'A' => '1', 'B' => 'two' }))
      expect(content).to include('Environment=A=1')
      expect(content).to include('Environment=B=two')
    end
  end

  describe '.timer_content' do
    it 'includes the managed marker' do
      expect(described_class.timer_content(task)).to include('Managed by do')
    end

    it 'uses OnCalendar for real schedules' do
      expect(described_class.timer_content(task))
        .to include('OnCalendar=*-*-* 02:00:00')
    end

    it 'adds Persistent for repeating schedules' do
      expect(described_class.timer_content(task)).to include('Persistent=true')
    end

    it 'uses OnActiveSec for once schedules and omits Persistent' do
      content = described_class.timer_content(task(schedule: 'once'))
      expect(content).to include('OnActiveSec=0')
      expect(content).not_to include('Persistent')
    end
  end
end
