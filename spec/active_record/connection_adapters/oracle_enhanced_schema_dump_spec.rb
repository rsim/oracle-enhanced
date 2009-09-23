require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

describe "OracleEnhancedAdapter original schema dump" do

  before(:all) do
    if !defined?(RUBY_ENGINE)
      if ActiveRecord::Base.respond_to?(:oracle_connection)
        @old_conn = ActiveRecord::Base.oracle_connection(CONNECTION_PARAMS)
        @old_conn.class.should == ActiveRecord::ConnectionAdapters::OracleAdapter
      end
    elsif RUBY_ENGINE == 'jruby'
      @old_conn = ActiveRecord::Base.jdbc_connection(JDBC_CONNECTION_PARAMS)
      @old_conn.class.should == ActiveRecord::ConnectionAdapters::JdbcAdapter
    end

    @new_conn = ActiveRecord::Base.oracle_enhanced_connection(CONNECTION_PARAMS)
    @new_conn.class.should == ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter
  end

  after(:all) do
    # Workaround for undefining callback that was defined by JDBC adapter
    if defined?(RUBY_ENGINE) && RUBY_ENGINE == 'jruby'
      ActiveRecord::Base.class_eval do
        def after_save_with_oracle_lob
          nil
        end
      end
    end
  end

  if !defined?(RUBY_ENGINE) && ActiveRecord::Base.respond_to?(:oracle_connection) || defined?(RUBY_ENGINE) && RUBY_ENGINE == 'jruby'
    it "should return the same tables list as original oracle adapter" do
      @new_conn.tables.sort.should == @old_conn.tables.sort
    end

    it "should return the same index list as original oracle adapter" do
      @new_conn.indexes('employees').sort_by(&:name).should == @old_conn.indexes('employees').sort_by(&:name)
    end

    it "should return the same pk_and_sequence_for as original oracle adapter" do
      if @old_conn.respond_to?(:pk_and_sequence_for)
        @new_conn.tables.each do |t|
          @new_conn.pk_and_sequence_for(t).should == @old_conn.pk_and_sequence_for(t)
        end
      end
    end

    it "should return the same structure dump as original oracle adapter" do
      @new_conn.structure_dump.split(";\n\n").sort.should == @old_conn.structure_dump.split(";\n\n").sort
    end

    it "should return the same structure drop as original oracle adapter" do
      @new_conn.structure_drop.split(";\n\n").sort.should == @old_conn.structure_drop.split(";\n\n").sort
    end
  end

end

describe "OracleEnhancedAdapter structure dump" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
  end

  describe "database stucture dump extentions" do
    before(:all) do
      @conn.execute <<-SQL
        CREATE TABLE nvarchartable (
          unq_nvarchar  NVARCHAR2(255) DEFAULT NULL
        )
      SQL
    end

    after(:all) do
      @conn.execute "DROP TABLE nvarchartable"
    end

    it "should return the character size of nvarchar fields" do
      if /.*unq_nvarchar nvarchar2\((\d+)\).*/ =~ @conn.structure_dump
         "#$1".should == "255"
      end
    end
  end

end
