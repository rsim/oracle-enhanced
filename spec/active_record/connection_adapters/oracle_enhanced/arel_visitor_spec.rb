# frozen_string_literal: true

describe "OracleEnhancedAdapter arel_visitor configuration" do
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
    it "picks Oracle12 on a real 12.1+ database by default" do
      conn = ActiveRecord::Base.connection
      if conn.database_version.first >= 12
        expect(conn.visitor).to be_a(Arel::Visitors::Oracle12)
      else
        expect(conn.visitor).to be_a(Arel::Visitors::Oracle)
      end
    end

    it "honors per-connection arel_visitor: :rownum" do
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(arel_visitor: :rownum))
      conn = ActiveRecord::Base.connection

      expect(conn.visitor).to be_a(Arel::Visitors::Oracle)
      expect(conn.visitor).not_to be_a(Arel::Visitors::Oracle12)
    end

    it "honors per-connection arel_visitor: :fetch_first" do
      skip "requires Oracle 12.1+" if ActiveRecord::Base.connection.database_version.first < 12
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(arel_visitor: :fetch_first))
      conn = ActiveRecord::Base.connection

      expect(conn.visitor).to be_a(Arel::Visitors::Oracle12)
    end

    it "accepts string values from database.yml-style config" do
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(arel_visitor: "rownum"))
      conn = ActiveRecord::Base.connection

      expect(conn.visitor).to be_a(Arel::Visitors::Oracle)
    end

    it "raises ArgumentError for an unknown arel_visitor value" do
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(arel_visitor: :bogus))

      expect {
        ActiveRecord::Base.connection
      }.to raise_error(ArgumentError, /bogus/)
    end

    it "raises ArgumentError (not NoMethodError) for non-string/symbol scalar values" do
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(arel_visitor: false))

      expect {
        ActiveRecord::Base.connection
      }.to raise_error(ArgumentError, /String or Symbol/)
    end

    it "falls back to the class-level setting when arel_visitor is explicitly nil" do
      # Mirrors the `foo:` / `foo: ~` shape in database.yml that YAML parses to nil.
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(arel_visitor: nil))
      conn = ActiveRecord::Base.connection

      if conn.database_version.first >= 12
        expect(conn.visitor).to be_a(Arel::Visitors::Oracle12)
      else
        expect(conn.visitor).to be_a(Arel::Visitors::Oracle)
      end
    end

    it "falls back to the class-level use_old_oracle_visitor when no per-connection key is given" do
      ActiveRecord::ConnectionAdapters::OracleEnhanced.deprecator.silence do
        adapter_class.use_old_oracle_visitor = true
      end
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
      conn = ActiveRecord::Base.connection

      expect(conn.visitor).to be_a(Arel::Visitors::Oracle)
      expect(conn.visitor).not_to be_a(Arel::Visitors::Oracle12)
    end

    it "per-connection arel_visitor overrides class-level use_old_oracle_visitor" do
      skip "requires Oracle 12.1+" if ActiveRecord::Base.connection.database_version.first < 12
      ActiveRecord::ConnectionAdapters::OracleEnhanced.deprecator.silence do
        adapter_class.use_old_oracle_visitor = true
      end
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(arel_visitor: :fetch_first))
      conn = ActiveRecord::Base.connection

      expect(conn.visitor).to be_a(Arel::Visitors::Oracle12)
    end

    it "per-connection :auto overrides class-level use_old_oracle_visitor and resolves by database_version" do
      # Forward-compatibility: writing `arel_visitor: :auto` produces the
      # same visitor whether or not use_old_oracle_visitor is set, so the
      # behavior is stable across the use_old_oracle_visitor deprecation.
      ActiveRecord::ConnectionAdapters::OracleEnhanced.deprecator.silence do
        adapter_class.use_old_oracle_visitor = true
      end
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(arel_visitor: :auto))
      conn = ActiveRecord::Base.connection

      if conn.database_version.first >= 12
        expect(conn.visitor).to be_a(Arel::Visitors::Oracle12)
      else
        expect(conn.visitor).to be_a(Arel::Visitors::Oracle)
      end
    end
  end

  describe "resolved_arel_visitor_mode" do
    it "returns :fetch_first when database_version is 12.1+ and no override" do
      conn = ActiveRecord::Base.connection
      allow(conn).to receive(:database_version).and_return([12, 1])
      expect(conn.send(:resolved_arel_visitor_mode)).to eq(:fetch_first)
    end

    it "returns :rownum when database_version is 11.2 and no override" do
      conn = ActiveRecord::Base.connection
      allow(conn).to receive(:database_version).and_return([11, 2])
      expect(conn.send(:resolved_arel_visitor_mode)).to eq(:rownum)
    end

    it "returns :fetch_first on recent Oracle releases" do
      conn = ActiveRecord::Base.connection
      allow(conn).to receive(:database_version).and_return([19, 3])
      expect(conn.send(:resolved_arel_visitor_mode)).to eq(:fetch_first)
      allow(conn).to receive(:database_version).and_return([23, 0])
      expect(conn.send(:resolved_arel_visitor_mode)).to eq(:fetch_first)
    end
  end

  describe "supports_fetch_first_n_rows_and_offset?" do
    # Capability flag — answers "does this database support FETCH FIRST n ROWS
    # ONLY syntax?" — driven by the connected server version, not by the
    # configured `arel_visitor`. Forcing `:rownum` on a 12c+ connection does
    # not change what the database supports; it only changes what the adapter
    # emits.
    it "reflects database_version >= 12 regardless of arel_visitor override" do
      skip "requires Oracle 12.1+" if ActiveRecord::Base.connection.database_version.first < 12
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(arel_visitor: :rownum))
      conn = ActiveRecord::Base.connection

      expect(conn.database_version.first).to be >= 12
      expect(conn.supports_fetch_first_n_rows_and_offset?).to be(true)
    end

    it "stubs to expected output for a synthetic pre-12c version" do
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
      conn = ActiveRecord::Base.connection

      allow(conn).to receive(:database_version).and_return([11, 2])
      expect(conn.supports_fetch_first_n_rows_and_offset?).to be(false)
    end
  end

  describe ":fetch_first on pre-12c" do
    after(:all) do
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    end

    it "raises ArgumentError" do
      skip "requires Oracle 12.1+" if ActiveRecord::Base.connection.database_version.first < 12
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(arel_visitor: :fetch_first))
      conn = ActiveRecord::Base.connection
      allow(conn).to receive(:database_version).and_return([11, 2])

      expect { conn.send(:resolved_arel_visitor_mode) }
        .to raise_error(ArgumentError, /arel_visitor: :fetch_first requires Oracle 12\.1 or later/)
    end
  end
end
