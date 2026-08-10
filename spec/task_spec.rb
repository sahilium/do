RSpec.describe Do::Task do
  def task(**over)
    defaults = { name: 't', command: 'echo hi' }
    described_class.new(**defaults, **over)
  end

  describe 'factory defaults' do
    it 'defaults enabled to true for scheduled tasks' do
      expect(task(schedule: 'daily')).to be_enabled
    end

    it 'defaults enabled to false for manual-only tasks' do
      expect(task).not_to be_enabled
    end

    it 'lets an explicit enabled value win' do
      expect(task(enabled: false, schedule: 'daily')).not_to be_enabled
      expect(task(enabled: true)).to be_enabled
    end
  end

  describe '#scheduled?' do
    it 'is true when a schedule is present' do
      expect(task(schedule: 'weekly')).to be_scheduled
    end

    it 'is false when schedule is nil or empty' do
      expect(task).not_to be_scheduled
      expect(task(schedule: '')).not_to be_scheduled
    end
  end

  describe 'unit names' do
    it 'derives predictable service and timer names' do
      t = task(name: 'backup')
      expect(t.service_unit).to eq('do-backup.service')
      expect(t.timer_unit).to eq('do-backup.timer')
    end
  end
end
