require "bigdecimal"
unless BigDecimal.instance_methods.include?("to_d")
  BigDecimal.class_eval do
    def to_d #:nodoc:
      self
    end
  end
end

unless Bignum.instance_methods.include?("to_d")
  Bignum.class_eval do
    def to_d #:nodoc:
      BigDecimal.new(self.to_s)
    end
  end
end

unless Fixnum.instance_methods.include?("to_d")
  Fixnum.class_eval do
    def to_d #:nodoc:
      BigDecimal.new(self.to_s)
    end
  end
end

# Add Unicode aware String#upcase and String#downcase methods when mb_chars method is called
if defined?(RUBY_ENGINE) && RUBY_ENGINE == 'ruby' && RUBY_VERSION >= '1.9'
  begin
    require "unicode_utils/upcase"
    require "unicode_utils/downcase"

    module ActiveRecord #:nodoc:
      module ConnectionAdapters #:nodoc:
        module OracleEnhancedUnicodeString #:nodoc:
          def upcase #:nodoc:
            UnicodeUtils.upcase(self)
          end

          def downcase #:nodoc:
            UnicodeUtils.downcase(self)
          end
        end
      end
    end

    class String #:nodoc:
      def mb_chars #:nodoc:
        self.extend(ActiveRecord::ConnectionAdapters::OracleEnhancedUnicodeString)
        self
      end
    end

  rescue LoadError
    warning_message = "WARNING: Please install unicode_utils gem to support Unicode aware upcase and downcase for String#mb_chars"
    if defined?(Rails.logger) && Rails.logger
      Rails.logger.warn warning_message
    elsif defined?(RAILS_DEFAULT_LOGGER) && RAILS_DEFAULT_LOGGER
      RAILS_DEFAULT_LOGGER.warn warning_message
    else
      STDERR.puts warning_message
    end
  end

  
end
