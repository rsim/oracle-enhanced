module ActiveRecord #:nodoc:
  module ConnectionAdapters #:nodoc:
    module OracleEnhancedVersion #:nodoc:
      MAJOR = 1
      MINOR = 2
      TINY  = 0

      STRING = [MAJOR, MINOR, TINY].join('.')
    end
  end
end
