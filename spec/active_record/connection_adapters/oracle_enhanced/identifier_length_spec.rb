# frozen_string_literal: true

describe "OracleEnhancedAdapter identifier length configuration" do
  let(:adapter_class) { ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter }

  before(:each) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end

  after(:each) do
    adapter_class.use_legacy_identifier_length = false
    ActiveRecord::Base.remove_connection
  end

  describe "use_shorter_identifier" do
    it "is deprecated when assigned and delegates to use_legacy_identifier_length" do
      expect {
        adapter_class.use_shorter_identifier = true
      }.to output(/use_shorter_identifier.* is deprecated/).to_stderr

      expect(adapter_class.use_legacy_identifier_length).to be(true)
    end

    it "is deprecated when read and reflects use_legacy_identifier_length" do
      adapter_class.use_legacy_identifier_length = true

      expect {
        expect(adapter_class.use_shorter_identifier).to be(true)
      }.to output(/use_shorter_identifier.* is deprecated/).to_stderr
    end
  end

  describe "supports_longer_identifier?" do
    it "honors global use_legacy_identifier_length" do
      adapter_class.use_legacy_identifier_length = true
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
      conn = ActiveRecord::Base.lease_connection

      expect(conn.supports_longer_identifier?).to be(false)
      expect(conn.max_identifier_length).to eq(30)
    end

    it "honors per-connection use_legacy_identifier_length" do
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(use_legacy_identifier_length: true))
      conn = ActiveRecord::Base.lease_connection

      expect(conn.supports_longer_identifier?).to be(false)
      expect(conn.max_identifier_length).to eq(30)
    end

    it "per-connection config overrides global (legacy locally, longer globally)" do
      adapter_class.use_legacy_identifier_length = false
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(use_legacy_identifier_length: true))
      conn = ActiveRecord::Base.lease_connection

      expect(conn.supports_longer_identifier?).to be(false)
    end

    it "per-connection config overrides global (longer locally, legacy globally)" do
      adapter_class.use_legacy_identifier_length = true
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(use_legacy_identifier_length: false))
      conn = ActiveRecord::Base.lease_connection

      if Gem::Version.new(conn.database_version.join(".")) >= Gem::Version.new("12.2")
        expect(conn.supports_longer_identifier?).to be(true)
        expect(conn.max_identifier_length).to eq(128)
      else
        expect(conn.supports_longer_identifier?).to be(false)
        expect(conn.max_identifier_length).to eq(30)
      end
    end

    it "silently falls back to 30-byte identifiers on a pre-12.2 database" do
      conn = ActiveRecord::Base.lease_connection
      allow(conn).to receive(:database_version).and_return([11, 2])
      expect(conn.supports_longer_identifier?).to be(false)
      expect(conn.max_identifier_length).to eq(30)
    end

    it "falls back to the global setting when the per-connection value is nil" do
      adapter_class.use_legacy_identifier_length = true
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(use_legacy_identifier_length: nil))
      conn = ActiveRecord::Base.lease_connection

      expect(conn.supports_longer_identifier?).to be(false)
      expect(conn.max_identifier_length).to eq(30)
    end
  end

  describe "IDENTIFIER_MAX_LENGTH deprecation" do
    it "flows through OracleEnhanced.deprecator with the gem name and horizon" do
      expect {
        ActiveRecord::ConnectionAdapters::OracleEnhanced::DatabaseLimits::IDENTIFIER_MAX_LENGTH
      }.to output(/IDENTIFIER_MAX_LENGTH is deprecated.*activerecord-oracle_enhanced-adapter.*a future version/m).to_stderr
    end
  end
end
