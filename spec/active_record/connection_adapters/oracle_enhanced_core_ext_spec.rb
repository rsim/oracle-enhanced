# encoding: utf-8
require 'spec_helper'

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
