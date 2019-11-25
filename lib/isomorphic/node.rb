require "active_support/concern"
require "active_support/core_ext/array/extract_options"
require "active_support/core_ext/object/try"
require "active_support/hash_with_indifferent_access"

require "isomorphic/errors"

require "isomorphic/lens"

module Isomorphic
  # Generic base class for Isomorphic node errors.
  #
  # @abstract
  class NodeError < Isomorphic::IsomorphicError
  end

  # Raised when the +:default+ option is not given in the constructor for a {Isomorphic::Node::Guard} node.
  class DefaultOptionNotFound < Isomorphic::NodeError
  end

  # Raised when the +:default+ option is not included in the array of values for a {Isomorphic::Node::Guard} node.
  class DefaultOptionNotIncluded < Isomorphic::NodeError
  end

  # Raised when an Isomorphic node cannot find a class.
  class InvalidNodeClass < Isomorphic::NodeError
    # @!attribute [r] klass
    #   @return [Class] the class
    attr_reader :klass

    # Default constructor.
    #
    # @param message [#to_s] the message
    # @param klass [Clsas] the class
    def initialize(message = nil, klass)
      super(message)

      @klass = klass
    end
  end

  # Raised when an object is not an instance of a class.
  class InvalidNodeObject < Isomorphic::NodeError
    # @!attribute [r] klass
    #   @return [Class] the class
    # @!attribute [r] object
    #   @return [Object] the object
    attr_reader :klass, :object

    # Default constructor.
    #
    # @param message [#to_s] the message
    # @param klass [Clsas] the class
    # @param object [Object] the object
    def initialize(message = nil, klass, object)
      super(message)

      @klass, @object = klass, object
    end
  end

  module Node
    module Internal
      # Included when the base class needs to perform deep equality testing.
      module DeepEquals
        extend ::ActiveSupport::Concern

        # @!scope instance

        # Are all attributes deep equal for the given object?
        #
        # @param base [Module] the base module
        # @param object [Object] the object
        # @param attributes [ActiveSupport::HashWithIndifferentAccess] the attributes
        # @return [Boolean] +true+ if all attribues are deep equal; otherwise, +false+
        def all_attributes_eql?(base, object, attributes = ::ActiveSupport::HashWithIndifferentAccess.new)
          attributes.try(:each_pair) do |pair|
            attribute_name, expected_value = *pair

            return false unless deep_eql?(base, expected_value, object.send(attribute_name))
          end

          true
        end

        private

        def deep_eql?(base, value, other_value)
          if value.class.parents[-2] == base
            if value.is_a?(::Array)
              return false unless other_value.is_a?(::Array) && (value.all? { |instance_for_value|
                other_value.any? { |instance_for_other_value|
                  deep_eql?(base, instance_for_value, instance_for_other_value)
                }
              })
            elsif value.is_a?(::String)
              return false unless (value.to_s == other_value.to_s)
            else
              attributes = value.class.instance_methods(false).reject { |method_name|
                method_name.to_s.ends_with?("=")
              }.inject(::ActiveSupport::HashWithIndifferentAccess.new) { |acc, method_name|
                value.send(method_name).try { |expected_value|
                  acc[method_name] = expected_value
                }

                acc
              }

              return false unless (value.class == other_value.class) && all_attributes_eql?(base, other_value, attributes)
            end
          else
            return false unless (value == other_value)
          end

          true
        end
      end

      # Included when the base class is a collection.
      module InstanceMethodsForCollection
        extend ::ActiveSupport::Concern

        included do
          include Isomorphic::Lens::Internal::InstanceMethodsForLens
        end

        # @!scope instance

        # Build an Isomorphic node for an Active Record association.
        #
        # @param options [Hash<Symbol, Object>] the options
        # @option options [Boolean] :allow_blank (false) +true+ if the new node should always return a non-+nil+ target
        # @option options [Hash<Symbol, Object>] :attributes ({}) default attributes for the target
        # @yieldparam node [Isomorphic::Node::Association] the Isomorphic node (member)
        # @yieldreturn [void]
        # @return [self]
        def association(**options, &block)
          node = Isomorphic::Node::Association.new(self, **options, &block)
          @__child_nodes << node
          node
        end

        # Build an Isomorphic node for an Active Record association (as an attribute) using an Isomorphic lens.
        #
        # @param lens_or_association [Isomorphic::Lens::AbstractLens, #to_s] the Isomorphic lens or the name of the Active Record association
        # @param options [Hash<Symbol, Object>] the options
        # @option options [Boolean] :allow_blank (false) +true+ if the new node should always return a non-+nil+ target
        # @option options [Hash<Symbol, Object>] :attributes ({}) default attributes for the target
        # @yieldparam node [Isomorphic::Node::Association] the Isomorphic node (member)
        # @yieldreturn [void]
        # @return [self]
        def association_for(lens_or_association, **options, &block)
          lens = lens_or_association.is_a?(Isomorphic::Lens::AbstractLens) ? lens_or_association : reflect_on_attribute(lens_or_association)

          association(**options.merge({
            get: ::Proc.new { |record| lens.get(record) },
            set: ::Proc.new { |record, value, xmlattr_acc| lens.set(record, value, xmlattr_acc) },
          }), &block)
        end

        # Build an Isomorphic node for zero or more members of a collection.
        #
        # @param isomorphism_class [Class] the class
        # @param options [Hash<Symbol, Object>] the options
        # @option options [Boolean] :allow_blank (false) +true+ if the new node should always return a non-+nil+ target
        # @option options [Hash<Symbol, Object>] :attributes ({}) default attributes for the target
        # @yieldparam node [Isomorphic::Node::Element] the Isomorphic node (member)
        # @yieldreturn [void]
        # @return [self]
        def element(isomorphism_class, **options, &block)
          node = Isomorphic::Node::Element.new(self, isomorphism_class, **options, &block)
          @__child_nodes << node
          node
        end

        # Build an Isomorphic node for a "guard" statement for an Active Record association using an Isomorphic lens.
        #
        # @param lens_or_attribute_name [Isomorphic::Lens::AbstractLens, #to_s] the Isomorphic lens or the name of the Active Record association
        # @param values [Array<Object>] the included values
        # @param options [Hash<Symbol, Object>] the options
        # @option options [Boolean] :allow_blank (false) +true+ if the new node should always return a non-+nil+ target
        # @option options [Hash<Symbol, Object>] :attributes ({}) default attributes for the target
        # @option options [Object] :default (nil) the default value, where more than one included value is given
        # @yieldparam node [Isomorphic::Node::GuardCollection] the Isomorphic node (collection)
        # @yieldreturn [void]
        # @return [self]
        def guard_association_for(lens_or_attribute_name, *values, **options, &block)
          lens = lens_or_attribute_name.is_a?(Isomorphic::Lens::AbstractLens) ? lens_or_attribute_name : reflect_on_attribute(lens_or_attribute_name)

          node = Isomorphic::Node::GuardCollection.new(self, lens, *values, **options, &block)
          @__child_nodes << node
          node
        end

        # Build an Isomorphic node for a value of a "namespace" statement that is within scope.
        #
        # @param namespace [#to_s] the namespace name
        # @param terms [Array<Object>] the inflectable terms
        # @param options [Hash<Symbol, Object>] the options
        # @option options [Boolean] :allow_blank (false) +true+ if the new node should always return a non-+nil+ target
        # @option options [Hash<Symbol, Object>] :attributes ({}) default attributes for the target
        # @yieldparam node [Isomorphic::Node::NamespaceAssociation] the Isomorphic node (member)
        # @yieldreturn [void]
        # @return [self]
        # @raise [Isomorphic::InflectorError] if an inflectable term is invalid
        def namespace_association_for(namespace, terms, **options, &block)
          key = inflector.isomorphism(terms)

          node = Isomorphic::Node::NamespaceAssociation.new(self, namespace, key, **options, &block)
          @__child_nodes << node
          node
        end
      end

      # Included when the base class is a member.
      module InstanceMethodsForMember
        extend ::ActiveSupport::Concern

        included do
          include Isomorphic::Lens::Internal::InstanceMethodsForLens
        end

        # @!scope instance

        # Build an Isomorphic node for an attribute.
        #
        # @param method_name [#to_s] the method name for the target
        # @param isomorphism_xmlattr_class [Class] the class for the target
        # @param options [Hash<Symbol, Object>] the options
        # @option options [Boolean] :allow_blank (false) +true+ if the new node should always return a non-+nil+ target
        # @option options [Hash<Symbol, Object>] :attributes ({}) default attributes for the target
        # @yieldparam node [Isomorphic::Node::Attribute] the Isomorphic node (member)
        # @yieldreturn [void]
        # @return [self]
        def attribute(method_name, isomorphism_xmlattr_class = nil, **options, &block)
          node = Isomorphic::Node::Attribute.new(self, method_name, isomorphism_xmlattr_class, **options, &block)
          @__child_nodes << node
          node
        end

        # Build an Isomorphic node for an attribute using the given lens.
        #
        # @param lens_or_attribute_name [Isomorphic::Lens::AbstractLens, #to_s] the Isomorphic lens or the name of the attribute
        # @param method_name [#to_s] the method name for the target
        # @param isomorphism_xmlattr_class [Class] the class for the target
        # @param options [Hash<Symbol, Object>] the options
        # @option options [Boolean] :allow_blank (false) +true+ if the new node should always return a non-+nil+ target
        # @option options [Hash<Symbol, Object>] :attributes ({}) default attributes for the target
        # @yieldparam node [Isomorphic::Node::Attribute] the Isomorphic node (member)
        # @yieldreturn [void]
        # @return [self]
        def attribute_for(lens_or_attribute_name, method_name, isomorphism_xmlattr_class = nil, **options, &block)
          lens = lens_or_attribute_name.is_a?(Isomorphic::Lens::AbstractLens) ? lens_or_attribute_name : reflect_on_attribute(lens_or_attribute_name)

          attribute(method_name, isomorphism_xmlattr_class, **options.merge({
            get: ::Proc.new { |record| lens.get(record) },
            set: ::Proc.new { |record, value, xmlattr_acc| lens.set(record, value, xmlattr_acc) },
          }), &block)
        end

        # Build an Isomorphic node for a collection.
        #
        # @param method_name [#to_s] the method name for the target
        # @param isomorphism_class [Class] the class for the target
        # @param options [Hash<Symbol, Object>] the options
        # @option options [Boolean] :allow_blank (false) +true+ if the new node should always return a non-+nil+ target
        # @option options [Hash<Symbol, Object>] :attributes ({}) default attributes for the target
        # @yieldparam node [Isomorphic::Node::Attribute] the Isomorphic node (collection)
        # @yieldreturn [void]
        # @return [self]
        def collection(method_name, isomorphism_class, **options, &block)
          node = Isomorphic::Node::Collection.new(self, method_name, isomorphism_class, **options, &block)
          @__child_nodes << node
          node
        end

        # Build an Isomorphic node for a +Proc+ that is called in the reverse direction only.
        #
        # @param options [Hash<Symbol, Object>] the options
        # @yieldparam instance [Object] the instance
        # @yieldparam record [ActiveRecord::Base] the record
        # @yieldparam xmlattr_acc [ActiveSupport::HashWithIndifferentAccess] the accumulator for XML attributes
        # @yieldparam scope [Isomorphic::Node::Internal::Scope] the scope
        # @yieldreturn [ActiveRecord::Record] the record
        # @return [self]
        def from(**options, &block)
          node = Isomorphic::Node::ProcFrom.new(self, **options, &block)
          @__child_nodes << node
          node
        end

        # Build an Isomorphic node for a "guard" statement for an attribute using an Isomorphic lens.
        #
        # @param lens_or_attribute_name [Isomorphic::Lens::AbstractLens, #to_s] the Isomorphic lens or the name of the attribute
        # @param values [Array<Object>] the included values
        # @param options [Hash<Symbol, Object>] the options
        # @option options [Boolean] :allow_blank (false) +true+ if the new node should always return a non-+nil+ target
        # @option options [Hash<Symbol, Object>] :attributes ({}) default attributes for the target
        # @option options [Object] :default (nil) the default value, where more than one included value is given
        # @yieldparam node [Isomorphic::Node::GuardCollection] the Isomorphic node (collection)
        # @yieldreturn [void]
        # @return [self]
        def guard_attribute_for(lens_or_attribute_name, *values, **options, &block)
          lens = lens_or_attribute_name.is_a?(Isomorphic::Lens::AbstractLens) ? lens_or_attribute_name : reflect_on_attribute(lens_or_attribute_name)

          node = Isomorphic::Node::GuardMember.new(self, lens, *values, **options, &block)
          @__child_nodes << node
          node
        end

        # Build an Isomorphic node for a member.
        #
        # @param method_name [#to_s] the method name for the target
        # @param isomorphism_class [Class] the class for the target
        # @param options [Hash<Symbol, Object>] the options
        # @option options [Boolean] :allow_blank (false) +true+ if the new node should always return a non-+nil+ target
        # @option options [Hash<Symbol, Object>] :attributes ({}) default attributes for the target
        # @yieldparam node [Isomorphic::Node::Attribute] the Isomorphic node (collection)
        # @yieldreturn [void]
        # @return [self]
        def member(method_name, isomorphism_class, **options, &block)
          node = Isomorphic::Node::Member.new(self, method_name, isomorphism_class, **options, &block)
          @__child_nodes << node
          node
        end

        # Build an Isomorphic node for a "namespace" statement using an Isomorphic lens.
        #
        # @param namespace [#to_s] the namespace name
        # @param lens_or_attribute_name [Isomorphic::Lens::AbstractLens, #to_s] the Isomorphic lens or the name of the attribute
        # @param options [Hash<Symbol, Object>] the options
        # @option options [Boolean] :allow_blank (false) +true+ if the new node should always return a non-+nil+ target
        # @option options [Hash<Symbol, Object>] :attributes ({}) default attributes for the target
        # @yieldparam node [Isomorphic::Node::NamespaceAssociation] the Isomorphic node (member)
        # @yieldreturn [void]
        # @return [self]
        def namespace(namespace, lens_or_attribute_name, **options, &block)
          lens = lens_or_attribute_name.is_a?(Isomorphic::Lens::AbstractLens) ? lens_or_attribute_name : reflect_on_attribute(lens_or_attribute_name)

          node = Isomorphic::Node::Namespace.new(self, namespace, lens, **options, &block)
          @__child_nodes << node
          node
        end

        # Build an Isomorphic node for a value of a "namespace" statement that is within scope.
        #
        # @param namespace [#to_s] the namespace name
        # @param terms [Array<Object>] the inflectable terms
        # @param method_name [#to_s] the method name for the target
        # @param isomorphism_xmlattr_class [Class] the class for the target
        # @param options [Hash<Symbol, Object>] the options
        # @option options [Boolean] :allow_blank (false) +true+ if the new node should always return a non-+nil+ target
        # @option options [Hash<Symbol, Object>] :attributes ({}) default attributes for the target
        # @yieldparam node [Isomorphic::Node::NamespaceAssociation] the Isomorphic node (member)
        # @yieldreturn [void]
        # @return [self]
        # @raise [Isomorphic::InflectorError] if an inflectable term is invalid
        def namespace_attribute_for(namespace, terms, method_name, isomorphism_xmlattr_class = nil, **options, &block)
          key = inflector.isomorphism(terms)

          node = Isomorphic::Node::NamespaceAttribute.new(self, namespace, key, method_name, isomorphism_xmlattr_class, **options, &block)
          @__child_nodes << node
          node
        end

        # Build an Isomorphic node for a +Proc+ that is called in the forward direction only.
        #
        # @param options [Hash<Symbol, Object>] the options
        # @yieldparam record [ActiveRecord::Base] the record
        # @yieldparam instance [Object] the instance
        # @yieldparam scope [Isomorphic::Node::Internal::Scope] the scope
        # @yieldreturn [Object] the instance
        # @return [self]
        def to(**options, &block)
          node = Isomorphic::Node::ProcTo.new(self, **options, &block)
          @__child_nodes << node
          node
        end
      end

      # Implements a tree of hashes, where retrieval is from the bottom-up.
      class Scope
        # @!attribute [r] parent
        #   @return [Isomorphic::Node::Internal::Scope] the parent scope
        attr_reader :parent

        # Default constructor.
        #
        # @param parent [Isomorphic::Node::Internal::Scope] the parent scope
        # @param inflector [Isomorphic::Inflector::AbstractInflector] the Isomorphic inflector
        def initialize(parent, inflector = nil)
          super()

          @parent, @inflector = parent, inflector

          @value_by_namespace_and_key = ActiveSupport::HashWithIndifferentAccess.new
        end

        # @!attribute [r] inflector
        #   @return [Isomorphic::Inflector::AbstractInflector] the inflector
        %i(inflector).each do |method_name|
          define_method(method_name) do
            if parent.is_a?(Isomorphic::Node::Internal::Scope)
              parent.send(method_name)
            else
              instance_variable_get(:"@#{method_name}")
            end
          end
        end

        # Build a new child scope for the given namespace.
        #
        # @param namespace [#to_s] the namespace name
        # @return [Isomorphic::Node::Internal::Scope] the new child scope
        def child(namespace)
          scope = self.class.new(self)

          scope.instance_variable_get(:@value_by_namespace_and_key).send(:[]=, namespace, inflector.convert_hash({}))

          scope
        end

        # Get the scoped value of the given key in the context of the given namespace.
        #
        # @param namespace [#to_s] the namespace name
        # @param key [#to_s] the key
        # @return [Object, nil] the value or +nil+ if the namespace or key are not defined
        def get(namespace, key)
          if @value_by_namespace_and_key.key?(namespace) && @value_by_namespace_and_key[namespace].key?(key)
            @value_by_namespace_and_key[namespace][key]
          elsif @parent.is_a?(self.class)
            @parent.get(namespace, key)
          else
            nil
          end
        end

        # The keys for the given namespace.
        #
        # @param namespace [#to_s] the namespace name
        # @return [Array<String>] the keys or +nil+ if the namespace is not defined
        def keys(namespace)
          if @value_by_namespace_and_key.key?(namespace)
            @value_by_namespace_and_key[namespace].keys
          else
            nil
          end
        end

        # The namespaces.
        #
        # @return [Array<String>] the namespace names
        def namespaces
          @value_by_namespace_and_key.keys
        end

        # Set the scoped value of the given key in the context of the given namespace.
        #
        # @param namespace [#to_s] the namespace name
        # @param key [#to_s] the key
        # @param value [Object] the value
        # @return [Object, nil] the value or +nil+ if the namespace is not defined
        def set(namespace, key, value)
          if @value_by_namespace_and_key.key?(namespace)
            @value_by_namespace_and_key[namespace][key] = value
          elsif @parent.is_a?(self.class)
            @parent.set(namespace, key, value)
          else
            nil
          end
        end

        # The values for the given namespace.
        #
        # @param namespace [#to_s] the namespace name
        # @return [Array<Object>, nil] the values or +nil+ if the namespace is not defined
        def values(namespace)
          keys(namespace).try(:inject, inflector.convert_hash({})) { |acc, key|
            acc[key] = get(namespace, key)
            acc
          }
        end
      end
    end

    # Generic base class for Isomorphic nodes.
    #
    # @abstract Subclass and override {#from_isomorphism} and {#to_isomorphism} to implement a custom class.
    class AbstractNode
      include Isomorphic::Node::Internal::DeepEquals

      # @!attribute [r] parent
      #   @return [Isomorphic::Node::AbstractNode] the parent node
      attr_reader :parent

      # @!attribute [r] options
      #   @return [Hash<Symbol, Object>] the options
      attr_reader :options

      # Default constructor.
      #
      # @param parent [Isomorphic::Node::AbstractNode] the parent node
      # @param args [Array<Object>] the arguments
      # @yieldparam [self]
      # @yieldreturn [void]
      def initialize(parent, *args, &block)
        super()

        @__cache_for_to_isomorphism_for = {}
        @__child_nodes = []

        @parent = parent

        @options = args.extract_options!

        unless block.nil?
          self.instance_exec(*args, &block)
        end
      end

      # @!attribute [r] factory
      #   @return [Isomorphic::Factory::AbstractFactory] the Isomorphic factory
      # @!attribute [r] inflector
      #   @return [Isomorphic::Inflector::AbstractInflector] the Isomorphic inflector
      %i(factory inflector).each do |method_name|
        define_method(method_name) do
          if parent.is_a?(Isomorphic::Node::AbstractNode)
            parent.send(method_name)
          else
            instance_variable_get(:"@#{method_name}")
          end
        end
      end

      # Converts the given instance to an Active Record record.
      #
      # @param scope [Isomorphic::Node::Internal::Scope] the scope
      # @param isomorphism_instance [Object] the instance
      # @param record [ActiveRecord::Base] the record (optional; when not provided, a new instance of the Active Record class is constructed)
      # @param xmlattr_acc [ActiveSupport::HashWithIndifferentAccess] the accumulator for XML attributes
      # @return [ActiveRecord::Base] the record
      def from_isomorphism(scope, isomorphism_instance, record = nil, xmlattr_acc = ::ActiveSupport::HashWithIndifferentAccess.new)
        raise ::NotImplementedError
      end

      # Converts the given Active Record record to an instance.
      #
      # @param scope [Isomorphic::Node::Internal::Scope] the scope
      # @param record [ActiveRecord::Base] the record
      # @param isomorphism_instance [Object] the instance (optional; when not provided, a new instance is constructed)
      # @return [Object] the instance
      def to_isomorphism(scope, record, isomorphism_instance = nil)
        raise ::NotImplementedError
      end

      # Returns the cached instance for the given Active Record record.
      #
      # @param record [ActiveRecord::Base] the record
      # @param args [Array<#to_s>] the method names
      # @return [Object] the cached instance
      def to_isomorphism_for(record, *args)
        args.inject(@__cache_for_to_isomorphism_for[record]) { |acc, arg|
          acc.try(:[], arg)
        }
      end
    end

    class Association < Isomorphic::Node::AbstractNode
      include Isomorphic::Node::Internal::InstanceMethodsForMember

      def from_isomorphism(scope, instance, record = nil, xmlattr_acc = ::ActiveSupport::HashWithIndifferentAccess.new)
        is_present = false

        instance.each do |instance_for_node|
          _set(scope, record, instance_for_node, xmlattr_acc).try { |record_for_node|
            is_present ||= true

            @__child_nodes.inject(false) { |acc, child_node| child_node.from_isomorphism(scope, instance_for_node, record_for_node, xmlattr_acc).nil? ? acc : true }
          }
        end

        if is_present
          record
        else
          nil
        end
      end

      def to_isomorphism(scope, record, instance = nil)
        instance_for_node_or_array = _get(scope, record).try { |instance_for_node_or_hash|
          @__cache_for_to_isomorphism_for[record] ||= instance_for_node_or_hash

          if instance_for_node_or_hash.is_a?(::Hash)
            instance_for_node_or_hash.values
          else
            instance_for_node_or_hash
          end
        }

        unless instance_for_node_or_array.nil?
          array = (instance_for_node_or_array.instance_of?(::Array) ? instance_for_node_or_array : [instance_for_node_or_array]).reject(&:nil?)

          if array.any? || options[:allow_blank]
            array.each do |instance_for_node|
              @__child_nodes.inject(false) { |acc, child_node| child_node.to_isomorphism(scope, record, instance_for_node).nil? ? acc : true }

              instance.send(:<<, instance_for_node)
            end

            instance_for_node_or_array
          else
            nil
          end
        else
          nil
        end
      end

      protected

      def _get(scope, record)
        options[:get].try { |block|
          case block.arity
            when 1 then block.call(record)
            else record.instance_eval(&block)
          end
        }
      end

      def _set(scope, record, instance_for_node, xmlattr_acc = ::ActiveSupport::HashWithIndifferentAccess.new)
        options[:set].try { |block|
          case block.arity
            when 3 then block.call(record, instance_for_node, xmlattr_acc)
            else record.instance_exec(instance_for_node, xmlattr_acc, &block)
          end
        }
      end
    end

    class Attribute < AbstractNode
      include Isomorphic::Node::Internal::InstanceMethodsForMember

      attr_reader :method_name

      attr_reader :xmlattr_class

      def initialize(parent, method_name, xmlattr_class = nil, **options, &block)
        super(parent, **options, &block)

        unless xmlattr_class.nil? || (xmlattr_class.is_a?(::Class) && (xmlattr_class.parents[-2] == parent.inflector.base))
          raise Isomorphic::InvalidNodeClass.new(nil, xmlattr_class)
        end

        @method_name = method_name

        @xmlattr_class = xmlattr_class
      end

      def from_isomorphism(scope, instance, record = nil, xmlattr_acc = ::ActiveSupport::HashWithIndifferentAccess.new)
        is_present = false

        instance_for_node = instance.send(method_name)

        is_valid = (xmlattr_class.nil? || instance_for_node.instance_of?(xmlattr_class)) && all_attributes_eql?(inflector.base, instance_for_node, options[:attributes].try(:each_pair).try(:inject, ::ActiveSupport::HashWithIndifferentAccess.new) { |acc, pair|
          xmlattr_name, value = *pair

          acc[:"xmlattr_#{xmlattr_name}"] = value
          acc
        })

        if is_valid && (!instance_for_node.nil? || options[:allow_nil])
          _set(scope, record, instance_for_node, xmlattr_acc).try { |record_for_node|
            is_present ||= true

            @__child_nodes.inject(false) { |acc, child_node| child_node.from_isomorphism(scope, instance_for_node, record_for_node, xmlattr_acc).nil? ? acc : true }
          }
        end

        if is_present
          record
        else
          nil
        end
      end

      def to_isomorphism(scope, record, instance = nil)
        instance_for_node = _get(scope, record).try { |retval_or_hash|
          @__cache_for_to_isomorphism_for[record] ||= retval_or_hash

          if retval_or_hash.is_a?(::Hash)
            retval_or_hash.values
          else
            retval_or_hash
          end
        }.try { |retval|
          if retval.class.parents[-2] == inflector.base
            @__child_nodes.inject(false) { |acc, child_node| child_node.to_isomorphism(scope, record, retval).nil? ? acc : true }

            retval
          else
            retval.try(:to_s).try { |s|
              if xmlattr_class.nil?
                s
              else
                instance_for_node = xmlattr_class.new(s)

                options[:attributes].try(:each_pair).try(:inject, {}) { |acc, pair|
                  xmlattr_name, value = *pair

                  acc[:"xmlattr_#{xmlattr_name}"] = value
                  acc
                }.try { |attributes|
                  factory.update_attributes(instance_for_node, attributes)
                }

                @__child_nodes.inject(false) { |acc, child_node| child_node.to_isomorphism(scope, record, instance_for_node).nil? ? acc : true }

                instance_for_node
              end
            }
          end
        }

        if !instance_for_node.nil? || options[:allow_nil]
          instance.send(:"#{method_name}=", instance_for_node)
        else
          nil
        end
      end

      protected

      def _get(scope, record)
        options[:get].try { |block|
          case block.arity
            when 1 then block.call(record)
            else record.instance_eval(&block)
          end
        }
      end

      def _set(scope, record, instance_for_node, xmlattr_acc = ::ActiveSupport::HashWithIndifferentAccess.new)
        options[:set].try { |block|
          case block.arity
            when 3 then block.call(record, instance_for_node, xmlattr_acc)
            else record.instance_exec(instance_for_node, xmlattr_acc, &block)
          end
        }
      end
    end

    class Collection < Isomorphic::Node::AbstractNode
      include Isomorphic::Node::Internal::InstanceMethodsForCollection

      attr_reader :method_name

      attr_reader :klass

      def initialize(parent, method_name, klass, **options, &block)
        super(parent, **options, &block)

        unless klass.is_a?(::Class) && (klass.parents[-2] == parent.inflector.base)
          raise Isomorphic::InvalidNodeClass.new(nil, klass)
        end

        @method_name = method_name
        @klass = klass
      end

      def from_isomorphism(scope, instance, record = nil, xmlattr_acc = ::ActiveSupport::HashWithIndifferentAccess.new)
        is_present = false

        instance.send(method_name).try { |instance_for_node|
          is_valid = instance_for_node.instance_of?(klass) && all_attributes_eql?(inflector.base, instance_for_node, options[:attributes])

          if is_valid
            is_present ||= @__child_nodes.inject(false) { |acc, child_node| child_node.from_isomorphism(scope, instance_for_node, record, xmlattr_acc).nil? ? acc : true }
          end
        }

        if is_present
          record
        else
          nil
        end
      end

      def to_isomorphism(scope, record, instance = nil)
        is_present = false

        instance_for_node = instance.send(method_name) || factory.for(klass)

        options[:attributes].try { |attributes|
          factory.update_attributes(instance_for_node, attributes)
        }

        is_present ||= @__child_nodes.inject(false) { |acc, child_node| child_node.to_isomorphism(scope, record, instance_for_node).nil? ? acc : true }

        if is_present || options[:allow_blank]
          instance.send(:"#{method_name}=", instance_for_node)

          instance_for_node
        else
          nil
        end
      end
    end

    class Element < Isomorphic::Node::AbstractNode
      include Isomorphic::Node::Internal::InstanceMethodsForMember

      attr_reader :klass

      def initialize(parent, klass, **options, &block)
        super(parent, **options, &block)

        unless klass.is_a?(::Class) && (klass.parents[-2] == parent.inflector.base)
          raise Isomorphic::InvalidNodeClass.new(nil, klass)
        end

        @klass = klass
      end

      def from_isomorphism(scope, instance, record = nil, xmlattr_acc = ::ActiveSupport::HashWithIndifferentAccess.new)
        is_present = false

        instance.try(:each) { |instance_for_node|
          is_valid = instance_for_node.instance_of?(klass) && all_attributes_eql?(inflector.base, instance_for_node, options[:attributes])

          if is_valid
            is_present ||= @__child_nodes.inject(options[:allow_blank]) { |acc, child_node| child_node.from_isomorphism(scope, instance_for_node, record, xmlattr_acc).nil? ? acc : true }
          end
        }

        if is_present
          record
        else
          nil
        end
      end

      def to_isomorphism(scope, record, instance = nil)
        is_present = false

        instance_for_node = factory.for(klass)

        options[:attributes].try { |attributes|
          factory.update_attributes(instance_for_node, attributes)
        }

        is_present ||= @__child_nodes.inject(false) { |acc, child_node| child_node.to_isomorphism(scope, record, instance_for_node).nil? ? acc : true }

        if is_present || options[:allow_blank]
          instance.send(:<<, instance_for_node)

          instance_for_node
        else
          nil
        end
      end
    end

    class Guard < Isomorphic::Node::AbstractNode
      attr_reader :lens

      attr_reader :values

      def initialize(parent, lens, *values, **options, &block)
        super(parent, **options, &block)

        unless (lens.is_a?(Isomorphic::Lens::Association) && lens.last_lens.is_a?(Isomorphic::Lens::Attribute)) || lens.is_a?(Isomorphic::Lens::Attribute)
          raise Isomorphic::LensInvalid.new(nil, lens)
        end

        if (values.size > 1) && !options.key?(:default)
          raise Isomorphic::DefaultOptionNotFound.new(nil)
        elsif options.key?(:default) && !values.include?(options[:default])
          raise Isomorphic::DefaultOptionNotIncluded.new(nil)
        end

        @lens = lens
        @values = values
      end

      def from_isomorphism(scope, instance, record = nil, xmlattr_acc = ::ActiveSupport::HashWithIndifferentAccess.new)
        is_present = @__child_nodes.inject(false) { |acc, child_node| child_node.from_isomorphism(scope, instance, record, xmlattr_acc).nil? ? acc : true }

        if is_present
          value = \
            case values.size
              when 1 then values[0]
              else options[:default]
            end

          lens.set(record, value, xmlattr_acc)

          record
        else
          nil
        end
      end

      def to_isomorphism(scope, record, instance = nil)
        lens.get(record).try { |value_or_hash|
          is_valid = \
            if value_or_hash.is_a?(::Hash)
              value_or_hash.values.all? { |value| values.include?(value) }
            else
              values.include?(value_or_hash)
            end

          if is_valid
            is_present = @__child_nodes.inject(false) { |acc, child_node| child_node.to_isomorphism(scope, record, instance).nil? ? acc : true }

            if is_present || options[:allow_blank]
              instance
            else
              nil
            end
          else
            nil
          end
        }
      end
    end

    class GuardCollection < Isomorphic::Node::Guard
      include Isomorphic::Node::Internal::InstanceMethodsForCollection
    end

    class GuardMember < Isomorphic::Node::Guard
      include Isomorphic::Node::Internal::InstanceMethodsForMember
    end

    class Member < Isomorphic::Node::AbstractNode
      include Isomorphic::Node::Internal::InstanceMethodsForMember

      attr_reader :method_name

      attr_reader :klass

      def initialize(parent, method_name, klass, **options, &block)
        super(parent, **options, &block)

        unless klass.is_a?(::Class) && (klass.parents[-2] == parent.inflector.base)
          raise Isomorphic::InvalidNodeClass.new(nil, klass)
        end

        @method_name = method_name
        @klass = klass
      end

      def from_isomorphism(scope, instance, record = nil, xmlattr_acc = ::ActiveSupport::HashWithIndifferentAccess.new)
        is_present = false

        instance.send(method_name).try { |instance_for_node|
          is_valid = instance_for_node.instance_of?(klass) && all_attributes_eql?(inflector.base, instance_for_node, options[:attributes])

          if is_valid
            is_present ||= @__child_nodes.inject(options[:allow_blank]) { |acc, child_node| child_node.from_isomorphism(scope, instance_for_node, record, xmlattr_acc).nil? ? acc : true }
          end
        }

        if is_present
          record
        else
          nil
        end
      end

      def to_isomorphism(scope, record, instance = nil)
        is_present = false

        instance_for_node = instance.send(method_name) || factory.for(klass)

        options[:attributes].try { |attributes|
          factory.update_attributes(instance_for_node, attributes)
        }

        is_present ||= @__child_nodes.inject(false) { |acc, child_node| child_node.to_isomorphism(scope, record, instance_for_node).nil? ? acc : true }

        if is_present || options[:allow_blank]
          instance.send(:"#{method_name}=", instance_for_node)

          instance_for_node
        else
          nil
        end
      end
    end

    class Namespace < Isomorphic::Node::AbstractNode
      include Isomorphic::Node::Internal::InstanceMethodsForMember

      attr_reader :namespace_name

      attr_reader :lens

      def initialize(parent, namespace_name, lens, **options, &block)
        super(parent, **options, &block)

        unless (lens.is_a?(Isomorphic::Lens::Association) && lens.last_lens.is_a?(Isomorphic::Lens::Isomorphism)) || lens.is_a?(Isomorphic::Lens::Isomorphism)
          raise Isomorphic::LensInvalid.new(nil, lens)
        end

        @namespace_name = namespace_name

        @lens = lens
      end

      def from_isomorphism(scope, instance, record = nil, xmlattr_acc = ::ActiveSupport::HashWithIndifferentAccess.new)
        new_scope = scope.child(namespace_name)

        is_present = @__child_nodes.inject(false) { |acc, child_node| child_node.from_isomorphism(new_scope, instance, record, xmlattr_acc).nil? ? acc : true }

        lens.set(record, new_scope.values(namespace_name), xmlattr_acc)

        if is_present
          record
        else
          nil
        end
      end

      def to_isomorphism(scope, record, instance = nil)
        new_scope = scope.child(namespace_name)

        lens.get(record).try { |hash|
          hash.each do |key, value|
            new_scope.set(namespace_name, key, value)
          end
        }

        is_present = @__child_nodes.inject(false) { |acc, child_node| child_node.to_isomorphism(new_scope, record, instance).nil? ? acc : true }

        if is_present || options[:allow_blank]
          instance
        else
          nil
        end
      end
    end

    class NamespaceAssociation < Isomorphic::Node::Association
      attr_reader :namespace_name, :key

      def initialize(parent, namespace_name, key, **options, &block)
        super(parent, **options, &block)

        @namespace_name = namespace_name
        @key = key
      end

      protected

      def _get(scope, record)
        scope.get(namespace_name, key)
      end

      def _set(scope, record, instance_for_node, xmlattr_acc = ::ActiveSupport::HashWithIndifferentAccess.new)
        scope.set(namespace_name, key, instance_for_node)
      end
    end

    class NamespaceAttribute < Isomorphic::Node::Attribute
      attr_reader :namespace_name, :key

      def initialize(parent, namespace_name, key, method_name, xmlattr_class = nil, **options, &block)
        super(parent, method_name, xmlattr_class, **options, &block)

        @namespace_name = namespace_name
        @key = key
      end

      protected

      def _get(scope, record)
        scope.get(namespace_name, key)
      end

      def _set(scope, record, instance_for_node, xmlattr_acc = ::ActiveSupport::HashWithIndifferentAccess.new)
        scope.set(namespace_name, key, instance_for_node)
      end
    end

    class ProcFrom < Isomorphic::Node::AbstractNode
      attr_reader :block

      def initialize(parent, **options, &block)
        # super(parent, **options)

        @block = block
      end

      def from_isomorphism(scope, instance, record = nil, xmlattr_acc = ::ActiveSupport::HashWithIndifferentAccess.new)
        if block.nil?
          record
        else
          case block.arity
            when 1 then block.call(instance)
            when 2 then block.call(instance, record)
            when 3 then block.call(instance, record, xmlattr_acc)
            when 4 then block.call(instance, record, xmlattr_acc, scope)
            else instance.instance_exec(record, xmlattr_acc, scope, &block)
          end
        end
      end

      def to_isomorphism(scope, record, instance = nil)
        instance
      end
    end

    class ProcTo < Isomorphic::Node::AbstractNode
      attr_reader :block

      def initialize(parent, **options, &block)
        # super(parent, **options)

        @block = block
      end

      def from_isomorphism(scope, instance, record = nil, xmlattr_acc = ::ActiveSupport::HashWithIndifferentAccess.new)
        record
      end

      def to_isomorphism(scope, record, instance = nil)
        if block.nil?
          instance
        else
          case block.arity
            when 1 then block.call(record)
            when 2 then block.call(record, instance)
            when 3 then block.call(record, instance, scope)
            else record.instance_exec(instance, scope, &block)
          end
        end
      end
    end

    class Root < Isomorphic::Node::AbstractNode
      attr_reader :record_class

      attr_reader :klass

      attr_reader :args

      def initialize(factory, inflector, record_class, klass, *args, &block)
        @factory = factory
        @inflector = inflector

        @record_class = record_class
        @klass = klass

        super(nil, *args, &block)

        unless klass.is_a?(::Class) && (klass.parents[-2] == inflector.base)
          raise Isomorphic::InvalidNodeClass.new(nil, klass)
        end
      end

      def from_isomorphism(instance, record = nil, xmlattr_acc = ::ActiveSupport::HashWithIndifferentAccess.new)
        unless instance.instance_of?(klass)
          raise Isomorphic::InvalidNodeObject.new(nil, klass, instance)
        end

        scope = Isomorphic::Node::Internal::Scope.new(nil, inflector)

        is_valid = all_attributes_eql?(inflector.base, instance, options[:attributes])

        if is_valid
          record_for_node = record || record_class.new

          @__child_nodes.each do |child_node|
            child_node.from_isomorphism(scope, instance, record_for_node, xmlattr_acc)
          end

          record_for_node
        else
          record
        end
      end

      def to_isomorphism(record, instance = nil)
        scope = Isomorphic::Node::Internal::Scope.new(nil, inflector)

        instance_for_node = instance || factory.for(klass)

        options[:attributes].try { |attributes|
          factory.update_attributes(instance_for_node, attributes)
        }

        is_present = @__child_nodes.inject(false) { |acc, child_node| child_node.to_isomorphism(scope, record, instance_for_node).nil? ? acc : true }

        if is_present || options[:allow_blank]
          instance_for_node
        else
          nil
        end
      end
    end

    class RootCollection < Isomorphic::Node::Root
      include Isomorphic::Node::Internal::InstanceMethodsForCollection
    end

    class RootMember < Isomorphic::Node::Root
      include Isomorphic::Node::Internal::InstanceMethodsForMember
    end
  end
end
