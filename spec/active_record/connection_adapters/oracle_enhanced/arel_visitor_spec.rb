# frozen_string_literal: true

RSpec.describe "OracleEnhancedAdapter limit_offset_syntax configuration" do
  let(:adapter_class) { ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter }

  before(:each) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end

  after(:each) do
    ActiveRecord::ConnectionAdapters::OracleEnhanced.deprecator.silence do
      adapter_class.use_old_oracle_visitor = false
    end
    ActiveRecord::Base.remove_connection
  end

  describe "use_old_oracle_visitor=" do
    it "emits a deprecation warning and still updates the class attribute" do
      expect {
        adapter_class.use_old_oracle_visitor = true
      }.to output(/use_old_oracle_visitor=.* is deprecated/).to_stderr

      expect(adapter_class.use_old_oracle_visitor).to be(true)
    end

    it "emits a deprecation warning when assigned via an instance" do
      conn = ActiveRecord::Base.connection
      expect {
        conn.use_old_oracle_visitor = true
      }.to output(/use_old_oracle_visitor=.* is deprecated/).to_stderr
    end

    it "provides an instance-level reader that mirrors the class attribute" do
      ActiveRecord::ConnectionAdapters::OracleEnhanced.deprecator.silence do
        adapter_class.use_old_oracle_visitor = true
      end
      conn = ActiveRecord::Base.connection
      expect(conn.use_old_oracle_visitor).to be(true)
    end
  end

  describe "visitor selection" do
    it "uses Oracle12 by default, whatever the server version" do
      conn = ActiveRecord::Base.connection
      expect(conn.visitor).to be_a(Arel::Visitors::Oracle12)
    end

    it "honors per-connection limit_offset_syntax: :rownum" do
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(limit_offset_syntax: :rownum))
      conn = ActiveRecord::Base.connection

      expect(conn.visitor).to be_a(Arel::Visitors::Oracle)
      expect(conn.visitor).not_to be_a(Arel::Visitors::Oracle12)
    end

    it "honors per-connection limit_offset_syntax: :fetch_first" do
      skip "requires Oracle 12.1+" if ActiveRecord::Base.connection.database_version < "12"
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(limit_offset_syntax: :fetch_first))
      conn = ActiveRecord::Base.connection

      expect(conn.visitor).to be_a(Arel::Visitors::Oracle12)
    end

    it "accepts string values from database.yml-style config" do
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(limit_offset_syntax: "rownum"))
      conn = ActiveRecord::Base.connection

      expect(conn.visitor).to be_a(Arel::Visitors::Oracle)
    end

    it "raises ArgumentError for an unknown limit_offset_syntax value" do
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(limit_offset_syntax: :bogus))

      expect {
        ActiveRecord::Base.connection
      }.to raise_error(ArgumentError, /bogus/)
    end

    it "raises ArgumentError (not NoMethodError) for non-string/symbol scalar values" do
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(limit_offset_syntax: false))

      expect {
        ActiveRecord::Base.connection
      }.to raise_error(ArgumentError, /String or Symbol/)
    end

    it "falls back to the class-level setting when limit_offset_syntax is explicitly nil" do
      # Mirrors the `foo:` / `foo: ~` shape in database.yml that YAML parses to nil.
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(limit_offset_syntax: nil))
      conn = ActiveRecord::Base.connection

      expect(conn.visitor).to be_a(Arel::Visitors::Oracle12)
    end

    it "falls back to the class-level use_old_oracle_visitor when no per-connection key is given" do
      ActiveRecord::ConnectionAdapters::OracleEnhanced.deprecator.silence do
        adapter_class.use_old_oracle_visitor = true
      end
      conn = adapter_class.new(CONNECTION_PARAMS)

      expect(conn.visitor).to be_a(Arel::Visitors::Oracle)
      expect(conn.visitor).not_to be_a(Arel::Visitors::Oracle12)
    ensure
      conn&.disconnect!
    end

    it "per-connection limit_offset_syntax overrides class-level use_old_oracle_visitor" do
      skip "requires Oracle 12.1+" if ActiveRecord::Base.connection.database_version < "12"
      ActiveRecord::ConnectionAdapters::OracleEnhanced.deprecator.silence do
        adapter_class.use_old_oracle_visitor = true
      end
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(limit_offset_syntax: :fetch_first))
      conn = ActiveRecord::Base.connection

      expect(conn.visitor).to be_a(Arel::Visitors::Oracle12)
    end

    it "per-connection :auto overrides class-level use_old_oracle_visitor" do
      # Forward-compatibility: writing `limit_offset_syntax: :auto` produces the
      # same visitor whether or not use_old_oracle_visitor is set, so the
      # behavior is stable across the use_old_oracle_visitor deprecation.
      ActiveRecord::ConnectionAdapters::OracleEnhanced.deprecator.silence do
        adapter_class.use_old_oracle_visitor = true
      end
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(limit_offset_syntax: :auto))
      conn = ActiveRecord::Base.connection

      expect(conn.visitor).to be_a(Arel::Visitors::Oracle12)
    end
  end

  describe ":auto" do
    it "compiles LIMIT for the connected server version" do
      conn = ActiveRecord::Base.connection
      stmt = Arel::Table.new(name: :users).project(Arel.star).take(10).ast
      sql = conn.visitor.accept(stmt, Arel::Collectors::SQLString.new).value

      if conn.database_version >= "12"
        expect(sql).to include("FETCH FIRST 10 ROWS ONLY")
      else
        expect(sql).to include("ROWNUM <= 10")
        expect(sql).not_to include("FETCH FIRST")
      end
    end

    it "compiles an UPDATE with a limit but no key as Arel::Visitors::Oracle does before 12.1" do
      conn = ActiveRecord::Base.connection
      table = Arel::Table.new(name: :users)
      um = Arel::UpdateManager.new(table)
      um.set([[table[:name], Arel.sql("'foo'")]])
      um.take(10)
      sql = conn.visitor.accept(um.ast, Arel::Collectors::SQLString.new).value

      if conn.database_version >= "12"
        expect(sql).to include("FETCH FIRST 10 ROWS ONLY")
      else
        oracle = Arel::Visitors::Oracle.new(conn)
        expect(sql).to eq(oracle.accept(um.ast, Arel::Collectors::SQLString.new).value)
      end
    end
  end

  describe "supports_fetch_first_n_rows_and_offset?" do
    # Capability flag — answers "does this database support FETCH FIRST n ROWS
    # ONLY syntax?" — driven by the connected server version, not by the
    # configured `limit_offset_syntax`. Forcing `:rownum` on a 12c+ connection does
    # not change what the database supports; it only changes what the adapter
    # emits.
    it "reflects database_version regardless of limit_offset_syntax override" do
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(limit_offset_syntax: :rownum))
      conn = ActiveRecord::Base.connection

      expected = conn.database_version >= "12"
      expect(conn.supports_fetch_first_n_rows_and_offset?).to be(expected)
    end
  end

  describe ":fetch_first on pre-12c" do
    after(:all) do
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    end

    it "raises DatabaseVersionError when the reported version is older than 12.1" do
      allow_any_instance_of(adapter_class).to receive(:database_version)
        .and_return(adapter_class::Version.new("11.2", "11.2.0.4.0"))

      expect { adapter_class.new(CONNECTION_PARAMS.merge(limit_offset_syntax: :fetch_first)).connect! }
        .to raise_error(ActiveRecord::DatabaseVersionError, /limit_offset_syntax: :fetch_first requires Oracle 12\.1 or later/)
    end

    it "raises DatabaseVersionError when connecting to a server older than 12.1" do
      skip "requires Oracle pre-12.1" if ActiveRecord::Base.connection.database_version >= "12"
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(limit_offset_syntax: :fetch_first))

      expect { ActiveRecord::Base.connection }
        .to raise_error(ActiveRecord::DatabaseVersionError, /limit_offset_syntax: :fetch_first requires Oracle 12\.1 or later/)
    end
  end
end
