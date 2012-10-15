module RbScope

  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def rb_scope(symbol, func)
      if Rails::VERSION::MAJOR < 3
        named_scope symbol, func
      else
        scope symbol, func
      end
    end
  end

end