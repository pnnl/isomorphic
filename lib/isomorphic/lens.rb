require "active_support/concern"
require "active_support/core_ext/object/try"
require "active_support/hash_with_indifferent_access"

require "isomorphic/errors"

module Isomorphic
  # Generic base class for Isomorphic lens errors.
  #
  # @abstract
  class LensError < Isomorphic::IsomorphicError
  end

  # Raised when an Isomorphic lens is invalid.
  class InvalidLens < Isomorphic::LensError
    # @!attribute [r] lens
    #   @return [Isomorphic::Lens::AbstractLens] the lens
    attr_reader :lens

    # Default constructor.
    #
    # @param message [String] the message
    # @param lens [Isomorphic::Lens::AbstractLens] the lens
    def initialize(message = nil, lens)
      super(message)

      @lens = lens
    end
  end

  module Lens
    module Internal
      # Included when the base class has a +#factory+ and +#inflector+, and hence, can build Isomorphic lenses.
      module InstanceMethodsForLens
        extend ::ActiveSupport::Concern

        # Build a lens for the Active Record association with the given name.
        #
        # @param association [#to_s] the association name
        # @return [Isomorphic::Lens::Association] the lens
        def reflect_on_association(association)
          Isomorphic::Lens::Association.new(factory, inflector, association, nil)
        end

        # Build a lens for the attribute with the given name.
        #
        # @param attribute_name [#to_s] the attribute name
        # @param to [Proc] the optional modifier for after the getter
        # @param from [Proc] the optional modifier for before the setter
        # @return [Isomorphic::Lens::Attribute] the lens
        def reflect_on_attribute(attribute_name, to = nil, from = nil)
          Isomorphic::Lens::Attribute.new(factory, inflector, attribute_name, to, from)
        end

        # Build a lens for the given inflectable terms and optional arguments.
        #
        # @param terms [Array<Object>] the inflectable terms
        # @param args [Array<Object>] the arguments for the isomorphism
        # @return [Isomorphic::Lens::Isomorphism] the lens
        # @raise [Isomorphic::InflectorError] if an inflectable term is invalid
        def reflect_on_isomorphism(terms, *args)
          Isomorphic::Lens::Isomorphism.new(factory, inflector, terms, *args)
        end
      end
    end

    # Generic base class for Isomorphic lenses.
    #
    # @abstract Subclass and override {#_get} and {#set} to implement a custom class.
    class AbstractLens
      # @!attribute [r] factory
      #   @return [Isomorphic::Factory::AbstractFactory] the Isomorphic factory
      # @!attribute [r] inflector
      #   @return [Isomorphic::Inflector::AbstractInflector] the Isomorphic inflector
      attr_reader :factory, :inflector

      # Default constructor.
      #
      # @param factory [Isomorphic::Factory::AbstractFactory] the Isomorphic factory
      # @param inflector [Isomorphic::Inflector::AbstractInflector] the Isomorphic inflector
      def initialize(factory, inflector)
        super()

        @factory, @inflector = factory, inflector
      end

      # Getter.
      #
      # @param record_or_hash [ActiveRecord::Base, Hash<ActiveRecord::Base, ActiveRecord::Base>] the Active Record record or hash of records
      # @return [Object] the value of the getter
      # @raise [Isomorphic::InvalidLens] if the lens is invalid
      def get(record_or_hash)
        if record_or_hash.is_a?(::Hash)
          record_or_hash.each_pair.inject({}) { |acc, pair|
            association_record, record = *pair

            acc[association_record] = _get(record)
            acc
          }
        else
          _get(record_or_hash)
        end
      end

      # Setter.
      #
      # @param record [ActiveRecord::Base] the Active Record record
      # @param isomorphism_instance [Object] the instance
      # @param xmlattr_acc [ActiveSupport::HashWithIndifferentAccess] the accumulator of XML attributes by name
      # @return [Object] the value of the setter
      # @raise [Isomorphic::InvalidLens] if the lens is invalid
      def set(record, isomorphism_instance, xmlattr_acc = ::ActiveSupport::HashWithIndifferentAccess.new)
        raise ::NotImplementedError
      end

      protected

      def _get(record)
        raise ::NotImplementedError
      end
    end

    # An Isomorphic lens for an Active Record association.
    class Association < Isomorphic::Lens::AbstractLens
      # @!attribute [r] association
      #   @return [#to_s] the association name
      attr_reader :association

      # @!attribute [r] next_lens
      #   @return [Isomorphic::Lens::AbstractLens] the next lens or +nil+ if this is the last lens in the composition
      attr_reader :next_lens

      # Default constructor.
      #
      # @param factory [Isomorphic::Factory::AbstractFactory] the Isomorphic factory
      # @param inflector [Isomorphic::Inflector::AbstractInflector] the Isomorphic inflector
      # @param association [#to_s] the association name
      # @param next_lens [Isomorphic::Lens::AbstractLens] the next lens or +nil+ if this is the last lens in the composition
      def initialize(factory, inflector, association, next_lens = nil)
        super(factory, inflector)

        @association, @next_lens = association, next_lens
      end

      # Returns the last lens in the composition.
      #
      # @return [Isomorphic::Lens::AbstractLens] the last lens or +nil+ if this is the last lens in the composition
      def last_lens
        next_lens.try { |current_lens|
          while current_lens.is_a?(self.class)
            current_lens = current_lens.next_lens
          end
        }.try { |current_lens|
          current_lens.next_lens
        }
      end

      def set(record, isomorphism_instance, xmlattr_acc = ::ActiveSupport::HashWithIndifferentAccess.new)
        unless next_lens.is_a?(Isomorphic::Lens::AbstractLens)
          raise Isomorphic::InvalidLens.new(nil, self)
        end

        reflection = record.class.reflect_on_association(association)

        case reflection.macro
        when :has_many, :has_and_belongs_to_many
          raise Isomorphic::InvalidLens.new("invalid macro: #{reflection.macro}", self)
        when :has_one, :belongs_to
          next_lens.set(record.send(association) || record.send(:"build_#{association}"), isomorphism_instance, xmlattr_acc)
        else
          raise Isomorphic::InvalidLens.new("unknown macro: #{reflection.macro}", self)
        end
      end

      # Compose this lens with a new lens for the Active Record association with the given name.
      #
      # @param association [#to_s] the association name
      # @return [self]
      def reflect_on_association(association)
        append do
          self.class.new(factory, inflector, association, nil)
        end
      end

      # Compose this lens with a new lens for the attribute with the given name.
      #
      # @param attribute_name [#to_s] the attribute name
      # @param to [Proc] the optional modifier for after the getter
      # @param from [Proc] the optional modifier for before the setter
      # @return [self]
      def reflect_on_attribute(attribute_name, to = nil, from = nil)
        append do
          Isomorphic::Lens::Attribute.new(factory, inflector, attribute_name, to, from)
        end
      end

      # Compose this lens with a new lens for the given inflectable terms and optional arguments.
      #
      # @param terms [Array<Object>] the inflectable terms
      # @param args [Array<Object>] the arguments for the isomorphism
      # @return [self]
      # @raise [Isomorphic::InflectorError] if an inflectable term is invalid
      def reflect_on_isomorphism(terms, *args)
        append(with_next_lens: true) do |other|
          Isomorphic::Lens::IsomorphismAssociation.new(factory, inflector, other.association, terms, *args)
        end
      end

      protected

      def _get(record)
        unless next_lens.is_a?(Isomorphic::Lens::AbstractLens)
          raise Isomorphic::InvalidLens.new(nil, self)
        end

        reflection = record.class.reflect_on_association(association)

        case reflection.macro
        when :has_many, :has_and_belongs_to_many
          raise Isomorphic::InvalidLens.new("invalid macro: #{reflection.macro}", self)
        when :has_one, :belongs_to
          record.send(association).try { |association_record|
            next_lens.get(association_record)
          }
        else
          raise Isomorphic::InvalidLens.new("unknown macro: #{reflection.macro}", self)
        end
      end

      private

      def append(**options, &block)
        others = [self]
        current_lens = next_lens
        while current_lens.is_a?(self.class)
          others << current_lens
          current_lens = current_lens.next_lens
        end

        if options[:with_next_lens]
          if others.length == 1
            block.call(others[0])
          else
            others[0..-2].reverse.inject(block.call(others[-1])) { |acc, other|
              self.class.new(factory, inflector, other.association, acc)
            }
          end
        else
          others.reverse.inject(block.call) { |acc, other|
            self.class.new(factory, inflector, other.association, acc)
          }
        end
      end
    end

    # An Isomorphic lens for an attribute.
    class Attribute < Isomorphic::Lens::AbstractLens
      # @return [Proc] the identity morphism (returns the argument)
      IDENTITY = ::Proc.new { |x| x }.freeze

      # @!attribute [r] attribute_name
      #   @return [String] the attribute name
      attr_reader :attribute_name

      # @!attribute [r] to
      #   @return [Proc] the modifier for after the getter
      # @!attribute [r] from
      #   @return [Proc] the modifier for before the setter
      attr_reader :to, :from

      # Default constructor.
      #
      # @param factory [Isomorphic::Factory::AbstractFactory] the Isomorphic factory
      # @param inflector [Isomorphic::Inflector::AbstractInflector] the Isomorphic inflector
      # @param attribute_name [#to_s] the attribute name
      # @param to [Proc] the modifier for after the getter
      # @param from [Proc] the modifier for before the setter
      def initialize(factory, inflector, attribute_name, to = nil, from = nil)
        super(factory, inflector)

        @attribute_name = attribute_name

        @to = to || IDENTITY
        @from = from || IDENTITY
      end

      def set(record, isomorphism_instance, xmlattr_acc = ::ActiveSupport::HashWithIndifferentAccess.new)
        args = case from.arity
          when 1 then [isomorphism_instance]
          else [isomorphism_instance, xmlattr_acc]
        end

        record.instance_exec(*args, &from).try { |value|
          record.send(:"#{attribute_name}=", value)
        }
      end

      protected

      def _get(record)
        record.instance_exec(record.send(attribute_name), &to)
      end
    end

    # An Isomorphic lens for inflectable terms.
    class Isomorphism < Isomorphic::Lens::AbstractLens
      # @!attribute [r] terms
      #   @return [Array<Object>] the inflectable terms
      # @!attribute [r] args
      #   @return [Array<Object>] the arguments for the isomorphism
      attr_reader :terms, :args

      # @!attribute [r] method_name
      #   @return [#to_sym] the instance method name that was inflected from the given inflectable terms
      attr_reader :method_name

      # Default constructor.
      #
      # @param factory [Isomorphic::Factory::AbstractFactory] the Isomorphic factory
      # @param inflector [Isomorphic::Inflector::AbstractInflector] the Isomorphic inflector
      # @param terms [Array<Object>] the inflectable terms
      # @param args [Array<Object>] the arguments for the isomorphism
      # @raise [Isomorphic::InflectorError] if an inflectable term is invalid
      def initialize(factory, inflector, terms, *args)
        super(factory, inflector)

        @terms = terms
        @args = args

        @method_name = inflector.isomorphism(terms)
      end

      def set(record, isomorphism_instance, xmlattr_acc = ::ActiveSupport::HashWithIndifferentAccess.new)
        (record.class.try(:"has_#{method_name}?") ? record.class.send(:"from_#{method_name}", isomorphism_instance, record, xmlattr_acc, *args) : record.class.send(:"from_#{method_name}", isomorphism_instance, *args)).try { |association_record|
          factory.xmlattrs.try(:each) do |xmlattr_name|
            isomorphism_instance.try(:"xmlattr_#{xmlattr_name}").try { |xmlattr_value|
              xmlattr_acc[xmlattr_name] ||= {}
              xmlattr_acc[xmlattr_name][xmlattr_value] = association_record
            }
          end

          association_record
        }
      end

      protected

      def _get(record)
        record.class.try(:"has_#{method_name}?") ? record.send(:"to_#{method_name}", nil, *args) : record.send(:"to_#{method_name}", *args)
      end
    end

    # An Isomorphic lens for inflectable terms whose state is determined by an Active Record association.
    class IsomorphismAssociation < Isomorphic::Lens::Isomorphism
      # @!attribute [r] association
      #   @return [#to_s] the association name
      attr_reader :association

      # Default constructor.
      #
      # @param factory [Isomorphic::Factory::AbstractFactory] the Isomorphic factory
      # @param inflector [Isomorphic::Inflector::AbstractInflector] the Isomorphic inflector
      # @param association [#to_s] the association name
      # @param args [Array<Object>] the arguments for the isomorphism
      def initialize(factory, inflector, association, *args)
        super(factory, inflector, *args)

        @association = association
      end

      def set(record, isomorphism_instance, xmlattr_acc = ::ActiveSupport::HashWithIndifferentAccess.new)
        if association.nil?
          super(record, isomorphism_instance)
        else
          reflection = record.class.reflect_on_association(association)

          (reflection.klass.try(:"has_#{method_name}?") ? reflection.klass.send(:"from_#{method_name}", isomorphism_instance, nil, xmlattr_acc, *args) : reflection.klass.send(:"from_#{method_name}", isomorphism_instance, *args)).try { |association_record|
            case reflection.macro
            when :has_many, :has_and_belongs_to_many
              factory.xmlattrs.try(:each) do |xmlattr_name|
                isomorphism_instance.try(:"xmlattr_#{xmlattr_name}").try { |xmlattr_value|
                  xmlattr_acc[xmlattr_name] ||= {}
                  xmlattr_acc[xmlattr_name][xmlattr_value] = association_record
                }
              end

              record.send(association).send(:<<, association_record)
            when :has_one, :belongs_to
              factory.xmlattrs.try(:each) do |xmlattr_name|
                isomorphism_instance.try(:"xmlattr_#{xmlattr_name}").try { |xmlattr_value|
                  xmlattr_acc[xmlattr_name] ||= {}
                  xmlattr_acc[xmlattr_name][xmlattr_value] = association_record
                }
              end

              record.send(:"#{association}=", association_record)
            else
              raise Isomorphic::InvalidLens.new("unknown macro: #{reflection.macro}", self)
            end

            association_record
          }
        end
      end

      protected

      def _get(record)
        if association.nil?
          super(record)
        else
          reflection = record.class.reflect_on_association(association)

          case reflection.macro
          when :has_many, :has_and_belongs_to_many
            record.send(association).try { |collection_proxy|
              collection_proxy.to_a.inject({}) { |acc, association_record|
                acc[association_record] = reflection.klass.try(:"has_#{method_name}?") ? association_record.send(:"to_#{method_name}", nil, *args) : association_record.send(:"to_#{method_name}", *args)
                acc
              }
            }
          when :has_one, :belongs_to
            record.send(association).try { |association_record|
              reflection.klass.try(:"has_#{method_name}?") ? association_record.send(:"to_#{method_name}", nil, *args) : association_record.send(:"to_#{method_name}", *args)
            }
          else
            raise Isomorphic::InvalidLens.new("unknown macro: #{reflection.macro}", self)
          end
        end
      end
    end
  end
end
