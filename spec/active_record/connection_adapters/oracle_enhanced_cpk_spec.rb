require File.dirname(__FILE__) + '/../../spec_helper.rb'
require "composite_primary_keys"

describe "OracleEnhancedAdapter composite_primary_keys support" do

  before(:all) do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    class JobHistory < ActiveRecord::Base
      set_table_name "job_history"
      set_primary_keys :employee_id, :start_date
    end
  end

  after(:all) do
    Object.send(:remove_const, 'CompositePrimaryKeys') if defined?(CompositePrimaryKeys)
    Object.send(:remove_const, 'JobHistory') if defined?(JobHistory)
  end

  it "should tell ActiveRecord that count distinct is not supported" do
    ActiveRecord::Base.connection.supports_count_distinct?.should be_false
  end
  
  it "should execute correct SQL COUNT DISTINCT statement on table with composite primary keys" do
    lambda { JobHistory.count(:distinct => true) }.should_not raise_error
  end

  # Other testing was done based on composite_primary_keys tests

end