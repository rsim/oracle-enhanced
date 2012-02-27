require "bigdecimal"

unless BigDecimal.method_defined?(:to_d)
  BigDecimal.class_eval do
    def to_d #:nodoc:
      self
    end
  end
end

unless Bignum.method_defined?(:to_d)
  Bignum.class_eval do
    def to_d #:nodoc:
      BigDecimal.new(self.to_s)
    end
  end
end

unless Fixnum.method_defined?(:to_d)
  Fixnum.class_eval do
    def to_d #:nodoc:
      BigDecimal.new(self.to_s)
    end
  end
end
