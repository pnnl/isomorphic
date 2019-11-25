require "active_support/concern"
require "active_support/hash_with_indifferent_access"

require "isomorphic/node"

module Isomorphic
  # Included when the base class can define isomorphisms.
  module Model
    extend ::ActiveSupport::Concern

    class_methods do
      # @!scope class

      # Define an isomorphism for the given class and optional alias name.
      #
      # @param factory [Isomorphic::Factory::AbstractFactory] the Isomorphic factory
      # @param inflector [Isomorphic::Inflector::AbstractInflector] the Isomorphic inflector
      # @param isomorphism_class [Class] the class for the isomorphism
      # @param method_suffix [#to_s] the optional alias name for the isomorphism
      # @param options [Hash<Symbol, Object>] the options
      # @option options [Boolean] :allow_blank (false) +true+ if the root node should always return a non-+nil+ target
      # @option options [Hash<Symbol, Object>] :attributes ({}) default attributes for the target
      # @option options [Boolean] :collection (false) +true+ if the target is a collection
      # @yieldparam node [Isomorphic::Node::Root] the root node
      # @yieldreturn [void]
      # @return [void]
      # @raise [Isomorphic::InflectorError] if an inflectable term is invalid
      def isomorphism_for(factory, inflector, isomorphism_class, method_suffix = nil, **options, &block)
        isomorphism_method_name = inflector.isomorphism([[isomorphism_class, method_suffix]])

        # @!scope instance

        # @!method has_#{isomorphism_method_name}?
        #   Does the base class have an Isomorphic node for this isomorphism?
        #
        #   @return [Boolean] +true+
        define_singleton_method(:"has_#{isomorphism_method_name}?") do
          true
        end

        klass = options[:collection] ? Isomorphic::Node::RootCollection : Isomorphic::Node::RootMember

        # @!method build_isomorphic_node_for_#{isomorphism_method_name}(*args)
        #   Builds an Isomorphic node for this isomorphism.
        #
        #   @param args [Array<Object>] the arguments for the isomorphism
        #   @return [Isomorphic::Node::AbstractNode] the Isomorphic node
        define_singleton_method(:"build_isomorphic_node_for_#{isomorphism_method_name}") do |*args|
          klass.new(factory, inflector, self, isomorphism_class, *args, **options, &block)
        end

        # @!method from_#{isomorphism_method_name}(isomorphism_instance, record = nil, xmlattr_acc = ::ActiveSupport::HashWithIndifferentAccess.new, *args)
        #   Converts the given instance to an Active Record record.
        #
        #   @param isomorphism_instance [Object] the instance
        #   @param record [ActiveRecord::Base] the record (optional; when not provided, a new instance of the Active Record class is constructed)
        #   @param xmlattr_acc [ActiveSupport::HashWithIndifferentAccess] the accumulator for XML attributes
        #   @param args [Array<Object>] the arguments for the isomorphism
        #   @return [ActiveRecord::Base] the record
        define_singleton_method(:"from_#{isomorphism_method_name}") do |isomorphism_instance, record = nil, xmlattr_acc = ::ActiveSupport::HashWithIndifferentAccess.new, *args|
          node = send(:"build_isomorphic_node_for_#{isomorphism_method_name}", *args)

          node.from_isomorphism(isomorphism_instance, record, xmlattr_acc)
        end

        # @!method to_#{isomorphism_method_name}(isomorphism_instance = nil, *args)
        #   Converts the given Active Record record to an instance.
        #
        #   @param isomorphism_instance [Object] the instance (optional; when not provided, a new instance is constructed)
        #   @return [Object] the instance
        define_method(:"to_#{isomorphism_method_name}") do |isomorphism_instance = nil, *args|
          node = self.class.send(:"build_isomorphic_node_for_#{isomorphism_method_name}", *args)

          node.to_isomorphism(self, isomorphism_instance)
        end

        return
      end
    end

    # @!scope instance
  end
end
