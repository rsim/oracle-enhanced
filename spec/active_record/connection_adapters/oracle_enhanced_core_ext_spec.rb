# encoding: utf-8

require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

describe "OracleEnhancedAdapter to_d method" do
  it "BigDecimal#to_d returns the same decimal number" do
    d = BigDecimal.new("12345678901234567890.0123456789")
    d.to_d.should == d
  end
  
  it "Bignum#to_d translates large integer to decimal" do
    n = 12345678901234567890
    n.to_d.should == BigDecimal.new(n.to_s)
  end

  it "Fixnum#to_d translates small integer to decimal" do
    n = 123456
    n.to_d.should == BigDecimal.new(n.to_s)
  end
end

if ENV['RAILS_GEM_VERSION'] >= '2.3'

  describe "OracleEnhancedAdapter Unicode aware upcase and downcase" do
    before(:all) do
      @down = "āčēģīķļņšūž"
      @up = "ĀČĒĢĪĶĻŅŠŪŽ"
    end

    it "should translate Unicode string to upcase" do
      @down.mb_chars.upcase.to_s.should == @up
    end

    it "should translate Unicode string to downcase" do
      @up.mb_chars.downcase.to_s.should == @down
    end
  
  end

end
