require "isomorphic/errors"

module Isomorphic
  # Generic base class for Isomorphic factory errors.
  #
  # @abstract
  class FactoryError < Isomorphic::IsomorphicError
  end

  # Raised when an Isomorphic factory cannot find a class.
  class InvalidFactoryClass < Isomorphic::FactoryError
    # @!attribute [r] klass
    #   @return [Class] the class
    # @!attribute [r] const_name
    #   @return [#to_sym] the constant name
    attr_reader :klass, :const_name

    # Default constructor.
    #
    # @param message [#to_s] the message
    # @param base [Module] the base module
    # @param klass [Class] the class
    # @param const_name [#to_sym] the constant name
    def initialize(message = nil, base, klass, const_name)
      super(message, base)

      @klass, @const_name = klass, const_name
    end
  end

  module Factory
    # Generic base class for Isomorphic factories.
    #
    # @abstract Subclass and override {#const_get} and {#xmlattrs} to implement a custom class.
    class AbstractFactory
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

      # Build a new instance of the given class.
      #
      # @param klass [Class] the class
      # @param options [Hash<#to_sym, Object>] the options
      # @option options [Hash<#to_sym, Object>] :attributes ({}) the attributes for the new instance
      # @option options [Hash<#to_sym, #to_s>] :xmlattrs ({}) the XML attributes for the new instance
      # @yieldparam instance [Object] the new instance
      # @yieldreturn [void]
      # @return [Object] the new instance
      # @raise [Isomorphic::InvalidFactoryClass] if the given class cannot be found
      def for(klass, **options, &block)
        unless klass.is_a?(::Class) && (klass.parents[-2] == base)
          raise Isomorphic::InvalidFactoryClass.new(nil, base, klass, nil)
        end

        instance = klass.new

        if options.key?(:attributes)
          update_attributes(instance, options[:attributes])
        end

        send(:xmlattrs).select { |xmlattr_name|
          instance.respond_to?(:"xmlattr_#{xmlattr_name}=")
        }.each do |xmlattr_name|
          instance.send(:"xmlattr_#{xmlattr_name}=", send(:"xmlattr_#{xmlattr_name}_for", instance))
        end

        unless block.nil?
          case block.arity
            when 1 then block.call(instance)
            else instance.instance_eval(&block)
          end
        end

        instance
      end

      # Build a chain of new instances by reflecting on the instance methods for
      # the given instance and then return the end of the chain.
      #
      # @param instance [Object] the instance
      # @param method_names [Array<#to_sym>] the method names
      # @param options [Hash<#to_sym, Object>] the options
      # @option options [Boolean] :try (false) return +nil+ if any receiver in the chain is blank
      # @option options [Hash<#to_sym, Object>] :attributes ({}) the attributes for the new instance
      # @option options [Hash<#to_sym, #to_s>] :xmlattrs ({}) the XML attributes for the new instance
      # @return [Object, nil] the new instance or +nil+
      # @raise [Isomorphic::InvalidFactoryClass] if any class in the chain cannot be found
      def path(instance, *method_names, **options)
        method_names.inject([instance.class, instance]) { |pair, method_name|
          orig_class, orig_instance = *pair

          if orig_instance.nil? && options[:try]
            [::NilClass, orig_instance]
          else
            s = method_name.to_s
            const_name = s[0].upcase.concat(s[1..-1])

            new_class = const_get(base, orig_class, const_name)

            unless new_class.is_a?(::Class)
              raise Isomorphic::InvalidFactoryClass.new(nil, base, orig_class, const_name)
            end

            new_instance = orig_instance.send(method_name) || (options[:try] ? nil : orig_instance.send(:"#{method_name}=", send(:for, new_class)))

            [new_class, new_instance]
          end
        }[1]
      end

      # Is the chain of instances present?
      #
      # @param instance [Object] the instance
      # @param method_names [Array<#to_sym>] the method names
      # @return [Boolean] +true+ if the chain of instances is present; otherwise, +false+
      # @raise [Isomorphic::InvalidFactoryClass] if any class in the chain cannot be found
      def path?(instance, *method_names)
        !path(instance, *method_names, try: true).nil?
      end

      # Updates the attributes of the instance from the passed-in hash.
      #
      # @param instance [Object] the instance
      # @param attributes [Hash<#to_sym, Object>] the attributes
      # @return [void]
      #
      # @note Before assignment, attributes from the passed-in hash are duplicated.
      def update_attributes(instance, attributes = {})
        attributes.each do |method_name, value|
          instance.send(:"#{method_name}=", ::Marshal.load(::Marshal.dump(value)))
        end

        return
      end

      # Returns the array of XML attribute names that are accepted by this factory.
      #
      # @return [Array<#to_sym>] the XML attribute names
      #
      # @note For each XML attribute name, e.g., +name+, a corresponding instance method +#xmlattr_{name}_for(instance)+ must be defined.
      def xmlattrs
        []
      end

      protected

      # Checks for a constant with the given name in the base module.
      #
      # @param base [Module] the base module
      # @param klass [Class] the class
      # @param const_name [#to_sym] the constant name
      # @return [Class, Module, nil] the constant with the given name or +nil+ if not defined
      #
      # @note Subclasses override this instance method to implement custom dereferencing strategies for constants.
      def const_get(base, klass, const_name)
        if klass.const_defined?(const_name)
          klass.const_get(const_name)
        else
          nil
        end
      end
    end
  end
end
