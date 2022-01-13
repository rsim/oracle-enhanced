# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module SchemaStatementsExt
        # Create primary key trigger (so that you can skip primary key value in INSERT statement).
        # By default trigger name will be "table_name_pkt", you can override the name with
        # :trigger_name option (but it is not recommended to override it as then this trigger will
        # not be detected by ActiveRecord model and it will still do prefetching of sequence value).
        #
        #   add_primary_key_trigger :users
        #
        # You can also create primary key trigger using +create_table+ with :primary_key_trigger
        # option:
        #
        #   create_table :users, :primary_key_trigger => true do |t|
        #     # ...
        #   end
        #
        def add_primary_key_trigger(table_name, options = {})
          # call the same private method that is used for create_table :primary_key_trigger => true
          create_primary_key_trigger(table_name, options)
        end
      end
    end
  end
end
