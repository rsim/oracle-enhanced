# frozen_string_literal: true

require "active_record/connection_adapters/oracle_enhanced/structure_dump"
require "active_record/connection_adapters/oracle_enhanced/structure_dump/dbms_metadata"

module ActiveRecord # :nodoc:
  module ConnectionAdapters # :nodoc:
    module OracleEnhanced # :nodoc:
      module StructureDump # :nodoc:
        # `OracleEnhancedAdapter.structure_dump_method` accepts:
        #
        # * `:auto` (default) — DBMS_METADATA on Oracle 12.1+, otherwise
        #   data-dictionary.
        # * `:dbms_metadata` — force DBMS_METADATA; raises `ArgumentError`
        #   on pre-12.1 (mirrors PR #2576's `identifier_max_length: :long`
        #   policy).
        # * `:data_dictionary` — force the implementation that assembles
        #   DDL from the ALL_* static data dictionary views in Ruby.
        module Dispatcher # :nodoc:
          def structure_dump
            case resolved_structure_dump_method
            when :dbms_metadata then dbms_metadata_structure_dump
            when :data_dictionary then super
            end
          end

          def structure_dump_db_stored_code
            case resolved_structure_dump_method
            when :dbms_metadata then dbms_metadata_structure_dump_db_stored_code
            when :data_dictionary then super
            end
          end

          def structure_dump_synonyms
            case resolved_structure_dump_method
            when :dbms_metadata then dbms_metadata_structure_dump_synonyms
            when :data_dictionary then super
            end
          end

          private
            def resolved_structure_dump_method
              case OracleEnhancedAdapter.structure_dump_method
              when :auto
                use_dbms_metadata_dump? ? :dbms_metadata : :data_dictionary
              when :dbms_metadata
                unless use_dbms_metadata_dump?
                  raise ArgumentError,
                    "structure_dump_method: :dbms_metadata requires Oracle 12.1 or later " \
                    "(connected server reports #{database_version}). " \
                    "Use :auto to fall back to :data_dictionary on older releases."
                end
                :dbms_metadata
              when :data_dictionary
                :data_dictionary
              else
                raise ArgumentError,
                  "Unknown structure_dump_method " \
                  "#{OracleEnhancedAdapter.structure_dump_method.inspect}; " \
                  "expected :auto, :dbms_metadata, or :data_dictionary."
              end
            end
        end

        include DbmsMetadata
        prepend Dispatcher
      end
    end
  end
end
