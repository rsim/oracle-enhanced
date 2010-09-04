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
