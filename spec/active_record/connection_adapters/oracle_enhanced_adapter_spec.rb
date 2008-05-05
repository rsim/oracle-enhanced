require File.dirname(__FILE__) + '/../../spec_helper.rb'

describe "OracleEnhancedAdapter establish connection" do
  
  before(:all) do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
  end
  
  it "should connect to database" do
    ActiveRecord::Base.connection.should_not be_nil
    ActiveRecord::Base.connection.class.should == ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter
  end
  
end

describe "OracleEnhancedAdapter schema dump" do
  
  before(:all) do
    @old_conn = ActiveRecord::Base.oracle_connection(
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    @old_conn.class.should == ActiveRecord::ConnectionAdapters::OracleAdapter
    @new_conn = ActiveRecord::Base.oracle_enhanced_connection(
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    @new_conn.class.should == ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter
  end

  it "should return the same tables list as original oracle adapter" do
    @new_conn.tables.should == @old_conn.tables
  end

  it "should return the same pk_and_sequence_for as original oracle adapter" do
    @new_conn.tables.each do |t|
      @new_conn.pk_and_sequence_for(t).should == @old_conn.pk_and_sequence_for(t)
    end    
  end

  it "should return the same structure dump as original oracle adapter" do
    @new_conn.structure_dump.should == @old_conn.structure_dump
  end

  it "should return the same structure drop as original oracle adapter" do
    @new_conn.structure_drop.should == @old_conn.structure_drop
  end

end

describe "OracleEnhancedAdapter database session store" do
  before(:all) do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")

    ActiveRecord::Migration.create_table :sessions do |t|
      t.column :session_id, :string
      t.column :data, :text
      t.column :updated_at, :datetime
    end

  end

  after(:all) do
    ActiveRecord::Migration.drop_table :sessions
  end

  it "should create sessions table" do
    ActiveRecord::Base.connection.tables.grep("sessions").should_not be_empty
  end

  it "should save session data" do
    @session = CGI::Session::ActiveRecordStore::Session.new :session_id => "123456", :data  => "something", :updated_at => Time.now
    @session.save!
    @session = CGI::Session::ActiveRecordStore::Session.find_by_session_id("123456")
    @session.data.should == "something"
  end

end
