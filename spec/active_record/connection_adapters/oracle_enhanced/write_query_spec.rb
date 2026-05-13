# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OracleEnhancedAdapter#write_query?" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
  end

  describe "PL/SQL anonymous blocks (Oracle-specific)" do
    it "classifies BEGIN ... END; as a write" do
      sql = "BEGIN DELETE FROM dual WHERE 1=0; END;"
      expect(@conn.write_query?(sql)).to be(true)
    end

    it "classifies DECLARE ... BEGIN ... END; as a write" do
      sql = "DECLARE v NUMBER; BEGIN v := 1; END;"
      expect(@conn.write_query?(sql)).to be(true)
    end

    it "classifies BEGIN with leading whitespace as a write" do
      expect(@conn.write_query?("  BEGIN NULL; END;")).to be(true)
    end

    it "classifies BEGIN preceded by a SQL comment as a write" do
      expect(@conn.write_query?("-- start of pl/sql\nBEGIN NULL; END;")).to be(true)
    end

    it "classifies BEGIN preceded by a /* */ block comment as a write" do
      expect(@conn.write_query?("/* pl/sql */ BEGIN NULL; END;")).to be(true)
    end

    it "is case-insensitive on the BEGIN keyword" do
      expect(@conn.write_query?("begin null; end;")).to be(true)
    end
  end

  describe "SELECT and CTEs" do
    it "classifies SELECT as a read" do
      expect(@conn.write_query?("SELECT 1 FROM dual")).to be(false)
    end

    it "classifies SELECT wrapped in parentheses as a read" do
      expect(@conn.write_query?("(SELECT 1 FROM dual)")).to be(false)
    end

    it "classifies WITH (CTE) as a read" do
      sql = "WITH x AS (SELECT 1 AS c FROM dual) SELECT c FROM x"
      expect(@conn.write_query?(sql)).to be(false)
    end

    it "classifies SELECT preceded by a SQL comment as a read" do
      expect(@conn.write_query?("-- comment\nSELECT 1 FROM dual")).to be(false)
    end
  end

  describe "Transaction control and session statements" do
    it "classifies COMMIT as a read" do
      expect(@conn.write_query?("COMMIT")).to be(false)
    end

    it "classifies ROLLBACK as a read" do
      expect(@conn.write_query?("ROLLBACK")).to be(false)
    end

    it "classifies SAVEPOINT as a read" do
      expect(@conn.write_query?("SAVEPOINT sp1")).to be(false)
    end

    it "classifies RELEASE SAVEPOINT as a read" do
      expect(@conn.write_query?("RELEASE SAVEPOINT sp1")).to be(false)
    end

    it "classifies SET TRANSACTION ISOLATION LEVEL as a read" do
      expect(@conn.write_query?("SET TRANSACTION ISOLATION LEVEL READ COMMITTED")).to be(false)
    end

    it "classifies SHOW (e.g. SHOW PARAMETER) as a read" do
      expect(@conn.write_query?("SHOW PARAMETER nls_date_format")).to be(false)
    end

    it "classifies EXPLAIN PLAN FOR SELECT as a read" do
      expect(@conn.write_query?("EXPLAIN PLAN FOR SELECT 1 FROM dual")).to be(false)
    end
  end

  describe "DML and DDL (writes)" do
    it "classifies INSERT as a write" do
      expect(@conn.write_query?("INSERT INTO users (id) VALUES (1)")).to be(true)
    end

    it "classifies UPDATE as a write" do
      expect(@conn.write_query?("UPDATE users SET name='x'")).to be(true)
    end

    it "classifies DELETE as a write" do
      expect(@conn.write_query?("DELETE FROM users WHERE id=1")).to be(true)
    end

    it "classifies MERGE as a write" do
      sql = "MERGE INTO users u USING dual ON (u.id=1) WHEN MATCHED THEN UPDATE SET u.name='x'"
      expect(@conn.write_query?(sql)).to be(true)
    end

    it "classifies CREATE TABLE as a write" do
      expect(@conn.write_query?("CREATE TABLE t (id NUMBER)")).to be(true)
    end

    it "classifies ALTER TABLE as a write" do
      expect(@conn.write_query?("ALTER TABLE t ADD c2 NUMBER")).to be(true)
    end

    it "classifies TRUNCATE as a write" do
      expect(@conn.write_query?("TRUNCATE TABLE t")).to be(true)
    end

    it "classifies LOCK TABLE as a write" do
      expect(@conn.write_query?("LOCK TABLE t IN EXCLUSIVE MODE")).to be(true)
    end
  end
end
