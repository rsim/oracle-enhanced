# frozen_string_literal: true

RSpec.describe "OracleEnhancedAdapter identifier length configuration" do
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

  def twelve_two_or_later?(conn)
    conn.database_version >= "12.2"
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

      expect(conn.max_identifier_length).to eq(30)
    end

    it "is overridden by an explicit per-connection identifier_max_length" do
      adapter_class.class_variable_set(:@@use_shorter_identifier, true)
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(identifier_max_length: :auto))
      conn = ActiveRecord::Base.connection

      if twelve_two_or_later?(conn)
        expect(conn.max_identifier_length).to eq(128)
      else
        expect(conn.max_identifier_length).to eq(30)
      end
    end
  end

  describe "supports_longer_identifier? (pure DB capability)" do
    it "reflects the connected database version, ignoring identifier_max_length config" do
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(identifier_max_length: :short))
      conn = ActiveRecord::Base.connection

      expect(conn.supports_longer_identifier?).to be(twelve_two_or_later?(conn))
    end
  end

  describe "identifier_max_length (per-connection)" do
    it "defaults to :auto when the key is absent" do
      conn = ActiveRecord::Base.connection
      if twelve_two_or_later?(conn)
        expect(conn.max_identifier_length).to eq(128)
      else
        expect(conn.max_identifier_length).to eq(30)
      end
    end

    it "honors identifier_max_length: :short" do
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(identifier_max_length: :short))
      conn = ActiveRecord::Base.connection

      expect(conn.max_identifier_length).to eq(30)
    end

    it "honors identifier_max_length: :long on 12.2+, raises ArgumentError on pre-12.2" do
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(identifier_max_length: :long))
      conn = ActiveRecord::Base.connection

      if twelve_two_or_later?(conn)
        expect(conn.max_identifier_length).to eq(128)
      else
        expect { conn.max_identifier_length }.to raise_error(
          ArgumentError,
          /identifier_max_length: :long requires Oracle 12\.2 or later \(connected server reports #{Regexp.escape(conn.database_version.to_s)}\)/
        )
      end
    end

    it "accepts YAML string values and coerces them via to_sym" do
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(identifier_max_length: "short"))
      conn = ActiveRecord::Base.connection

      expect(conn.max_identifier_length).to eq(30)
    end

    it "silently falls back to 30-byte identifiers on a pre-12.2 database with :auto" do
      conn = ActiveRecord::Base.connection
      skip "requires Oracle pre-12.2" if twelve_two_or_later?(conn)

      expect(conn.max_identifier_length).to eq(30)
    end

    it "falls back to the global setting when the per-connection value is nil" do
      adapter_class.class_variable_set(:@@use_shorter_identifier, true)
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(identifier_max_length: nil))
      conn = ActiveRecord::Base.connection

      expect(conn.max_identifier_length).to eq(30)
    end

    it "raises ArgumentError for unknown symbol values" do
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(identifier_max_length: :bogus))
      conn = ActiveRecord::Base.connection
      expect { conn.max_identifier_length }.to raise_error(
        ArgumentError,
        /Unknown identifier_max_length :bogus\. Expected :auto, :short, or :long/
      )
    end

    it "raises ArgumentError for unknown string values" do
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(identifier_max_length: "bogus"))
      conn = ActiveRecord::Base.connection
      expect { conn.max_identifier_length }.to raise_error(
        ArgumentError,
        /Unknown identifier_max_length :bogus\. Expected :auto, :short, or :long/
      )
    end

    it "raises ArgumentError for non-symbol/non-string values (e.g. booleans) per-connection" do
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(identifier_max_length: true))
      conn = ActiveRecord::Base.connection
      expect { conn.max_identifier_length }.to raise_error(
        ArgumentError,
        /identifier_max_length must be a String or Symbol \(got true\)\. Expected :auto, :short, or :long/
      )
    end

    it "lets per-connection identifier_max_length: :long win over use_shorter_identifier=true" do
      adapter_class.class_variable_set(:@@use_shorter_identifier, true)
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(identifier_max_length: :long))
      conn = ActiveRecord::Base.connection

      if twelve_two_or_later?(conn)
        expect(conn.max_identifier_length).to eq(128)
      else
        expect { conn.max_identifier_length }
          .to raise_error(ArgumentError, /identifier_max_length: :long requires Oracle 12\.2 or later/)
      end
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
