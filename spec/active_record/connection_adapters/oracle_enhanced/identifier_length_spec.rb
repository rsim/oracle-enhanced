# frozen_string_literal: true

describe "OracleEnhancedAdapter identifier length configuration" do
  let(:adapter_class) { ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter }

  before(:each) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end

  after(:each) do
    ActiveRecord::Base.remove_connection
    # Reset the deprecated global fallback that individual tests may have toggled.
    # Use the class variable directly to avoid emitting a deprecation warning.
    adapter_class.class_variable_set(:@@use_shorter_identifier, false)
  end

  describe "use_shorter_identifier (deprecated global fallback)" do
    setter_warning = /use_shorter_identifier=.* is deprecated and will be removed from activerecord-oracle_enhanced-adapter a future version/m
    getter_warning = /use_shorter_identifier.* is deprecated and will be removed from activerecord-oracle_enhanced-adapter a future version/m

    it "warns of deprecation and future removal when assigned" do
      expect {
        adapter_class.use_shorter_identifier = true
      }.to output(setter_warning).to_stderr

      expect(adapter_class.class_variable_get(:@@use_shorter_identifier)).to be(true)
    end

    it "warns of deprecation and future removal when read" do
      adapter_class.class_variable_set(:@@use_shorter_identifier, true)

      expect {
        expect(adapter_class.use_shorter_identifier).to be(true)
      }.to output(getter_warning).to_stderr
    end

    it "is honored by connections that do not set identifier_max_length themselves" do
      adapter_class.class_variable_set(:@@use_shorter_identifier, true)
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
      conn = ActiveRecord::Base.connection

      expect(conn.supports_longer_identifier?).to be(false)
      expect(conn.max_identifier_length).to eq(30)
    end

    it "is overridden by an explicit per-connection identifier_max_length" do
      adapter_class.class_variable_set(:@@use_shorter_identifier, true)
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(identifier_max_length: :auto))
      conn = ActiveRecord::Base.connection

      if Gem::Version.new(conn.database_version.join(".")) >= Gem::Version.new("12.2")
        expect(conn.supports_longer_identifier?).to be(true)
        expect(conn.max_identifier_length).to eq(128)
      else
        expect(conn.supports_longer_identifier?).to be(false)
        expect(conn.max_identifier_length).to eq(30)
      end
    end
  end

  describe "identifier_max_length (per-connection)" do
    it "defaults to :auto when the key is absent (128 bytes on 12.2+)" do
      conn = ActiveRecord::Base.connection
      if Gem::Version.new(conn.database_version.join(".")) >= Gem::Version.new("12.2")
        expect(conn.supports_longer_identifier?).to be(true)
        expect(conn.max_identifier_length).to eq(128)
      else
        expect(conn.supports_longer_identifier?).to be(false)
        expect(conn.max_identifier_length).to eq(30)
      end
    end

    it "honors identifier_max_length: :short" do
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(identifier_max_length: :short))
      conn = ActiveRecord::Base.connection

      expect(conn.supports_longer_identifier?).to be(false)
      expect(conn.max_identifier_length).to eq(30)
    end

    it "honors identifier_max_length: :long on 12.2+" do
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(identifier_max_length: :long))
      conn = ActiveRecord::Base.connection

      if Gem::Version.new(conn.database_version.join(".")) >= Gem::Version.new("12.2")
        expect(conn.supports_longer_identifier?).to be(true)
        expect(conn.max_identifier_length).to eq(128)
      else
        expect { conn.supports_longer_identifier? }.to output(/falling back to 30 bytes/).to_stderr
      end
    end

    it "accepts YAML string values and coerces them via to_sym" do
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(identifier_max_length: "short"))
      conn = ActiveRecord::Base.connection

      expect(conn.supports_longer_identifier?).to be(false)
      expect(conn.max_identifier_length).to eq(30)
    end

    it "silently falls back to 30-byte identifiers on a pre-12.2 database with :auto" do
      conn = ActiveRecord::Base.connection
      allow(conn).to receive(:database_version).and_return([11, 2])
      expect(conn.supports_longer_identifier?).to be(false)
      expect(conn.max_identifier_length).to eq(30)
    end

    it "warns and falls back to 30-byte identifiers on a pre-12.2 database with :long" do
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(identifier_max_length: :long))
      conn = ActiveRecord::Base.connection
      allow(conn).to receive(:database_version).and_return([11, 2])
      expect {
        expect(conn.supports_longer_identifier?).to be(false)
      }.to output(/identifier_max_length = :long was requested but Oracle 11\.2 does not support 128 byte identifiers; falling back to 30 bytes/).to_stderr
      expect(conn.max_identifier_length).to eq(30)
    end

    it "emits the :long pre-12.2 fallback warning at most once per connection" do
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(identifier_max_length: :long))
      conn = ActiveRecord::Base.connection
      allow(conn).to receive(:database_version).and_return([11, 2])

      expect { conn.supports_longer_identifier? }.to output(/falling back to 30 bytes/).to_stderr
      expect {
        conn.supports_longer_identifier?
        conn.max_identifier_length
      }.not_to output.to_stderr
    end

    it "falls back to the global setting when the per-connection value is nil" do
      adapter_class.class_variable_set(:@@use_shorter_identifier, true)
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(identifier_max_length: nil))
      conn = ActiveRecord::Base.connection

      expect(conn.supports_longer_identifier?).to be(false)
      expect(conn.max_identifier_length).to eq(30)
    end

    it "raises ArgumentError for unknown symbol values" do
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(identifier_max_length: :bogus))
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
