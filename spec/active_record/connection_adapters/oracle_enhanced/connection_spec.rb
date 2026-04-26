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

  it "should raise ArgumentError for an unsupported cursor_sharing value" do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(cursor_sharing: "not_a_valid_mode"))
    expect { ActiveRecord::Base.connection }.to raise_error(ArgumentError, /Invalid :cursor_sharing value/)
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
    skip "Oracle 11g XE does not support native network encryption" if ENV["DATABASE_VERSION"] == "11.2.0.2"
    if ORACLE_ENHANCED_CONNECTION == :jdbc
      ActiveRecord::Base.establish_connection(SYSTEM_CONNECTION_PARAMS.merge(jdbc_connect_properties: { "oracle.net.encryption_client" => "REJECTED" }))
      conn = ActiveRecord::Base.connection.send(:_connection)
      expect(conn.select("SELECT COUNT(*) Records FROM v$Session_Connect_Info WHERE SID=SYS_CONTEXT('USERENV', 'SID') AND Network_Service_Banner LIKE '%Encryption service adapter%'")).to eq([{ "records" => 0 }])
    end
  end

  it "should encrypt JDBC network connection" do
    skip "Oracle 11g XE does not support native network encryption" if ENV["DATABASE_VERSION"] == "11.2.0.2"
    if ORACLE_ENHANCED_CONNECTION == :jdbc
      ActiveRecord::Base.establish_connection(SYSTEM_CONNECTION_PARAMS.merge(jdbc_connect_properties: { "oracle.net.encryption_client" => "REQUESTED" }))
      conn = ActiveRecord::Base.connection.send(:_connection)
      expect(conn.select("SELECT COUNT(*) Records FROM v$Session_Connect_Info WHERE SID=SYS_CONTEXT('USERENV', 'SID') AND Network_Service_Banner LIKE '%Encryption service adapter%'")).to eq([{ "records" => 1 }])
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

    it "should raise ArgumentError when JDBC exec is called with bindvars" do
      skip unless ORACLE_ENHANCED_CONNECTION == :jdbc
      expect {
        @conn.exec("SELECT ? FROM dual", 1)
      }.to raise_error(ArgumentError, /JDBC exec does not support bindvars/)
    end
  end

  describe "create connection with schema option" do
    before(:each) do
      ActiveRecord::Base.establish_connection(CONNECTION_WITH_SCHEMA_PARAMS)
    end

    after(:all) do
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    end

    it "should create new connection" do
      expect(ActiveRecord::Base.connection).to be_active
    end

    it "should switch to specified schema" do
      expect(ActiveRecord::Base.connection.current_schema).to eq(CONNECTION_WITH_SCHEMA_PARAMS[:schema].upcase)
      expect(ActiveRecord::Base.connection.current_user).to eq(CONNECTION_WITH_SCHEMA_PARAMS[:username].upcase)
    end

    it "should switch to specified schema after reset" do
      ActiveRecord::Base.connection.reset!
      expect(ActiveRecord::Base.connection.current_schema).to eq(CONNECTION_WITH_SCHEMA_PARAMS[:schema].upcase)
    end

    it "should raise ArgumentError for a :schema value that is not an Oracle unquoted identifier" do
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(schema: "oracle_enhanced;DROP TABLE x;--"))
      expect { ActiveRecord::Base.connection }.to raise_error(ArgumentError, /Invalid :schema value/)
    end
  end

  describe "resolving unqualified names with :schema set to a different user" do
    # Pins down the end-to-end contract of the `:schema` connection option:
    #
    # When `:schema` is present in the connection config, two independent
    # mechanisms must line up so that unqualified references to tables owned
    # by the `:schema` user resolve correctly end-to-end:
    #
    #   1. At connect time, the adapter runs
    #      `ALTER SESSION SET CURRENT_SCHEMA = <schema>`, so Oracle's own name
    #      resolution treats unqualified identifiers in SQL as belonging to
    #      the `:schema` user.
    #   2. The connection wrapper sets `@owner = config[:schema]` (falling
    #      back to `config[:username]`), so the adapter's catalog-lookup path
    #      (`data_source_exists?`, `column_definitions`, `indexes`, etc.)
    #      defaults its owner filter to the `:schema` user.
    #
    # If either mechanism drifts — e.g. someone changes `@owner` to track the
    # login user instead of `:schema`, or drops the ALTER SESSION at connect
    # time — the matching assertion below will fail, forcing the change to be
    # a conscious decision rather than a silent behavior drift.
    schema_owner_params = CONNECTION_PARAMS.merge(username: DATABASE_SCHEMA, password: DATABASE_SCHEMA)

    before(:all) do
      ActiveRecord::Base.establish_connection(schema_owner_params)
      schema_conn = ActiveRecord::Base.connection
      schema_conn.drop_table :schema_probe_table, if_exists: true
      schema_conn.create_table :schema_probe_table, id: :integer
      schema_conn.execute "GRANT SELECT ON schema_probe_table TO #{DATABASE_USER}"
      ActiveRecord::Base.remove_connection

      ActiveRecord::Base.establish_connection(CONNECTION_WITH_SCHEMA_PARAMS)
    end

    after(:all) do
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(schema_owner_params)
      ActiveRecord::Base.connection.drop_table :schema_probe_table, if_exists: true
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    end

    it "sets CURRENT_SCHEMA so unqualified raw SQL resolves in the :schema user" do
      expect(ActiveRecord::Base.connection.current_schema).to eq(DATABASE_SCHEMA.upcase)
      expect {
        ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM schema_probe_table")
      }.not_to raise_error
    end

    it "data_source_exists? resolves an unqualified name in the :schema user" do
      expect(ActiveRecord::Base.connection.data_source_exists?("schema_probe_table")).to be true
    end
  end

  describe "create connection with NLS parameters" do
    after do
      ENV["NLS_TERRITORY"] = nil
    end

    it "should use NLS_TERRITORY environment variable" do
      ENV["NLS_TERRITORY"] = "JAPAN"
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
      expect(ActiveRecord::Base.connection.select_value("select SYS_CONTEXT('userenv', 'NLS_TERRITORY') from dual")).to eq("JAPAN")
    end

    it "should use configuration value and ignore NLS_TERRITORY environment variable" do
      ENV["NLS_TERRITORY"] = "AMERICA"
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(nls_territory: "INDONESIA"))
      expect(ActiveRecord::Base.connection.select_value("select SYS_CONTEXT('userenv', 'NLS_TERRITORY') from dual")).to eq("INDONESIA")
    end
  end

  describe "Fixed NLS parameters" do
    after do
      ENV["NLS_DATE_FORMAT"] = nil
    end

    it "should ignore NLS_DATE_FORMAT environment variable" do
      ENV["NLS_DATE_FORMAT"] = "YYYY-MM-DD"
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
      expect(ActiveRecord::Base.connection.select_value("select SYS_CONTEXT('userenv', 'NLS_DATE_FORMAT') from dual")).to eq("YYYY-MM-DD HH24:MI:SS")
    end

    it "should ignore NLS_DATE_FORMAT configuration value" do
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(nls_date_format: "YYYY-MM-DD HH24:MI"))
      expect(ActiveRecord::Base.connection.select_value("select SYS_CONTEXT('userenv', 'NLS_DATE_FORMAT') from dual")).to eq("YYYY-MM-DD HH24:MI:SS")
    end

    it "should use default value when NLS_DATE_FORMAT environment variable is not set" do
      ENV["NLS_DATE_FORMAT"] = nil
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
      default = ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter::FIXED_NLS_PARAMETERS[:nls_date_format]
      expect(ActiveRecord::Base.connection.select_value("select SYS_CONTEXT('userenv', 'NLS_DATE_FORMAT') from dual")).to eq(default)
    end
  end

  describe "session settings survive reconnect!" do
    it "re-applies FIXED_NLS_PARAMETERS after reconnect!" do
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
      expected = ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter::FIXED_NLS_PARAMETERS[:nls_date_format]
      # Taint NLS_DATE_FORMAT on the current session so the post-reconnect
      # assertion can only pass if configure_connection actively re-applies
      # FIXED_NLS_PARAMETERS on the fresh physical session.
      ActiveRecord::Base.connection.execute("ALTER SESSION SET NLS_DATE_FORMAT = 'DD-MON-RRRR'")
      ActiveRecord::Base.connection.reconnect!
      expect(ActiveRecord::Base.connection.select_value("select SYS_CONTEXT('userenv', 'NLS_DATE_FORMAT') from dual")).to eq(expected)
    end

    it "re-applies current_schema after reconnect!" do
      ActiveRecord::Base.establish_connection(CONNECTION_WITH_SCHEMA_PARAMS)
      expected = CONNECTION_WITH_SCHEMA_PARAMS[:schema].upcase
      expect(ActiveRecord::Base.connection.current_schema).to eq(expected)
      ActiveRecord::Base.connection.reconnect!
      expect(ActiveRecord::Base.connection.current_schema).to eq(expected)
    end

    it "re-applies cursor_sharing after reconnect!" do
      ActiveRecord::Base.establish_connection(SYSTEM_CONNECTION_PARAMS.merge(cursor_sharing: :exact))
      expect(ActiveRecord::Base.connection.select_value("select value from v$parameter where name = 'cursor_sharing'")).to eq("EXACT")
      ActiveRecord::Base.connection.reconnect!
      expect(ActiveRecord::Base.connection.select_value("select value from v$parameter where name = 'cursor_sharing'")).to eq("EXACT")
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
      cast_type = @conn_base.lookup_cast_type("NUMBER(10,2)")
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
      # Always reconnect so that prepared statement / cursor caches do
      # not carry stale OCI8::Cursor objects from a previous example
      # whose `kill_current_session` invalidated them. Checking
      # `@conn.active?` only reconnects the raw OCI handle; the
      # AR-level prepared statement cache can still hold a closed
      # cursor that the next `Post.create!` will try to bind_param on.
      ActiveRecord::Base.connection.reconnect!
    end

    def kill_current_session
      audsid = @conn.select("SELECT userenv('sessionid') audsid FROM dual").first["audsid"]
      sid_serial = @sys_conn.select("SELECT s.sid||','||s.serial# sid_serial
          FROM   v$session s
          WHERE  audsid = '#{audsid}'").first["sid_serial"]
      @sys_conn.exec "ALTER SYSTEM KILL SESSION '#{sid_serial}' IMMEDIATE"
    end

    def connection_id_from_server(conn)
      audsid = conn.select("SELECT userenv('sessionid') audsid FROM dual").first["audsid"]
      @sys_conn.select("SELECT s.sid||','||s.serial# sid_serial
          FROM   v$session s
          WHERE  audsid = '#{audsid}'").first["sid_serial"]
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

    # Regression test ported from rails/rails#46273, which only covers
    # Mysql2 and PostgreSQL in the Rails repository.
    it "adapter #execute is retryable when allow_retry: true is passed" do
      previous_auto_retry = ActiveRecord::Base.connection.auto_retry
      ActiveRecord::Base.connection.auto_retry = false
      begin
        initial_connection_id = connection_id_from_server(@conn)
        kill_current_session
        expect { ActiveRecord::Base.connection.execute("SELECT 1 FROM dual", allow_retry: true) }.not_to raise_error
        expect(connection_id_from_server(@conn)).not_to eq(initial_connection_id)
      ensure
        ActiveRecord::Base.connection.auto_retry = previous_auto_retry
      end
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

    if RUBY_ENGINE == "jruby"
      # ojdbc17 surfaces dropped-connection errors with both a proper
      # SQLException#getErrorCode and an "ORA-17NNN:" prefix in the message.
      # Regression test for the case where the prefixed message no longer
      # matches LOST_CONNECTION_MESSAGE and the code must be recognised via
      # JDBC_LOST_CONNECTION_ERROR_CODES instead.
      it "recognises ORA-17008 via the JDBC driver error code" do
        exception = Java::JavaSql::SQLException.new("ORA-17008: Closed connection", nil, 17008)
        expect(@conn.lost_connection?(exception)).to be true
      end

      it "recognises ORA-17002 via the JDBC driver error code" do
        exception = Java::JavaSql::SQLException.new("ORA-17002: Io exception", nil, 17002)
        expect(@conn.lost_connection?(exception)).to be true
      end

      it "recognises older ojdbc 'Closed Connection' messages with no error code attached" do
        exception = Java::JavaSql::SQLException.new("Closed Connection", nil, 0)
        expect(@conn.lost_connection?(exception)).to be true
      end

      # ORA-17009 "Closed Statement" means only the Statement handle is
      # gone; the connection may still be alive. Treating it as a lost
      # connection would discard a live session, so lost_connection?
      # must return false. Cursor#close tolerates 17009 separately.
      it "does not treat ORA-17009 (Closed Statement) as a lost connection" do
        exception = Java::JavaSql::SQLException.new("ORA-17009: Closed Statement", nil, 17009)
        expect(@conn.lost_connection?(exception)).to be false
      end
    end
  end

  describe "resolve_data_source_name" do
    before(:all) do
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
      @conn = ActiveRecord::Base.connection
      @owner = CONNECTION_PARAMS[:username].upcase
    end

    def resolve(name)
      @conn.send(:resolve_data_source_name, name)
    end

    it "should resolve existing table" do
      @conn.execute "CREATE TABLE test_employees (first_name VARCHAR2(20))" rescue nil
      expect(resolve("test_employees")).to eq([@owner, "TEST_EMPLOYEES"])
      @conn.execute "DROP TABLE test_employees" rescue nil
    end

    it "should not resolve non-existing table" do
      expect { resolve("test_xxx") }.to raise_error(ActiveRecord::ConnectionAdapters::OracleEnhanced::ConnectionException)
    end

    it "should resolve table in other schema" do
      expect(resolve("sys.dual")).to eq(["SYS", "DUAL"])
    end

    it "should resolve table in other schema if the schema and table are in different cases" do
      expect(resolve("SYS.dual")).to eq(["SYS", "DUAL"])
    end

    it "should resolve existing view" do
      @conn.execute "CREATE TABLE test_employees (first_name VARCHAR2(20))" rescue nil
      @conn.execute "CREATE VIEW test_employees_v AS SELECT * FROM test_employees" rescue nil
      expect(resolve("test_employees_v")).to eq([@owner, "TEST_EMPLOYEES_V"])
      @conn.execute "DROP VIEW test_employees_v" rescue nil
      @conn.execute "DROP TABLE test_employees" rescue nil
    end

    it "should resolve view in other schema" do
      expect(resolve("sys.v_$version")).to eq(["SYS", "V_$VERSION"])
    end

    it "should resolve existing materialized view" do
      @conn.execute "CREATE TABLE test_employees (first_name VARCHAR2(20))" rescue nil
      @conn.execute "CREATE MATERIALIZED VIEW test_employees_mv AS SELECT * FROM test_employees" rescue nil
      expect(resolve("test_employees_mv")).to eq([@owner, "TEST_EMPLOYEES_MV"])
      @conn.execute "DROP MATERIALIZED VIEW test_employees_mv" rescue nil
      @conn.execute "DROP TABLE test_employees" rescue nil
    end

    it "should resolve existing private synonym" do
      @conn.execute "CREATE SYNONYM test_dual FOR sys.dual" rescue nil
      expect(resolve("test_dual")).to eq(["SYS", "DUAL"])
      @conn.execute "DROP SYNONYM test_dual" rescue nil
    end

    it "should resolve existing public synonym" do
      expect(resolve("all_tables")).to eq(["SYS", "ALL_TABLES"])
    end

    # Exercises all five catalog paths (table, view, materialized view,
    # private synonym, public synonym) for one underlying table in a single
    # run. The individual cases above use disjoint fixtures; this one proves
    # the DECODE-ordered all_objects lookup + synonym follow-through stays
    # consistent when a private and a public synonym to the same table
    # coexist, and that a materialized view created on the same base table
    # resolves to the MV name (not the base table) as a sibling data source.
    it "resolves table, view, materialized view, private synonym and public synonym for the same underlying table" do
      @conn.execute "CREATE TABLE test_describe_all (id NUMBER)" rescue nil
      @conn.execute "CREATE VIEW test_describe_all_v AS SELECT * FROM test_describe_all" rescue nil
      @conn.execute "CREATE MATERIALIZED VIEW test_describe_all_mv AS SELECT * FROM test_describe_all" rescue nil
      @conn.execute "CREATE SYNONYM test_describe_all_syn FOR test_describe_all" rescue nil
      @conn.execute "CREATE PUBLIC SYNONYM test_describe_all_pub FOR #{@owner}.test_describe_all" rescue nil

      expect(resolve("test_describe_all")).to eq([@owner, "TEST_DESCRIBE_ALL"])
      expect(resolve("test_describe_all_v")).to eq([@owner, "TEST_DESCRIBE_ALL_V"])
      expect(resolve("test_describe_all_mv")).to eq([@owner, "TEST_DESCRIBE_ALL_MV"])
      expect(resolve("test_describe_all_syn")).to eq([@owner, "TEST_DESCRIBE_ALL"])
      expect(resolve("test_describe_all_pub")).to eq([@owner, "TEST_DESCRIBE_ALL"])
    ensure
      @conn.execute "DROP PUBLIC SYNONYM test_describe_all_pub" rescue nil
      @conn.execute "DROP SYNONYM test_describe_all_syn" rescue nil
      @conn.execute "DROP MATERIALIZED VIEW test_describe_all_mv" rescue nil
      @conn.execute "DROP VIEW test_describe_all_v" rescue nil
      @conn.execute "DROP TABLE test_describe_all" rescue nil
    end

    it "raises when synonym resolution produces a looping chain" do
      @conn.execute "CREATE SYNONYM test_cycle_a FOR test_cycle_b" rescue nil
      @conn.execute "CREATE SYNONYM test_cycle_b FOR test_cycle_a" rescue nil
      expect { resolve("test_cycle_a") }.to raise_error(
        ActiveRecord::ConnectionAdapters::OracleEnhanced::ConnectionException,
        /looping chain of synonyms/
      )
    ensure
      @conn.execute "DROP SYNONYM test_cycle_a" rescue nil
      @conn.execute "DROP SYNONYM test_cycle_b" rescue nil
    end

    it "raises when a multi-hop synonym chain eventually revisits an earlier link" do
      @conn.execute "CREATE SYNONYM test_cycle_a FOR test_cycle_b" rescue nil
      @conn.execute "CREATE SYNONYM test_cycle_b FOR test_cycle_c" rescue nil
      @conn.execute "CREATE SYNONYM test_cycle_c FOR test_cycle_a" rescue nil
      expect { resolve("test_cycle_a") }.to raise_error(
        ActiveRecord::ConnectionAdapters::OracleEnhanced::ConnectionException,
        /looping chain of synonyms/
      )
    ensure
      @conn.execute "DROP SYNONYM test_cycle_a" rescue nil
      @conn.execute "DROP SYNONYM test_cycle_b" rescue nil
      @conn.execute "DROP SYNONYM test_cycle_c" rescue nil
    end

    it "raises ArgumentError when the name contains a db link" do
      expect { resolve("test@db_link") }.to raise_error(ArgumentError, /db link is not supported/)
    end

    # The previous Connection#describe path bypassed the adapter's query machinery
    # by driving a raw cursor, so its catalog lookup produced no sql.active_record
    # event. Routing through select_one(..., "SCHEMA", ...) makes the lookup
    # participate in logging, instrumentation, and the query cache. Lock that in
    # so a future refactor can't silently regress to the raw-cursor path.
    it "emits a SCHEMA sql.active_record event for the catalog lookup" do
      @conn.execute "CREATE TABLE test_employees (first_name VARCHAR2(20))" rescue nil
      events = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        events << payload
      end
      resolve("test_employees")
      expect(events.map { |p| p[:name] }).to include("SCHEMA")
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
      @conn.execute "DROP TABLE test_employees" rescue nil
    end
  end

  describe "extract_schema_qualified_name" do
    before(:all) do
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
      @conn = ActiveRecord::Base.connection
    end

    def extract(string)
      @conn.send(:extract_schema_qualified_name, string)
    end

    it "returns [nil, identifier] for an unqualified name and upcases it" do
      expect(extract("table_name")).to eq([nil, "TABLE_NAME"])
    end

    it "leaves an already upcased unqualified name as-is" do
      expect(extract("TABLE_NAME")).to eq([nil, "TABLE_NAME"])
    end

    it "splits a schema-qualified name and upcases it" do
      expect(extract("hr.dept")).to eq(["HR", "DEPT"])
    end

    it "upcases a qualified name whose parts are in different cases" do
      expect(extract("SYS.dual")).to eq(["SYS", "DUAL"])
    end

    it "accepts a Symbol and coerces it to a string" do
      expect(extract(:dept)).to eq([nil, "DEPT"])
    end

    it "raises ArgumentError when the name contains a db link" do
      expect { extract("test@db_link") }.to raise_error(ArgumentError, /db link is not supported/)
    end

    it "does not upcase a name that is not a valid identifier" do
      expect(extract('"Weird Name"')).to eq([nil, '"Weird Name"'])
    end
  end
end
