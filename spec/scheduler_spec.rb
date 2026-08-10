RSpec.describe Do::Scheduler do
  def task(**over)
    defaults = { name: 't', command: 'echo hi' }
    Do::Task.new(**defaults, **over)
  end

  describe '.on_calendar' do
    it 'returns nil for manual-only tasks' do
      expect(described_class.on_calendar(task)).to be_nil
    end

    it "emits an immediate one-shot expression for 'once'" do
      expect(described_class.on_calendar(task(schedule: 'once'))).to eq('OnActiveSec=0')
    end

    it 'emits an hourly expression using the minute of the given time' do
      expect(described_class.on_calendar(task(schedule: 'hourly', time: '02:30')))
        .to eq('*-*-* *:30:00')
    end

    it 'defaults hourly to the top of the hour' do
      expect(described_class.on_calendar(task(schedule: 'hourly')))
        .to eq('*-*-* *:00:00')
    end

    it 'emits a daily expression with zero-padded time' do
      expect(described_class.on_calendar(task(schedule: 'daily', time: '02:00')))
        .to eq('*-*-* 02:00:00')
    end

    it 'defaults a daily time to midnight when omitted' do
      expect(described_class.on_calendar(task(schedule: 'daily')))
        .to eq('*-*-* 00:00:00')
    end

    it 'emits a weekly expression with the weekday name' do
      expect(described_class.on_calendar(task(schedule: 'weekly', day: 'sunday', time: '10:00')))
        .to eq('Sun *-*-* 10:00:00')
    end

    it 'emits a monthly expression with a day-of-month' do
      expect(described_class.on_calendar(task(schedule: 'monthly', day: '1', time: '09:00')))
        .to eq('*-*-1 09:00:00')
    end

    it 'rejects an invalid schedule' do
      expect { described_class.on_calendar(task(schedule: 'fortnightly')) }
        .to raise_error(Do::Error, /unsupported schedule/)
    end

    it 'rejects an invalid time' do
      expect { described_class.on_calendar(task(schedule: 'daily', time: '25:73')) }
        .to raise_error(Do::Error, /invalid time/)
    end

    it 'rejects an invalid weekly day' do
      expect { described_class.on_calendar(task(schedule: 'weekly', day: 'funday')) }
        .to raise_error(Do::Error, /invalid day/)
    end

    it 'rejects an invalid monthly day' do
      expect { described_class.on_calendar(task(schedule: 'monthly', day: '32')) }
        .to raise_error(Do::Error, /invalid monthly day/)
    end
  end
end
