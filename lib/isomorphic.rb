require "isomorphic/version"

module Isomorphic
  extend ::ActiveSupport::Autoload

  autoload :Factory,                   "isomorphic/factory"
  autoload :HashWithIndifferentAccess, "isomorphic/hash_with_indifferent_access"
  autoload :Inflector,                 "isomorphic/inflector"
  autoload :Lens,                      "isomorphic/lens"
  autoload :Memoization,               "isomorphic/memoization"
  autoload :Model,                     "isomorphic/model"
  autoload :Node,                      "isomorphic/node"
end
