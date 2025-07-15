# frozen_string_literal: true

describe "OracleEnhancedAdapter establish connection" do
  it "should connect to database" do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    expect(ActiveRecord::Base.connection).not_to be_nil
    expect(ActiveRecord::Base.connection.class).to eq(ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter)
  end

  it "should connect to database as SYSDBA" do
    ActiveRecord::Base.establish_connection(SYS_CONNECTION_PARAMS)
    expect(ActiveRecord::Base.connection).not_to be_nil
    expect(ActiveRecord::Base.connection.class).to eq(ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter)
  end

  it "should be active after connection to database" do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    expect(ActiveRecord::Base.connection).to be_active
  end

  it "should not be active after disconnection to database" do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    ActiveRecord::Base.connection.disconnect!
    expect(ActiveRecord::Base.connection).not_to be_active
  end

  it "should be active after reconnection to database" do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    ActiveRecord::Base.connection.reconnect!
    expect(ActiveRecord::Base.connection).to be_active
  end

  it "should be active after reconnection to database with restore_transactions: true" do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    ActiveRecord::Base.connection.reconnect!(restore_transactions: true)
    expect(ActiveRecord::Base.connection).to be_active
  end

  it "should use database default cursor_sharing parameter value force by default" do
    # Use `SYSTEM_CONNECTION_PARAMS` to query v$parameter
    ActiveRecord::Base.establish_connection(SYSTEM_CONNECTION_PARAMS)
    expect(ActiveRecord::Base.connection.select_value("select value from v$parameter where name = 'cursor_sharing'")).to eq("FORCE")
  end

  it "should use modified cursor_sharing value exact" do
    ActiveRecord::Base.establish_connection(SYSTEM_CONNECTION_PARAMS.merge(cursor_sharing: :exact))
    expect(ActiveRecord::Base.connection.select_value("select value from v$parameter where name = 'cursor_sharing'")).to eq("EXACT")
  end

  it "should not use JDBC statement caching" do
    if ORACLE_ENHANCED_CONNECTION == :jdbc
      ActiveRecord::Base.establish_connection(SYSTEM_CONNECTION_PARAMS)
      expect(ActiveRecord::Base.connection.raw_connection.getImplicitCachingEnabled).to be(false)
      expect(ActiveRecord::Base.connection.raw_connection.getStatementCacheSize).to eq(-1)
    end
  end

  it "should use JDBC statement caching" do
    if ORACLE_ENHANCED_CONNECTION == :jdbc
      ActiveRecord::Base.establish_connection(SYSTEM_CONNECTION_PARAMS.merge(jdbc_statement_cache_size: 100))
      expect(ActiveRecord::Base.connection.raw_connection.getImplicitCachingEnabled).to be(true)
      expect(ActiveRecord::Base.connection.raw_connection.getStatementCacheSize).to eq(100)
      # else: don't raise error if OCI connection has parameter "jdbc_statement_cache_size", still ignore it
    end
  end

  it "should not encrypt JDBC network connection" do
    if ORACLE_ENHANCED_CONNECTION == :jdbc
      @conn = ActiveRecord::Base.establish_connection(SYSTEM_CONNECTION_PARAMS.merge(jdbc_connect_properties: { "oracle.net.encryption_client" => "REJECTED" }))
      expect(@conn.select("SELECT COUNT(*) Records FROM v$Session_Connect_Info WHERE SID=SYS_CONTEXT('USERENV', 'SID') AND Network_Service_Banner LIKE '%Encryption service adapter%'")).to eq([{ "records" => 0 }])
    end
  end

  it "should encrypt JDBC network connection" do
    if ORACLE_ENHANCED_CONNECTION == :jdbc
      @conn = ActiveRecord::Base.establish_connection(SYSTEM_CONNECTION_PARAMS.merge(jdbc_connect_properties: { "oracle.net.encryption_client" => "REQUESTED" }))
      expect(@conn.select("SELECT COUNT(*) Records FROM v$Session_Connect_Info WHERE SID=SYS_CONTEXT('USERENV', 'SID') AND Network_Service_Banner LIKE '%Encryption service adapter%'")).to eq([{ "records" => 1 }])
    end
  end

  it "should connect to database using service_name" do
    ActiveRecord::Base.establish_connection(SERVICE_NAME_CONNECTION_PARAMS)
    expect(ActiveRecord::Base.connection).not_to be_nil
    expect(ActiveRecord::Base.connection.class).to eq(ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter)
  end
