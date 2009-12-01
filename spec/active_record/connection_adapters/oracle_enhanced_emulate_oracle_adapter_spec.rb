require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

describe "OracleEnhancedAdapter emulate OracleAdapter" do

  before(:all) do
    if defined?(ActiveRecord::ConnectionAdapters::OracleAdapter)
      @old_oracle_adapter = ActiveRecord::ConnectionAdapters::OracleAdapter
      ActiveRecord::ConnectionAdapters.send(:remove_const, :OracleAdapter)
    end
  end

  it "should be an OracleAdapter" do
    @conn = ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(:emulate_oracle_adapter => true))
    ActiveRecord::Base.connection.should_not be_nil
    ActiveRecord::Base.connection.is_a?(ActiveRecord::ConnectionAdapters::OracleAdapter).should be_true
  end

  after(:all) do
    if @old_oracle_adapter
      ActiveRecord::ConnectionAdapters.send(:remove_const, :OracleAdapter)
      ActiveRecord::ConnectionAdapters::OracleAdapter = @old_oracle_adapter
    end
  end

end
