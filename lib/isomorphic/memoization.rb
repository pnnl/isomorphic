require "active_support/concern"
require "active_support/core_ext/object/try"
require "active_support/hash_with_indifferent_access"

require "isomorphic/hash_with_indifferent_access"

module Isomorphic
  # Included when the base class can memo-cache the results of getters and setters of Isomorphic lenses.
  module Memoization
    extend ::ActiveSupport::Concern

    class_methods do
      # @!scope class

      # Defines finder methods and instance variables for the Active Record associations given by name.
      #
      # @param inflector [Isomorphic::Inflector::AbstractInflector] the Isomorphic inflector
      # @param terms [Array<Object>] the inflectable terms
      # @param association_names [Array<#to_s>] the association names
      # @param options [Hash<Symbol, Object>] the options
      # @option options [Array<#to_s>] :xmlattrs ([]) the XML attribute names
      # @return [void]
      # @raise [Isomorphic::InflectorError] if an inflectable term is invalid
      def memo_isomorphism_for(inflector, terms, *association_names, **options)
        method_name = inflector.isomorphism(terms)

        options[:xmlattrs].try(:each) do |xmlattr_name|
          association_names.each do |association_name|
            memo_isomorphism_method_names_by_association_name_for(inflector.base)[association_name] ||= []
            memo_isomorphism_method_names_by_association_name_for(inflector.base)[association_name] << method_name

            # @!scope instance

            # @!attribute [r] xmlattr_#{xmlattr_name}_for_#{method_name}_by_#{association_name}
            #   @return [ActiveSupport::HashWithIndifferentAccess] the cache of XML attributes
            attribute_name = :"@xmlattr_#{xmlattr_name}_for_#{method_name}_by_#{association_name}"

            # @!attribute [r] #{method_name}_by_xmlattr_#{xmlattr_name}
            #   @return [ActiveSupport::HashWithIndifferentAccess] the cache of instances
            isomorphism_attribute_name = :"@#{method_name}_by_xmlattr_#{xmlattr_name}"

            # @!method find_or_create_#{method_name}_for_#{association_name}!(record, *args, &block)
            #   Find or create the instance for the given Active Record record.
            #
            #   @param record [ActiveRecord::Base] the record
            #   @param args [Array<Object>] the arguments for the isomorphism
            #   @yieldparam [Object] the instance
            #   @yieldreturn [void]
            #   @return [Object] the instance
            define_method(:"find_or_create_#{method_name}_for_#{association_name}!") do |record, *args, &block|
              instance = (instance_variable_get(attribute_name) || instance_variable_set(attribute_name, ::ActiveSupport::HashWithIndifferentAccess.new)).try { |hash| hash[record] }.try { |xmlattr_for_record|
                (instance_variable_get(isomorphism_attribute_name) || instance_variable_set(isomorphism_attribute_name, ::ActiveSupport::HashWithIndifferentAccess.new)).try { |hash| hash[xmlattr_for_record] }
              }

              if instance.nil?
                instance = record.send(:"to_#{method_name}", *args)

                unless instance.nil?
                  if instance.respond_to?(:"xmlattr_#{xmlattr_name}")
                    xmlattr_for_record = instance.send(:"xmlattr_#{xmlattr_name}")

                    (instance_variable_get(attribute_name) || instance_variable_set(attribute_name, ::ActiveSupport::HashWithIndifferentAccess.new)).try { |hash|
                      hash[record] = xmlattr_for_record
                    }

                    (instance_variable_get(isomorphism_attribute_name) || instance_variable_set(isomorphism_attribute_name, ::ActiveSupport::HashWithIndifferentAccess.new)).try { |hash|
                      hash[xmlattr_for_record] = instance
                    }
                  end

                  unless block.nil?
                    case block.arity
                      when 1 then block.call(instance)
                      else instance.instance_eval(&block)
                    end
                  end
                end
              end

              instance
            end
          end
        end

        return
      end

      # Returns the memo-cahe.
      #
      # @param base [Module] the base module
      # @return [Hash<Module, ActiveSupport::HashWithIndifferentAccess>] the memo-cache
      def memo_isomorphism_method_names_by_association_name_for(base)
        unless class_variable_defined?(:"@@memo_isomorphism_method_names_by_association_name_for")
          class_variable_set(:"@@memo_isomorphism_method_names_by_association_name_for", {})
        end

        class_variable_get(:"@@memo_isomorphism_method_names_by_association_name_for")[base] ||= ::ActiveSupport::HashWithIndifferentAccess.new
      end
    end

    # @!scope instance

    # Find all memoized instances for the given Active Record record by XML attribute name.
    #
    # @param inflector [Isomorphic::Inflector::AbstractInflector] the Isomorphic inflector
    # @param record [ActiveRecord::Base] the Active Record record
    # @param options [Hash<Symbol, Object>] the options
    # @option options [Array<#to_s>] :xmlattrs ([]) the XML attribute names
    # @return [ActiveSupport::HashWithIndifferentAccess] the memoized instances by XML attribute name
    # @raise [Isomorphic::InflectorError] if an inflectable term is invalid
    def find_all_with_memo_isomorphism_for(inflector, record, **options)
      association_name = record.class.name.underscore.gsub("/", "_").to_sym

      options[:xmlattrs].try(:inject, ::ActiveSupport::HashWithIndifferentAccess.new) { |xmlattr_acc, xmlattr_name|
        xmlattr_acc[xmlattr_name] = self.class.memo_isomorphism_method_names_by_association_name_for(inflector.base)[association_name].try(:inject, inflector.convert_hash({})) { |acc, method_name|
          attribute_name = :"@xmlattr_#{xmlattr_name}_for_#{method_name}_by_#{association_name}"

          isomorphism_attribute_name = :"@#{method_name}_by_xmlattr_#{xmlattr_name}"

          acc[method_name] ||= instance_variable_get(attribute_name).try { |xmlattr_for_method_name_by_association_name|
            xmlattr_for_method_name_by_association_name[record].try { |xmlattr_for_method_name|
              instance_variable_get(isomorphism_attribute_name).try { |method_name_by_xmlattr|
                method_name_by_xmlattr[xmlattr_for_method_name]
              }
            }
          }

          acc
        }

        xmlattr_acc
      }
    end
  end
end
