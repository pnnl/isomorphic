require "active_support/inflector"

require "isomorphic/errors"
require "isomorphic/hash_with_indifferent_access"

module Isomorphic
  # Generic base class for Isomorphic inflector errors.
  #
  # @abstract
  class InflectorError < Isomorphic::IsomorphicError
  end

  # Raised when an Isomorphic inflector cannot find a class.
  class InvalidInflectionClass < Isomorphic::InflectorError
    # @!attribute [r] klass
    #   @return [Class] the class
    attr_reader :klass

    # Default constructor.
    #
    # @param message [#to_s] the message
    # @param base [Module] the base module
    # @param klass [Class] the class
    def initialize(message = nil, base, klass)
      super(message, base)

      @klass = klass
    end
  end

  # Raised when an Isomorphic inflector cannot find an instance method by name.
  class InvalidInflectionMethodName < Isomorphic::InflectorError
    # @!attribute [r] method_name
    #   @return [#to_sym] the method name
    attr_reader :method_name

    # Default constructor.
    #
    # @param message [#to_s] the message
    # @param base [Module] the base module
    # @param method_name [#to_sym] the method name
    def initialize(message = nil, base, method_name)
      super(message, base)

      @method_name = method_name
    end
  end

  # Raised when an Isomorphic inflector cannot find an inflectable term.
  class InvalidInflectionTerm < Isomorphic::InflectorError
    # @!attribute [r] term
    #   @return [Object] the inflectable term
    attr_reader :term

    # Default constructor.
    #
    # @param message [#to_s] the message
    # @param base [Module] the base module
    # @param term [Object] the inflectable term
    def initialize(message = nil, base, term)
      super(message, base)

      @term = term
    end
  end

  module Inflector
    # Generic base class for Isomorphic inflectors.
    #
    # @abstract
    class AbstractInflector
      # @!attribute [r] base
      #   @return [Module] the base module
      attr_reader :base

      # Default constructor
      #
      # @param base [Module] the base module
      def initialize(base)
        super()

        @base = base
      end

      # Inflect upon the given hash or constructor for a hash.
      #
      # @param constructor [Hash, #to_hash] the hash or constructor for a hash
      # @return [Isomorphic::HashWithIndifferentAccess] the inflected hash
      # @raise [Isomorphic::InflectorError] if a key in the given hash or constructor for a hash is invalid
      def convert_hash(constructor = {})
        Isomorphic::HashWithIndifferentAccess.new(self, constructor)
      end

      # Inflect upon the given terms.
      #
      # @example Inflect upon a {String}
      #   Isomorphic::Inflector.new(Foo).isomorphism("bar") #=> "foo_bar"
      # @example Inflect upon a {Symbol}
      #   Isomorphic::Inflector.new(Foo).isomorphism(:bar) #=> "foo_bar"
      # @example Inflect upon a {Class}
      #   Isomorphic::Inflector.new(Foo).isomorphism(Foo::Bar) #=> "foo_bar"
      # @example Inflect upon an {Array} of inflectable terms
      #   Isomorphic::Inflector.new(Foo).isomorphism(["bar", "fum", "baz"]) #=> "foo_bar_and_foo_fum_and_foo_baz"
      # @example Inflect upon an inflectable term-alias pair
      #   Isomorphic::Inflector.new(Foo).isomorphism([["bar", "ex1"]]) #=> "foo_bar_as_ex1"
      # @example Inflect upon an {Array} of inflectable term-alias pairs
      #   Isomorphic::Inflector.new(Foo).isomorphism([["bar", "ex1"], ["bar", "ex2"], ["bar", "ex3"]]) #=> "foo_bar_as_ex1_and_foo_bar_as_ex2_and_foo_bar_as_ex3"
      #
      # @param terms [Array<Object>] the inflectable terms
      # @return [String] the inflection
      # @raise [Isomorphic::InflectorError] if an inflectable term is invalid
      def isomorphism(terms)
        isomorphism_for(terms)
      end

      protected

      # Converts the name of the given class.
      #
      # @param klass [Class] the class
      # @return [String] the underscored name of the class, where occurrences of +"/"+ are replaced with +"_"+
      def convert_class(klass)
        ::ActiveSupport::Inflector.underscore(klass.name).gsub("/", "_")
      end

      private

      def isomorphism_for(terms)
        unless terms.is_a?(::Array)
          terms = [terms]
        end

        terms.collect { |term|
          case term
            when ::Array            then isomorphism_for_array(term)
            when ::Class            then isomorphism_for_class(term)
            when ::String, ::Symbol then isomorphism_for_method_name(term)
            else raise Isomorphic::InvalidInflectionTerm.new(nil, base, term)
          end
        }.join("_and_")
      end

      def isomorphism_for_array(array)
        method_name = \
          case array[0]
            when ::Class            then isomorphism_for_class(array[0])
            when ::String, ::Symbol then isomorphism_for_method_name(array[0])
            else raise Isomorphic::InvalidInflectionTerm.new(nil, base, array)
          end

        method_suffix = \
          case array[1]
            when ::NilClass         then ""
            when ::String, ::Symbol then ::Kernel.sprintf("_as_%s", array[1])
            else raise Isomorphic::InvalidInflectionTerm.new(nil, base, array)
          end

        "#{method_name}#{method_suffix}"
      end

      def isomorphism_for_class(klass)
        unless klass.is_a?(::Class) && (klass.parents[-2] == base)
          raise Isomorphic::InvalidInflectionClass.new(nil, base, klass)
        end

        convert_class(klass)
      end

      def isomorphism_for_method_name(method_name)
        s = method_name.to_s

        unless s.starts_with?(::Kernel.sprintf("%s_", convert_class(base)))
          raise Isomorphic::InvalidInflectionMethodName.new(nil, base, method_name)
        end

        s
      end
    end
  end
end
