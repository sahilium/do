RSpec.describe Do::Validator do
  def config(toml)
    Do::Config.parse(toml)
  end

  def errors_for(toml)
    Do::Validator.validate(config(toml))
  end

  it 'accepts a minimal valid task' do
    expect(errors_for("[tasks.t]\ncommand = \"echo hi\"")).to eq([])
  end

  it 'flags a missing required command' do
    expect(errors_for("[tasks.t]\nschedule = \"daily\""))
      .to include(include("missing required field 'command'"))
  end

  it 'flags an invalid schedule' do
    expect(errors_for("[tasks.t]\ncommand = \"x\"\nschedule = \"fortnightly\""))
      .to include(include('invalid schedule'))
  end

  it 'flags an invalid time' do
    expect(errors_for("[tasks.t]\ncommand = \"x\"\nschedule = \"daily\"\ntime = \"25:73\""))
      .to include(include('invalid time'))
  end

  it 'flags an invalid weekly day' do
    expect(errors_for("[tasks.t]\ncommand = \"x\"\nschedule = \"weekly\"\nday = \"funday\""))
      .to include(include('invalid day'))
  end

  it 'flags an invalid monthly day' do
    expect(errors_for("[tasks.t]\ncommand = \"x\"\nschedule = \"monthly\"\nday = \"32\""))
      .to include(include('invalid monthly day'))
  end

  it 'flags unsupported task fields' do
    expect(errors_for("[tasks.t]\ncommand = \"x\"\nbogus = \"y\""))
      .to include(include("unsupported field 'bogus'"))
  end

  it 'flags a nonexistent working directory' do
    expect(errors_for("[tasks.t]\ncommand = \"x\"\nworking_directory = \"/no/such/dir/xyz\""))
      .to include(match(/working directory .* does not exist/))
  end

  it 'flags non-string environment values' do
    expect(errors_for("[tasks.t]\ncommand = \"x\"\n[tasks.t.environment]\nK = 5"))
      .to include(include('must map strings to strings'))
  end

  it 'flags invalid unit names' do
    expect(errors_for("[tasks.\"bad name\"]\ncommand = \"x\""))
      .to include(include('not a valid systemd unit name'))
  end

  it 'does not raise when valid via validate!' do
    expect { described_class.validate!(config("[tasks.t]\ncommand = \"x\"")) }.not_to raise_error
  end
end
