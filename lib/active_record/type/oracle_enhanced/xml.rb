# frozen_string_literal: true

require "active_model/type/string"
require "xmlhasher"

module ActiveRecord
  module Type
    module OracleEnhanced
      class XML < ActiveRecord::Type::String # :nodoc:
        def type
          :xmltype
        end

        def serialize(value)
          raise "XMLTYPE column must be of type Hash" unless value.is_a?(Hash)
          to_xml(value).first
        end

        def cast_value(value)
          value
        end

        def deserialize(value)
          XmlHasher.parse(value) if value.present?
        end

      private
        def to_xml(hash_obj)
          hash_obj.map do |key, value|
            noderize(key, value)
          end
        end

        def noderize(key, value)
          if value.class == Hash
            node_value = to_xml(value).join
          else
            node_value = value.nil? ? "" : value
          end

          "<#{key}>#{node_value}</#{key}>"
        end
      end
    end
  end
end
