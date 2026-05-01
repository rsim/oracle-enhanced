# frozen_string_literal: true

describe "OracleEnhancedAdapter::Version" do
  let(:adapter_class) { ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter }
  let(:version_class) { adapter_class::Version }

  before(:each) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end

  after(:each) do
    ActiveRecord::Base.remove_connection
  end

  describe "subclassing" do
    it "is a subclass of AbstractAdapter::Version" do
      expect(version_class.ancestors).to include(ActiveRecord::ConnectionAdapters::AbstractAdapter::Version)
    end

    it "is the type returned by database_version" do
      conn = ActiveRecord::Base.connection
      expect(conn.database_version).to be_a(version_class)
    end
  end

  describe "Comparable" do
    it "compares against dotted version strings" do
      version = version_class.new("12.2", "12.2.0.1.0")
      expect(version >= "11.2").to be(true)   # 11gR2
      expect(version >= "12.1").to be(true)   # 12cR1
      expect(version >= "12.2").to be(true)   # itself
      expect(version >= "19.3").to be(false)  # 19c RU
      expect(version >= "23.4").to be(false)  # 23ai GA
      expect(version <= "23.4").to be(true)
    end

    it "preserves numerical monotonicity across the 23ai sub-era boundary" do
      # Year-based (`23.26`) is greater than the highest sequential (`23.9`).
      year_based = version_class.new("23.26", "23.26.0.0.0")
      sequential = version_class.new("23.9", "23.9.0.0.0")
      expect(year_based > "23.9").to be(true)
      expect(sequential < "23.26").to be(true)
      # Both are >= the old-scheme 12.2 baseline.
      expect(year_based >= "12.2").to be(true)
      expect(sequential >= "12.2").to be(true)
    end

    it "compares Version against another Version" do
      v12_2 = version_class.new("12.2")  # 12cR2
      v11_2 = version_class.new("11.2")  # 11gR2
      v23_4 = version_class.new("23.4")  # 23ai GA

      expect(v12_2 > v11_2).to be(true)
      expect(v11_2 < v12_2).to be(true)
      expect(v23_4 >= v12_2).to be(true)
      expect(v12_2 == version_class.new("12.2")).to be(true)
      expect(v12_2 != v11_2).to be(true)
    end
  end

  describe "to_s" do
    it "returns the parsed version string, not the Array inspect form" do
      version = version_class.new("12.2", "12.2.0.1.0")
      expect(version.to_s).to eq("12.2")
    end

    it "interpolates the same as join('.') on the previous Array shape" do
      conn = ActiveRecord::Base.connection
      expect("#{conn.database_version}").to eq(conn.database_version.to_s)
      expect(conn.database_version.to_s).to match(/\A\d+\.\d+\z/)
    end
  end

  describe "full_version_string" do
    it "returns the 5-part dotted form Oracle uses (per Oracle's release-numbering scheme)" do
      conn = ActiveRecord::Base.connection
      # Same shape on both drivers (per Oracle's documented release-numbering scheme):
      # 5 numerals separated by 4 dots, each part 1-2 digits.
      # Old scheme: major . maintenance . fusion_middleware . component . platform   (e.g. 12.2.0.1.0)
      # 23ai+:      major . RU_year . RU_quarter . MRP_level . recut                 (e.g. 23.26.0.0.0)
      # 23ai+ may zero-pad recut to 2 digits (e.g. "23.4.0.24.05"); other parts stay 1-2 digits.
      expect(conn.database_version.full_version_string).to match(/\A\d{1,2}(?:\.\d{1,2}){4}\z/)
    end
  end

  describe "deprecated Array-compat methods" do
    let(:version) { version_class.new("12.2", "12.2.0.1.0") }
    let(:deprecation_pattern) { /is deprecated/ }

    it "warns and returns the parsed major on #first" do
      expect {
        expect(version.first).to eq(12)
      }.to output(deprecation_pattern).to_stderr
    end

    it "warns and returns the parsed minor on #second" do
      expect {
        expect(version.second).to eq(2)
      }.to output(deprecation_pattern).to_stderr
    end

    it "warns and returns the parsed integer at the given index on #[]" do
      expect {
        expect(version[0]).to eq(12)
      }.to output(deprecation_pattern).to_stderr
      expect {
        expect(version[1]).to eq(2)
      }.to output(deprecation_pattern).to_stderr
    end

    it "warns and falls back to Array equality on `== [X, Y]`" do
      expect {
        expect(version == [12, 2]).to be(true)
      }.to output(deprecation_pattern).to_stderr
      expect {
        expect(version == [12, 1]).to be(false)
      }.to output(deprecation_pattern).to_stderr
    end

    it "does not warn for non-Array == comparisons" do
      expect {
        expect(version == "12.2").to be(true)
      }.not_to output(deprecation_pattern).to_stderr
    end
  end
end
