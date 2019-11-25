module Isomorphic
  # Generic base class for all Isomorphic errors.
  #
  # @abstract
  class IsomorphicError < ::StandardError
    # @!attribute [r] base
    #   @return [Module] the base module
    attr_reader :base

    # Default constructor.
    #
    # @param message [String] the message
    # @param base [Module] the base module
    def initialize(message = nil, base)
      @base = base

      super(message)
    end
  end
end