end

describe "OracleEnhancedConnection" do
  describe "create connection" do
    before(:all) do
      @conn = ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection.create(CONNECTION_PARAMS)
    end

    before(:each) do
      @conn = ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection.create(CONNECTION_PARAMS) unless @conn.active?
    end

    it "should create new connection" do
      expect(@conn).to be_active
    end

    it "should ping active connection" do
      expect(@conn.ping).to be_truthy
    end

    it "should not ping inactive connection" do
      @conn.logoff
      expect { @conn.ping }.to raise_error(ActiveRecord::ConnectionAdapters::OracleEnhanced::ConnectionException)
    end

    it "should reset active connection" do
      @conn.reset!
      expect(@conn).to be_active
    end

    it "should be in autocommit mode after connection" do
      expect(@conn).to be_autocommit
    end
  end

  describe "create connection with schema option" do
    it "should create new connection" do
      ActiveRecord::Base.establish_connection(CONNECTION_WITH_SCHEMA_PARAMS)
      expect(ActiveRecord::Base.connection).to be_active
    end

    it "should switch to specified schema" do
      ActiveRecord::Base.establish_connection(CONNECTION_WITH_SCHEMA_PARAMS)
      expect(ActiveRecord::Base.connection.current_schema).to eq(CONNECTION_WITH_SCHEMA_PARAMS[:schema].upcase)
      expect(ActiveRecord::Base.connection.current_user).to eq(CONNECTION_WITH_SCHEMA_PARAMS[:username].upcase)
    end

    it "should switch to specified schema after reset" do
      ActiveRecord::Base.connection.reset!
      expect(ActiveRecord::Base.connection.current_schema).to eq(CONNECTION_WITH_SCHEMA_PARAMS[:schema].upcase)
    end
  end

  describe "create connection with NLS parameters" do
    after do
      ENV["NLS_TERRITORY"] = nil
    end

    it "should use NLS_TERRITORY environment variable" do
      ENV["NLS_TERRITORY"] = "JAPAN"
      @conn = ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection.create(CONNECTION_PARAMS)
      expect(@conn.select("select SYS_CONTEXT('userenv', 'NLS_TERRITORY') as value from dual")).to eq([{ "value" => "JAPAN" }])
    end

    it "should use configuration value and ignore NLS_TERRITORY environment variable" do
      ENV["NLS_TERRITORY"] = "AMERICA"
      @conn = ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection.create(CONNECTION_PARAMS.merge(nls_territory: "INDONESIA"))
      expect(@conn.select("select SYS_CONTEXT('userenv', 'NLS_TERRITORY') as value from dual")).to eq([{ "value" => "INDONESIA" }])
    end
  end

  describe "Fixed NLS parameters" do
    after do
      ENV["NLS_DATE_FORMAT"] = nil
    end

    it "should ignore NLS_DATE_FORMAT environment variable" do
      ENV["NLS_DATE_FORMAT"] = "YYYY-MM-DD"
      @conn = ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection.create(CONNECTION_PARAMS)
      expect(@conn.select("select SYS_CONTEXT('userenv', 'NLS_DATE_FORMAT') as value from dual")).to eq([{ "value" => "YYYY-MM-DD HH24:MI:SS" }])
    end

    it "should ignore NLS_DATE_FORMAT configuration value" do
      @conn = ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection.create(CONNECTION_PARAMS.merge(nls_date_format: "YYYY-MM-DD HH24:MI"))
      expect(@conn.select("select SYS_CONTEXT('userenv', 'NLS_DATE_FORMAT') as value from dual")).to eq([{ "value" => "YYYY-MM-DD HH24:MI:SS" }])
    end

    it "should use default value when NLS_DATE_FORMAT environment variable is not set" do
      ENV["NLS_DATE_FORMAT"] = nil
      @conn = ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection.create(CONNECTION_PARAMS)
      default = ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter::FIXED_NLS_PARAMETERS[:nls_date_format]
      expect(@conn.select("select SYS_CONTEXT('userenv', 'NLS_DATE_FORMAT') as value from dual")).to eq([{ "value" => default }])
    end
  end

  if defined?(OCI8)
    describe "with TCP keepalive parameters" do
      it "should use database default `tcp_keepalive` value true by default" do
        ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection.create(CONNECTION_PARAMS)

        expect(OCI8.properties[:tcp_keepalive]).to be true
      end

      it "should use modified `tcp_keepalive` value false" do
        ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection.create(CONNECTION_PARAMS.dup.merge(tcp_keepalive: false))

        expect(OCI8.properties[:tcp_keepalive]).to be false
      end

      it "should use database default `tcp_keepalive_time` value 600 by default" do
        ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection.create(CONNECTION_PARAMS)

        expect(OCI8.properties[:tcp_keepalive_time]).to eq(600)
      end

      it "should use modified `tcp_keepalive_time` value 3000" do
        ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection.create(CONNECTION_PARAMS.dup.merge(tcp_keepalive_time: 3000))

        expect(OCI8.properties[:tcp_keepalive_time]).to eq(3000)
      end
    end
  end

  describe "with non-string parameters" do
    before(:all) do
      params = CONNECTION_PARAMS.dup
      params[:username] = params[:username].to_sym
      params[:password] = params[:password].to_sym
      params[:database] = params[:database].to_sym
      @conn = ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection.create(params)
    end

    it "should create new connection" do
      expect(@conn).to be_active
    end
  end

  describe "with slash-prefixed database name (service name)" do
    before(:all) do
      params = CONNECTION_PARAMS.dup
      params[:database] = "/#{params[:database]}" unless params[:database].start_with?("/")
      @conn = ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection.create(params)
    end

    it "should create new connection" do
      expect(@conn).to be_active
    end
  end

  describe "default_timezone" do
    include SchemaSpecHelper

    before(:all) do
      ActiveRecord::Base.establish_connection(CONNECTION_WITH_TIMEZONE_PARAMS)
      schema_define do
        create_table :posts, force: true do |t|
          t.timestamps null: false
        end
      end
      class ::Post < ActiveRecord::Base
      end
    end

    after(:all) do
      Object.send(:remove_const, "Post") if defined?(Post)
      ActiveRecord::Base.clear_cache!
    end

    it "should respect default_timezone = :utc than time_zone setting" do
      # it expects that ActiveRecord.default_timezone = :utc
      ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection.create(CONNECTION_WITH_TIMEZONE_PARAMS)
      post = Post.create!
      created_at = post.created_at
      expect(post).to eq(Post.find_by!(created_at: created_at))
    end
  end

  describe 'with host="connection-string"' do
    let(:username) { CONNECTION_PARAMS[:username] }
    let(:password) { CONNECTION_PARAMS[:password] }
    let(:connection_string) { "(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=tcp)(HOST=#{DATABASE_HOST})(PORT=#{DATABASE_PORT})))(CONNECT_DATA=(SERVICE_NAME=#{DATABASE_NAME})))" }
    let(:params) { { username: username, password: password, host: "connection-string", database: connection_string } }

    it "uses the database param as the connection string" do
      if ORACLE_ENHANCED_CONNECTION == :jdbc
        expect(java.sql.DriverManager).to receive(:getConnection).with("jdbc:oracle:thin:@#{connection_string}", anything).and_call_original
      else
        expect(OCI8).to receive(:new).with(username, password, connection_string, nil).and_call_original
      end
      conn = ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection.create(params)
      expect(conn).to be_active
    end
  end

  if defined?(RUBY_ENGINE) && RUBY_ENGINE == "jruby"

    describe "create JDBC connection" do
      it "should create new connection using :url" do
        params = CONNECTION_PARAMS.dup
        params[:url] = "jdbc:oracle:thin:@#{DATABASE_HOST && "//#{DATABASE_HOST}#{DATABASE_PORT && ":#{DATABASE_PORT}"}/"}#{DATABASE_NAME}"

        params[:host] = nil
        params[:database] = nil
        @conn = ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection.create(params)
        expect(@conn).to be_active
      end

      it "should create new connection using :url and tnsnames alias" do
        params = CONNECTION_PARAMS.dup
        params[:url] = "jdbc:oracle:thin:@#{DATABASE_NAME}"
        params[:host] = nil
        params[:database] = nil
        @conn = ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection.create(params)
        expect(@conn).to be_active
      end

      it "should create new connection using just tnsnames alias" do
        params = CONNECTION_PARAMS.dup
        params[:host] = nil
        @conn = ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection.create(params)
        expect(@conn).to be_active
      end

      it "should create a new connection using JNDI" do
        begin
          import "oracle.jdbc.driver.OracleDriver"
          import "org.apache.commons.pool.impl.GenericObjectPool"
          import "org.apache.commons.dbcp.PoolingDataSource"
          import "org.apache.commons.dbcp.PoolableConnectionFactory"
          import "org.apache.commons.dbcp.DriverManagerConnectionFactory"
        rescue NameError => e
          return skip e.message
        end

        class InitialContextMock
          def initialize
            connection_pool = GenericObjectPool.new(nil)
            uri = "jdbc:oracle:thin:@#{DATABASE_HOST && "#{DATABASE_HOST}:"}#{DATABASE_PORT && "#{DATABASE_PORT}:"}#{DATABASE_NAME}"
            connection_factory = DriverManagerConnectionFactory.new(uri, DATABASE_USER, DATABASE_PASSWORD)
            PoolableConnectionFactory.new(connection_factory, connection_pool, nil, nil, false, true)
            @data_source = PoolingDataSource.new(connection_pool)
            @data_source.access_to_underlying_connection_allowed = true
          end
          def lookup(path)
            if path == "java:/comp/env"
              self
            else
              @data_source
            end
          end
        end

        allow(javax.naming.InitialContext).to receive(:new).and_return(InitialContextMock.new)

        params = {}
        params[:jndi] = "java:comp/env/jdbc/test"
        @conn = ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection.create(params)
        expect(@conn).to be_active
      end
    end

    it "should fall back to directly instantiating OracleDriver" do
      params = CONNECTION_PARAMS.dup
      params[:url] = "jdbc:oracle:thin:@#{DATABASE_HOST && "//#{DATABASE_HOST}#{DATABASE_PORT && ":#{DATABASE_PORT}"}/"}#{DATABASE_NAME}"
      params[:host] = nil
      params[:database] = nil
      allow(java.sql.DriverManager).to receive(:getConnection).and_raise("no suitable driver found")
      @conn = ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection.create(params)
      expect(@conn).to be_active
    end

  end

  describe "SQL execution" do
    before(:all) do
      @conn = ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection.create(CONNECTION_PARAMS)
    end

    it "should execute SQL statement" do
      expect(@conn.exec("SELECT * FROM dual")).not_to be_nil
    end

    it "should execute SQL select" do
      expect(@conn.select("SELECT * FROM dual")).to eq([{ "dummy" => "X" }])
    end

    it "should execute SQL select and return also columns" do
      expect(@conn.select("SELECT * FROM dual", nil, true)).to eq([ [{ "dummy" => "X" }], ["dummy"] ])
    end
  end

  describe "SQL with bind parameters" do
    before(:all) do
      @conn = ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection.create(CONNECTION_PARAMS)
    end

    it "should execute SQL statement with bind parameter" do
      cursor = @conn.prepare("SELECT * FROM dual WHERE :1 = 1")
      cursor.bind_param(1, 1)
      cursor.exec
      expect(cursor.get_col_names).to eq(["DUMMY"])
      expect(cursor.fetch).to eq(["X"])
      cursor.close
    end

    it "should execute prepared statement with different bind parameters" do
      cursor = @conn.prepare("SELECT * FROM dual WHERE :1 = 1")
      cursor.bind_param(1, 1)
      cursor.exec
      expect(cursor.fetch).to eq(["X"])
      cursor.bind_param(1, 0)
      cursor.exec
      expect(cursor.fetch).to be_nil
      cursor.close
    end
  end

  describe "SQL with bind parameters when NLS_NUMERIC_CHARACTERS is set to ', '" do
    before(:all) do
      ENV["NLS_NUMERIC_CHARACTERS"] = ", "
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
      @conn_base = ActiveRecord::Base.connection
      @conn = @conn_base.send(:_connection)
      @conn.exec "CREATE TABLE test_employees (age NUMBER(10,2))"
    end

    after(:all) do
      ENV["NLS_NUMERIC_CHARACTERS"] = nil
      @conn.exec "DROP TABLE test_employees" rescue nil
      ActiveRecord::Base.clear_cache!
    end

    it "should execute prepared statement with decimal bind parameter" do
      cursor = @conn.prepare("INSERT INTO test_employees VALUES(:1)")
      type_metadata = ActiveRecord::ConnectionAdapters::SqlTypeMetadata.new(sql_type: "NUMBER", type: :decimal, limit: 10, precision: nil, scale: 2)
      cast_type = @conn_base.lookup_cast_type("NUMBER(10)")
      column = ActiveRecord::ConnectionAdapters::OracleEnhanced::Column.new("age", cast_type, nil, type_metadata, false, comment: nil)
      expect(column.type).to eq(:decimal)
      # Here 1.5 expects that this value has been type casted already
      # it should use bind_params in the long term.
      cursor.bind_param(1, 1.5)
      cursor.exec
      cursor.close
      cursor = @conn.prepare("SELECT age FROM test_employees")
      cursor.exec
      expect(cursor.fetch).to eq([1.5])
      cursor.close
    end
  end

  describe "auto reconnection" do
    include SchemaSpecHelper

    before(:all) do
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
      @conn = ActiveRecord::Base.connection.send(:_connection)
      @sys_conn = ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection.create(SYS_CONNECTION_PARAMS)
      schema_define do
        create_table :posts, force: true
      end
      class ::Post < ActiveRecord::Base
      end
    end

    after(:all) do
      Object.send(:remove_const, "Post")
      ActiveRecord::Base.clear_cache!
    end

    before(:each) do
      ActiveRecord::Base.connection.reconnect! unless @conn.active?
    end

    def kill_current_session
      audsid = @conn.select("SELECT userenv('sessionid') audsid FROM dual").first["audsid"]
      sid_serial = @sys_conn.select("SELECT s.sid||','||s.serial# sid_serial
          FROM   v$session s
          WHERE  audsid = '#{audsid}'").first["sid_serial"]
      @sys_conn.exec "ALTER SYSTEM KILL SESSION '#{sid_serial}' IMMEDIATE"
    end

    it "should reconnect and execute SQL statement if connection is lost and auto retry is enabled" do
      # @conn.auto_retry = true
      ActiveRecord::Base.connection.auto_retry = true
      kill_current_session
      expect(@conn.exec("SELECT * FROM dual")).not_to be_nil
    end

    it "should reconnect and execute SQL statement if connection is lost and allow_retry is passed" do
      kill_current_session
      expect(@conn.exec("SELECT * FROM dual", allow_retry: true)).not_to be_nil
    end

    it "should not reconnect and execute SQL statement if connection is lost and auto retry is disabled" do
      # @conn.auto_retry = false
      ActiveRecord::Base.connection.auto_retry = false
      kill_current_session
      if defined?(RUBY_ENGINE) && RUBY_ENGINE == "jruby"
        expect { @conn.exec("SELECT * FROM dual") }.to raise_error(Java::JavaSql::SQLRecoverableException)
      else
        expect { @conn.exec("SELECT * FROM dual") }.to raise_error(OCIError)
      end
    end

    it "should reconnect and execute SQL select if connection is lost and auto retry is enabled" do
      # @conn.auto_retry = true
      ActiveRecord::Base.connection.auto_retry = true
      kill_current_session
      expect(@conn.select("SELECT * FROM dual")).to eq([{ "dummy" => "X" }])
    end

    it "should not reconnect and execute SQL select if connection is lost and auto retry is disabled" do
      # @conn.auto_retry = false
      ActiveRecord::Base.connection.auto_retry = false
      kill_current_session
      if defined?(RUBY_ENGINE) && RUBY_ENGINE == "jruby"
        expect { @conn.select("SELECT * FROM dual") }.to raise_error(Java::JavaSql::SQLRecoverableException)
      else
        expect { @conn.select("SELECT * FROM dual") }.to raise_error(OCIError)
      end
    end

    it "should reconnect and execute query if connection is lost and auto retry is enabled" do
      Post.create!
      ActiveRecord::Base.connection.auto_retry = true
      kill_current_session
      expect(Post.take).not_to be_nil
    end

    it "should not reconnect and execute query if connection is lost and auto retry is disabled" do
      Post.create!
      ActiveRecord::Base.connection.auto_retry = false
      kill_current_session
      expect { Post.take }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  describe "describe table" do
    before(:all) do
      @conn = ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection.create(CONNECTION_PARAMS)
      @owner = CONNECTION_PARAMS[:username].upcase
    end

    it "should describe existing table" do
      @conn.exec "CREATE TABLE test_employees (first_name VARCHAR2(20))" rescue nil
      expect(@conn.describe("test_employees")).to eq([@owner, "TEST_EMPLOYEES"])
      @conn.exec "DROP TABLE test_employees" rescue nil
    end

    it "should not describe non-existing table" do
      expect { @conn.describe("test_xxx") }.to raise_error(ActiveRecord::ConnectionAdapters::OracleEnhanced::ConnectionException)
    end

    it "should describe table in other schema" do
      expect(@conn.describe("sys.dual")).to eq(["SYS", "DUAL"])
    end

    it "should describe table in other schema if the schema and table are in different cases" do
      expect(@conn.describe("SYS.dual")).to eq(["SYS", "DUAL"])
    end

    it "should describe existing view" do
      @conn.exec "CREATE TABLE test_employees (first_name VARCHAR2(20))" rescue nil
      @conn.exec "CREATE VIEW test_employees_v AS SELECT * FROM test_employees" rescue nil
      expect(@conn.describe("test_employees_v")).to eq([@owner, "TEST_EMPLOYEES_V"])
      @conn.exec "DROP VIEW test_employees_v" rescue nil
      @conn.exec "DROP TABLE test_employees" rescue nil
    end

    it "should describe view in other schema" do
      expect(@conn.describe("sys.v_$version")).to eq(["SYS", "V_$VERSION"])
    end

    it "should describe existing private synonym" do
      @conn.exec "CREATE SYNONYM test_dual FOR sys.dual" rescue nil
      expect(@conn.describe("test_dual")).to eq(["SYS", "DUAL"])
      @conn.exec "DROP SYNONYM test_dual" rescue nil
    end

    it "should describe existing public synonym" do
      expect(@conn.describe("all_tables")).to eq(["SYS", "ALL_TABLES"])
    end

    if defined?(OCI8)
      context "OCI8 adapter" do
        it "should not fallback to SELECT-based logic when querying non-existent table information" do
          expect(@conn).not_to receive(:select_one)
          @conn.describe("non_existent") rescue ActiveRecord::ConnectionAdapters::OracleEnhanced::ConnectionException
        end
      end
    end
  end
end
