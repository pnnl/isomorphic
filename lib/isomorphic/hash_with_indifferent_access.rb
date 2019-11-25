require "active_support/hash_with_indifferent_access"

module Isomorphic
  # Implements a hash where keys +:foo+, +"foo"+ and +Foo+ are considered to be the same.
  class HashWithIndifferentAccess < ::ActiveSupport::HashWithIndifferentAccess
    # @!attribute [r] inflector
    #   @return [Isomorphic::Inflector::AbstractInflector] the inflector
    attr_reader :inflector

    # Default constructor.
    #
    # @param inflector [Isomorphic::Inflector::AbstractInflector] the inflector
    # @param constructor [Hash, #to_hash] the hash or constructor for a hash
    # @raise [Isomorphic::InflectorError] if a key in the hash or the constructor for the hash is invalid
    def initialize(inflector, constructor = {})
      @inflector = inflector

      super(constructor)
    end

    # Same as {Hash#[]} where the key passed as argument can be either a string, a symbol or a class.
    #
    # @param key [Object] the key
    # @return [Object] the value
    # @raise [Isomorphic::InflectorError] if the key is invalid
    def [](key)
      super(convert_key(key))
    end

    # Same as {Hash#assoc} where the key passed as argument can be either a string, a symbol or a class.
    #
    # @param key [Object] the key
    # @return [Array<Object>, nil] the key-value pair or +nil+ if the key is not present
    # @raise [Isomorphic::InflectorError] if the key is invalid
    def assoc(key)
      super(convert_key(key))
    end

    if ::Hash.new.respond_to?(:dig)
      # Same as {Hash#dig} where the key passed as argument can be either a string, a symbol or a class.
      #
      # @param args [Array<Object>] the keys
      # @return [Object, nil] the value or nil
      # @raise [Isomorphic::InflectorError] if a key is invalid
      def dig(*args)
        args[0] = convert_key(args[0]) if args.size > 0
        super(*args)
      end
    end

    private

    # Inflect upon the given key.
    #
    # @param key [Object] the key
    # @return [String] the inflected key
    # @raise [Isomorphic::InflectorError] if the key is invalid
    def convert_key(key)
      inflector.isomorphism(key)
    end
  end
end
