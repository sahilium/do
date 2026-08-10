require_relative 'lib/do/version'

Gem::Specification.new do |spec|
  spec.name          = 'do'
  spec.version       = Do::VERSION
  spec.authors       = ['do contributors']
  spec.summary       = 'Declarative Linux execution layer backed by systemd user services and timers.'
  spec.description   = 'do is a declarative execution layer for Linux. It translates a small TOML ' \
                       'configuration into systemd user services and timers, giving you a friendly ' \
                       'control plane without reinventing scheduling.'
  spec.homepage      = 'https://sahil.im./tools/do'
  spec.license       = 'GPL-3.0'
  spec.required_ruby_version = '>= 3.1'

  spec.files         = Dir['lib/**/*.rb', 'bin/*', 'README.md', 'CHANGELOG.md', 'LICENSE']
  spec.bindir        = 'bin'
  spec.executables   = ['do']
  spec.require_paths = ['lib']

  spec.add_dependency 'thor', '~> 1.3'
  spec.add_dependency 'toml-rb', '~> 4.2'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
