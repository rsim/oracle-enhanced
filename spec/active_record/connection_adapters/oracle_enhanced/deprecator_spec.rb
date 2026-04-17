# frozen_string_literal: true

describe ActiveRecord::ConnectionAdapters::OracleEnhanced do
  describe ".deprecator" do
    subject(:deprecator) { described_class.deprecator }

    it "returns an ActiveSupport::Deprecation" do
      expect(deprecator).to be_a(ActiveSupport::Deprecation)
    end

    it "sets the gem name to activerecord-oracle_enhanced-adapter" do
      expect(deprecator.gem_name).to eq("activerecord-oracle_enhanced-adapter")
    end

    it "sets the deprecation horizon to 'a future version'" do
      expect(deprecator.deprecation_horizon).to eq("a future version")
    end

    it "memoizes the instance" do
      expect(deprecator).to equal(described_class.deprecator)
    end

    it "includes the gem name and horizon in a deprecation warning" do
      expect { deprecator.deprecation_warning("legacy_thing") }
        .to output(/legacy_thing is deprecated.*activerecord-oracle_enhanced-adapter.*a future version/m)
        .to_stderr
    end

    it "emits a custom message when a method is deprecated through it" do
      test_class = Class.new do
        def legacy_method; end
        deprecate legacy_method: "use `modern_method` instead",
          deprecator: ActiveRecord::ConnectionAdapters::OracleEnhanced.deprecator
      end

      expect { test_class.new.legacy_method }
        .to output(/legacy_method is deprecated.*use `modern_method` instead/)
        .to_stderr
    end
  end
end
