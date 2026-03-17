# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'
require 'rubygems'
require 'rspec'
require 'active_record'
require 'active_record/version'
require 'active_support'
require 'active_support/core_ext'
require 'mocha/api'
require 'bourne'
require 'ostruct'
require 'simplecov'
require 'gb_dispatch'
require 'aws-sdk-s3'
require 'aws-sdk-glacier'

SimpleCov.start do
  add_filter '/spec/'
  add_group 'Library core', %w(lib\/[^\/]*\.rb lib\/gb_paperclip\/[^\/]*\.rb)
  add_group 'Paperclip extensions', 'lib\/gb_paperclip\/paperclip\/[^\/]*\.rb'
  add_group 'IO Adapters', 'lib/gb_paperclip/paperclip/io_adapters'
  add_group 'Validators', 'lib/gb_paperclip/paperclip/validators'
  add_group 'Storage', 'lib/gb_paperclip/paperclip/storage'
end

SimpleCov.minimum_coverage 78

ROOT = Pathname(File.expand_path(File.join(File.dirname(__FILE__), '..')))

puts "Testing against version #{ActiveRecord::VERSION::STRING}"

$LOAD_PATH << File.join(ROOT, 'lib')
$LOAD_PATH << File.join(ROOT, 'lib', 'gb_paperclip')
require File.join(ROOT, 'lib', 'gb_paperclip.rb')

if ActiveRecord::VERSION::MAJOR == 7 && ActiveRecord::VERSION::MINOR < 2
  require 'active_record/connection_adapters/sqlite3_adapter'
  module ActiveRecord
    module ConnectionHandling
      def sqlite3_connection(config)
        config = config.symbolize_keys
        raise ArgumentError, 'No database file specified. Missing argument: database' unless config[:database]
        unless config[:database] =~ /:memory/
          config[:database] = File.expand_path(config[:database], Rails.root) if defined?(Rails.root)
          dirname = File.dirname(config[:database])
          Dir.mkdir(dirname) unless File.directory?(dirname)
        end
        db = SQLite3::Database.new(
          config[:database].to_s,
          results_as_hash: true,
          flags: SQLite3::Constants::Open::READWRITE |
                 SQLite3::Constants::Open::CREATE    |
                 SQLite3::Constants::Open::URI
        )
        if config[:timeout]
          db.busy_timeout(ConnectionAdapters::SQLite3Adapter.type_cast_config_to_integer(config[:timeout]))
        end
        ConnectionAdapters::SQLite3Adapter.new(db, logger, nil, config)
      rescue Errno::ENOENT => e
        if e.message.include?('No such file or directory')
          raise ActiveRecord::NoDatabaseError
        else
          raise
        end
      end
    end
  end
end

require 'gb_dispatch/active_record_patch'

FIXTURES_DIR              = File.join(File.dirname(__FILE__), 'fixtures')
ActiveRecord::Base.logger = Logger.new("#{File.dirname(__FILE__)}/debug.log")
ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: 'file::memory:?cache=shared', pool: 5)

GBDispatch.logger = Logger.new($stdout)
Paperclip.options[:logger] = ActiveRecord::Base.logger
Paperclip::DataUriAdapter.register
Paperclip::UriAdapter.register
Paperclip::HttpUrlProxyAdapter.register

Dir[File.join(ROOT, 'spec', 'support', '**', '*.rb')].sort.each { |f| require f }

RSpec.configure do |config|
  config.include Assertions
  config.include ModelReconstruction
  config.include TestData
  config.extend VersionHelper
  config.extend RailsHelpers::ClassMethods
  config.include Reporting
  config.mock_framework = :rspec
  config.before(:all) do
    FileUtils.mkdir_p Pathname.new(ROOT).join('tmp')
    rebuild_model
  end
  config.after(:each) do
    ActiveRecord::Base.connection_handler.clear_reloadable_connections!
  end
  config.after(:all) do
    FileUtils.rm_r Pathname.new(ROOT).join('tmp')
  end

  Aws.config.update({
                      region: 'us-west-2',
                      credentials: Aws::Credentials.new('ak_id', 'secret')
                    })
end
