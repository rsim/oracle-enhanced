# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters #:nodoc:
    module OracleEnhanced
      class TypeMetadata < DelegateClass(ActiveRecord::ConnectionAdapters::SqlTypeMetadata) # :nodoc:
        include Deduplicable

        attr_reader :virtual

        def initialize(type_metadata, virtual: nil)
          super(type_metadata)
          @type_metadata = type_metadata
          @virtual = virtual
        end

        def ==(other)
          other.is_a?(OracleEnhanced::TypeMetadata) &&
            attributes_for_hash == other.attributes_for_hash
        end
        alias eql? ==

        def hash
          attributes_for_hash.hash
        end

        protected
          def attributes_for_hash
            [self.class, @type_metadata, virtual]
          end
      end
    end
  end
end
