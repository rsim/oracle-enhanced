require File.dirname(__FILE__) + '/../../spec_helper.rb'

describe "OracleEnhancedConnection create connection" do

  before(:all) do
    @config = {
      :adapter => "oracle_enhanced",
      :database => "xe",
      :username => "hr",
      :password => "hr"
    }
    @conn = ActiveRecord::ConnectionAdapters::OracleEnhancedConnection.create(@config)
  end
  
  before(:each) do
    @conn = ActiveRecord::ConnectionAdapters::OracleEnhancedConnection.create(@config) unless @conn.active?
  end

  after(:all) do
    @conn.logoff if @conn.active?
  end

  it "should create new connection" do
    @conn.should be_active
  end

  it "should ping active connection" do
    @conn.ping.should be_true
  end

  it "should not ping inactive connection" do
    @conn.logoff
    lambda { @conn.ping }.should raise_error(ActiveRecord::ConnectionAdapters::OracleEnhancedConnectionException)
  end

  it "should reset active connection" do
    @conn.reset!
    @conn.should be_active
  end

  it "should be in autocommit mode after connection" do
    @conn.should be_autocommit
  end

end

describe "OracleEnhancedConnection SQL execution" do

  before(:all) do
    @config = {
      :adapter => "oracle_enhanced",
      :database => "xe",
      :username => "hr",
      :password => "hr"
    }
    @conn = ActiveRecord::ConnectionAdapters::OracleEnhancedConnection.create(@config)
  end
  
  before(:each) do
    @conn = ActiveRecord::ConnectionAdapters::OracleEnhancedConnection.create(@config) unless @conn.active?
  end

  after(:all) do
    @conn.logoff if @conn.active?
  end

  it "should execute SQL statement" do
    @conn.exec("SELECT * FROM dual").should_not be_nil
  end

end