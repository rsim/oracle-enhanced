require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

describe "OracleEnhancedConnection create connection" do

  before(:all) do
    @conn = ActiveRecord::ConnectionAdapters::OracleEnhancedConnection.create(CONNECTION_PARAMS)
  end
  
  before(:each) do
    @conn = ActiveRecord::ConnectionAdapters::OracleEnhancedConnection.create(CONNECTION_PARAMS) unless @conn.active?
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

if defined?(RUBY_ENGINE) && RUBY_ENGINE == 'jruby'

  describe "OracleEnhancedConnection create JDBC connection" do
    after(:each) do
      @conn.logoff if @conn.active?
    end

    it "should create new connection using :url" do
      params = CONNECTION_PARAMS.dup
      params[:url] = "jdbc:oracle:thin:@#{DATABASE_HOST}:#{DATABASE_PORT}:#{DATABASE_NAME}"
      params[:host] = nil
      params[:database] = nil
      @conn = ActiveRecord::ConnectionAdapters::OracleEnhancedConnection.create(params)
      @conn.should be_active
    end

    it "should create new connection using :url and tnsnames alias" do
      params = CONNECTION_PARAMS.dup
      params[:url] = "jdbc:oracle:thin:@#{DATABASE_NAME}"
      params[:host] = nil
      params[:database] = nil
      @conn = ActiveRecord::ConnectionAdapters::OracleEnhancedConnection.create(params)
      @conn.should be_active
    end

    it "should create new connection using just tnsnames alias" do
      params = CONNECTION_PARAMS.dup
      params[:host] = nil
      @conn = ActiveRecord::ConnectionAdapters::OracleEnhancedConnection.create(params)
      @conn.should be_active
    end

  end

end

describe "OracleEnhancedConnection SQL execution" do

  before(:all) do
    @conn = ActiveRecord::ConnectionAdapters::OracleEnhancedConnection.create(CONNECTION_PARAMS)
  end
  
  before(:each) do
    @conn = ActiveRecord::ConnectionAdapters::OracleEnhancedConnection.create(CONNECTION_PARAMS) unless @conn.active?
  end

  after(:all) do
    @conn.logoff if @conn.active?
  end

  it "should execute SQL statement" do
    @conn.exec("SELECT * FROM dual").should_not be_nil
  end

  it "should execute SQL select" do
    @conn.select("SELECT * FROM dual").should == [{'dummy' => 'X'}]
  end

  it "should execute SQL select and return also columns" do
    @conn.select("SELECT * FROM dual", nil, true).should == [ [{'dummy' => 'X'}], ['dummy'] ]
  end

end

describe "OracleEnhancedConnection auto reconnection" do

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection.instance_variable_get("@connection")
    @sys_conn = ActiveRecord::ConnectionAdapters::OracleEnhancedConnection.create(SYS_CONNECTION_PARAMS)
  end
  
  before(:each) do
    ActiveRecord::Base.connection.reconnect! unless @conn.active?
  end

  after(:all) do
    ActiveRecord::Base.connection.disconnect! if @conn.active?
  end

  def kill_current_session
    audsid = @conn.select("SELECT userenv('sessionid') audsid FROM dual").first['audsid']
    sid_serial = @sys_conn.select("SELECT s.sid||','||s.serial# sid_serial
        FROM   v$session s
        WHERE  audsid = '#{audsid}'").first['sid_serial']
    @sys_conn.exec "ALTER SYSTEM KILL SESSION '#{sid_serial}' IMMEDIATE"
  end

  it "should reconnect and execute SQL statement if connection is lost and auto retry is enabled" do
    # @conn.auto_retry = true
    ActiveRecord::Base.connection.auto_retry = true
    kill_current_session
    @conn.exec("SELECT * FROM dual").should_not be_nil
  end

  it "should not reconnect and execute SQL statement if connection is lost and auto retry is disabled" do
    # @conn.auto_retry = false
    ActiveRecord::Base.connection.auto_retry = false
    kill_current_session
    lambda { @conn.exec("SELECT * FROM dual") }.should raise_error
  end

  it "should reconnect and execute SQL select if connection is lost and auto retry is enabled" do
    # @conn.auto_retry = true
    ActiveRecord::Base.connection.auto_retry = true
    kill_current_session
    @conn.select("SELECT * FROM dual").should == [{'dummy' => 'X'}]
  end

  it "should not reconnect and execute SQL select if connection is lost and auto retry is disabled" do
    # @conn.auto_retry = false
    ActiveRecord::Base.connection.auto_retry = false
    kill_current_session
    lambda { @conn.select("SELECT * FROM dual") }.should raise_error
  end

end

describe "OracleEnhancedConnection describe table" do

  before(:all) do
    @conn = ActiveRecord::ConnectionAdapters::OracleEnhancedConnection.create(CONNECTION_PARAMS)
    @owner = CONNECTION_PARAMS[:username].upcase
  end
  
  after(:all) do
    @conn.logoff if @conn.active?
  end

  it "should describe existing table" do
    @conn.exec "CREATE TABLE test_employees (first_name VARCHAR2(20))" rescue nil
    @conn.describe("test_employees").should == [@owner, "TEST_EMPLOYEES"]
    @conn.exec "DROP TABLE test_employees" rescue nil
  end

  it "should not describe non-existing table" do
    lambda { @conn.describe("test_xxx") }.should raise_error(ActiveRecord::ConnectionAdapters::OracleEnhancedConnectionException)
  end

  it "should describe table in other schema" do
    @conn.describe("sys.dual").should == ["SYS", "DUAL"]
  end

  it "should describe existing view" do
    @conn.exec "CREATE TABLE test_employees (first_name VARCHAR2(20))" rescue nil
    @conn.exec "CREATE VIEW test_employees_v AS SELECT * FROM test_employees" rescue nil
    @conn.describe("test_employees_v").should == [@owner, "TEST_EMPLOYEES_V"]
    @conn.exec "DROP VIEW test_employees_v" rescue nil
    @conn.exec "DROP TABLE test_employees" rescue nil
  end

  it "should describe view in other schema" do
    @conn.describe("sys.v_$version").should == ["SYS", "V_$VERSION"]
  end

  it "should describe existing private synonym" do
    @conn.exec "CREATE SYNONYM test_dual FOR sys.dual" rescue nil
    @conn.describe("test_dual").should == ["SYS", "DUAL"]
    @conn.exec "DROP SYNONYM test_dual" rescue nil
  end

  it "should describe existing public synonym" do
    @conn.describe("all_tables").should == ["SYS", "ALL_TABLES"]
  end

end