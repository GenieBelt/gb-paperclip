class FakeRails
  # Mock Rails version 4 for ActiveRecord connection handling
  module VERSION
    MAJOR = 4
  end

  cattr_accessor :env, :root

  attr_accessor :env, :root

  def const_defined?(const)
    false
  end
end

# Mock ActiveRecord::Base.clear_active_connections! for Rails 4
class ActiveRecord::Base
  def self.clear_active_connections!
    ActiveRecord::Base.connection_handler.clear_active_connections!
  end
end
