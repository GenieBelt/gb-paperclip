# frozen_string_literal: true

$LOAD_PATH.push File.expand_path('lib', __dir__)

# Maintain your gem's version:
require 'gb_paperclip/version'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = 'gb_paperclip'
  s.version     = GBPaperclip::VERSION
  s.authors     = ['Kacper Kawecki']
  s.email       = ['kacper@letsbuild.com']
  s.homepage    = 'https://github.com/letsbuilders/gb-paperclip'
  s.summary     = 'GenieBelt Paperclip extensions'
  s.description = 'Extensions for paperclip'
  s.license     = 'GPL-2.0-or-later'

  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.files         = `git ls-files lib`.split("\n") + ['README.md']
  s.executables   = `git ls-files -- bin/*`.split("\n").map { |f| File.basename(f) }
  s.require_paths = ['lib']
  s.metadata['allowed_push_host'] = 'https://rubygems.pkg.github.com/letsbuilders'
  s.metadata['github_repo'] = 'ssh://github.com/letsbuilders/gb-paperclip'

  s.required_ruby_version = '>= 3.0.0'

  s.add_runtime_dependency 'gb_dispatch', '>=0.1.1'
  s.add_runtime_dependency 'kt-paperclip', '>=6.0'
  s.add_development_dependency('activerecord', '>=7.0')
  s.add_development_dependency('appraisal')
  s.add_development_dependency('aws-sdk-core')
  s.add_development_dependency('aws-sdk-glacier')
  s.add_development_dependency('aws-sdk-s3')
  s.add_development_dependency('bourne')
  s.add_development_dependency('bundler')
  s.add_development_dependency('fakeweb')
  s.add_development_dependency('fog', '~> 2.0')
  s.add_development_dependency('generator_spec')
  s.add_development_dependency('launchy')
  s.add_development_dependency('nokogiri')
  s.add_development_dependency('railties')
  s.add_development_dependency('rake')
  s.add_development_dependency('rspec', '>=3.0.0')
  s.add_development_dependency('rspec-mocks', '>=3.0.0')
  s.add_development_dependency('rubocop')
  s.add_development_dependency('rubyzip')
  s.add_development_dependency('shoulda')
  s.add_development_dependency('simplecov')
  s.add_development_dependency('sqlite3')
  s.add_development_dependency('timecop')
end
