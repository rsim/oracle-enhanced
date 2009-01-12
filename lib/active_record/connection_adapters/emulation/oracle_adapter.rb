class ActiveRecord::ConnectionAdapters::OracleAdapter < ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter
  def adapter_name
    'Oracle'
  end
end
