# frozen_string_literal: true

describe "OracleEnhancedAdapter identifier length configuration" do
  let(:adapter_class) { ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter }

  before(:each) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end

  after(:each) do
    adapter_class.identifier_max_length = :auto
    ActiveRecord::Base.remove_connection
  end

  describe "use_shorter_identifier" do
    setter_warning = /use_shorter_identifier=.* is deprecated and will be removed from activerecord-oracle_enhanced-adapter a future version/m
    getter_warning = /use_shorter_identifier.* is deprecated and will be removed from activerecord-oracle_enhanced-adapter a future version/m

    it "warns of deprecation and future removal when assigned, and maps to identifier_max_length = :short" do
      expect {
        adapter_class.use_shorter_identifier = true
      }.to output(setter_warning).to_stderr

      expect(adapter_class.identifier_max_length).to eq(:short)
    end

    it "warns of deprecation and future removal when assigned false, and maps to identifier_max_length = :auto" do
      adapter_class.identifier_max_length = :short
      expect {
        adapter_class.use_shorter_identifier = false
      }.to output(setter_warning).to_stderr

      expect(adapter_class.identifier_max_length).to eq(:auto)
    end

    it "warns of deprecation and future removal when read and returns true iff identifier_max_length == :short" do
      adapter_class.identifier_max_length = :short

      expect {
        expect(adapter_class.use_shorter_identifier).to be(true)
      }.to output(getter_warning).to_stderr

      adapter_class.identifier_max_length = :auto
      expect {
        expect(adapter_class.use_shorter_identifier).to be(false)
      }.to output(getter_warning).to_stderr
    end
  end

  describe "supports_longer_identifier?" do
    it "honors global identifier_max_length = :short" do
      adapter_class.identifier_max_length = :short
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
      conn = ActiveRecord::Base.connection

      expect(conn.supports_longer_identifier?).to be(false)
      expect(conn.max_identifier_length).to eq(30)
    end

    it "honors global identifier_max_length = :long on 12.2+" do
      adapter_class.identifier_max_length = :long
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
      conn = ActiveRecord::Base.connection

      if Gem::Version.new(conn.database_version.join(".")) >= Gem::Version.new("12.2")
        expect(conn.supports_longer_identifier?).to be(true)
        expect(conn.max_identifier_length).to eq(128)
      else
        expect(conn.supports_longer_identifier?).to be(false)
        expect(conn.max_identifier_length).to eq(30)
      end
    end

    it "honors per-connection identifier_max_length = :short" do
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(identifier_max_length: :short))
      conn = ActiveRecord::Base.connection

      expect(conn.supports_longer_identifier?).to be(false)
      expect(conn.max_identifier_length).to eq(30)
    end

    it "accepts YAML string values and coerces them via to_sym" do
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(identifier_max_length: "short"))
      conn = ActiveRecord::Base.connection

      expect(conn.supports_longer_identifier?).to be(false)
      expect(conn.max_identifier_length).to eq(30)
    end

    it "per-connection config overrides global (:short locally, :auto globally)" do
      adapter_class.identifier_max_length = :auto
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(identifier_max_length: :short))
      conn = ActiveRecord::Base.connection

      expect(conn.supports_longer_identifier?).to be(false)
    end

    it "per-connection config overrides global (:long locally, :short globally)" do
      adapter_class.identifier_max_length = :short
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(identifier_max_length: :long))
      conn = ActiveRecord::Base.connection

      if Gem::Version.new(conn.database_version.join(".")) >= Gem::Version.new("12.2")
        expect(conn.supports_longer_identifier?).to be(true)
        expect(conn.max_identifier_length).to eq(128)
      else
        expect(conn.supports_longer_identifier?).to be(false)
        expect(conn.max_identifier_length).to eq(30)
      end
    end

    it "silently falls back to 30-byte identifiers on a pre-12.2 database with :auto" do
      conn = ActiveRecord::Base.connection
      allow(conn).to receive(:database_version).and_return([11, 2])
      expect(conn.supports_longer_identifier?).to be(false)
      expect(conn.max_identifier_length).to eq(30)
    end

    it "silently falls back to 30-byte identifiers on a pre-12.2 database with :long" do
      adapter_class.identifier_max_length = :long
      conn = ActiveRecord::Base.connection
      allow(conn).to receive(:database_version).and_return([11, 2])
      expect(conn.supports_longer_identifier?).to be(false)
      expect(conn.max_identifier_length).to eq(30)
    end

    it "falls back to the global setting when the per-connection value is nil" do
      adapter_class.identifier_max_length = :short
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(identifier_max_length: nil))
      conn = ActiveRecord::Base.connection

      expect(conn.supports_longer_identifier?).to be(false)
      expect(conn.max_identifier_length).to eq(30)
    end

    it "raises ArgumentError for unknown symbol values" do
      adapter_class.identifier_max_length = :bogus
      conn = ActiveRecord::Base.connection
      expect { conn.supports_longer_identifier? }.to raise_error(ArgumentError, /identifier_max_length must be :auto, :short, or :long/)
    end

    it "raises ArgumentError for non-symbol/non-string values (e.g. booleans) per-connection" do
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(identifier_max_length: true))
      conn = ActiveRecord::Base.connection
      expect { conn.supports_longer_identifier? }.to raise_error(ArgumentError, /identifier_max_length must be :auto, :short, or :long; got true/)
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
