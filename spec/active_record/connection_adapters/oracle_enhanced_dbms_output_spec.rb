require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

describe "OracleEnhancedAdapter logging dbms_output from plsql" do
  include LoggerSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    ActiveRecord::Base.connection.execute <<-SQL
    CREATE or REPLACE
    FUNCTION MORE_THAN_FIVE_CHARACTERS_LONG (some_text VARCHAR2) RETURN INTEGER
    AS
      longer_than_five INTEGER;
    BEGIN
      dbms_output.put_line('before the if -' || some_text || '-');
      IF length(some_text) > 5 THEN
        dbms_output.put_line('it is longer than 5');
        longer_than_five := 1;
      ELSE
        dbms_output.put_line('it is 5 or shorter');
        longer_than_five := 0;
      END IF;
      dbms_output.put_line('about to return: ' || longer_than_five);
      RETURN longer_than_five;
    END;
    SQL
  end

  after(:all) do
    ActiveRecord::Base.connection.execute "DROP FUNCTION MORE_THAN_FIVE_CHARACTERS_LONG"
  end

  before(:each) do
    set_logger
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
  end

  after(:each) do
    clear_logger
  end

  it "should NOT log dbms output when dbms output is disabled" do
    @conn.disable_dbms_output

    @conn.select_all("select more_than_five_characters_long('hi there') is_it_long from dual").should == [{'is_it_long'=>1}]

    @logger.output(:debug).should_not match(/^DBMS_OUTPUT/)
  end

  it "should log dbms output lines to the rails log" do
    @conn.enable_dbms_output

    @conn.select_all("select more_than_five_characters_long('hi there') is_it_long from dual").should == [{'is_it_long'=>1}]
    
    @logger.output(:debug).should match(/^DBMS_OUTPUT: before the if -hi there-$/)
    @logger.output(:debug).should match(/^DBMS_OUTPUT: it is longer than 5$/)
    @logger.output(:debug).should match(/^DBMS_OUTPUT: about to return: 1$/)
  end

  it "should log dbms output lines to the rails log" do
    @conn.enable_dbms_output

    @conn.select_all("select more_than_five_characters_long('short') is_it_long from dual").should == [{'is_it_long'=>0}]
    
    @logger.output(:debug).should match(/^DBMS_OUTPUT: before the if -short-$/)
    @logger.output(:debug).should match(/^DBMS_OUTPUT: it is 5 or shorter$/)
    @logger.output(:debug).should match(/^DBMS_OUTPUT: about to return: 0$/)
  end
end
