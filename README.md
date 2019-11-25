# isomorphic

Isomorphic is a Ruby library for specifying isomorphisms between Ruby objects.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'isomorphic'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install isomorphic

## Usage

In this example, we demonstrate how to use Isomorphic to specify an isomorphism between a Ruby on Rails model and a non-trivial `module`/`class` definition: [BuildingSync](https://buildingsync.net), an XML schema for building energy audit data.

We begin with the definition of the Ruby on Rails model:
```ruby
class Address < ActiveRecord::Base
  validates_presence_of :street_address, :city, :state, :postal_code
end
```

Our goal is to map instances of the Ruby on Rails model to/from the `<auc:Address>` XML element in [BuildingSync](https://buildingsync.net).

The [`soap4r`](https://github.com/rubyjedi/soap4r) gem provides the [`xsd2ruby.rb`](https://github.com/rubyjedi/soap4r/blob/master/bin/xsd2ruby.rb) binary for auto-generating Ruby code from an XML schema document.

An excerpt of the auto-generated Ruby code for [BuildingSync](https://buildingsync.net) is as follows:
```ruby
module BuildingSync
  # {http://buildingsync.net/schemas/bedes-auc/2019}Address
  #   streetAddressDetail - BuildingSync::Address::StreetAddressDetail
  #   city - SOAP::SOAPString
  #   state - BuildingSync::State
  #   postalCode - SOAP::SOAPString
  #   postalCodePlus4 - SOAP::SOAPString
  #   county - SOAP::SOAPString
  #   country - SOAP::SOAPString
  class Address

    # inner class for member: StreetAddressDetail
    # {http://buildingsync.net/schemas/bedes-auc/2019}StreetAddressDetail
    #   simplified - BuildingSync::Address::StreetAddressDetail::Simplified
    #   complex - BuildingSync::Address::StreetAddressDetail::Complex
    class StreetAddressDetail

      # inner class for member: Simplified
      # {http://buildingsync.net/schemas/bedes-auc/2019}Simplified
      #   streetAddress - SOAP::SOAPString
      #   streetAdditionalInfo - SOAP::SOAPString
      class Simplified
        attr_accessor :streetAddress
        attr_accessor :streetAdditionalInfo

        def initialize(streetAddress = nil, streetAdditionalInfo = nil)
          @streetAddress = streetAddress
          @streetAdditionalInfo = streetAdditionalInfo
        end
      end

      # inner class for member: Complex
      # {http://buildingsync.net/schemas/bedes-auc/2019}Complex
      #   streetNumberPrefix - SOAP::SOAPString
      #   streetNumberNumeric - BuildingSync::Address::StreetAddressDetail::Complex::StreetNumberNumeric
      #   streetNumberSuffix - SOAP::SOAPString
      #   streetDirPrefix - SOAP::SOAPString
      #   streetName - SOAP::SOAPString
      #   streetAdditionalInfo - SOAP::SOAPString
      #   streetSuffix - SOAP::SOAPString
      #   streetSuffixModifier - SOAP::SOAPString
      #   streetDirSuffix - SOAP::SOAPString
      #   subaddressType - SOAP::SOAPString
      #   subaddressIdentifier - SOAP::SOAPString
      class Complex

        # inner class for member: StreetNumberNumeric
        # {http://buildingsync.net/schemas/bedes-auc/2019}StreetNumberNumeric
        #   xmlattr_Source - SOAP::SOAPString
        class StreetNumberNumeric < ::String
          AttrSource = XSD::QName.new("http://buildingsync.net/schemas/bedes-auc/2019", "Source")

          def __xmlattr
            @__xmlattr ||= {}
          end

          def xmlattr_Source
            __xmlattr[AttrSource]
          end

          def xmlattr_Source=(value)
            __xmlattr[AttrSource] = value
          end

          def initialize(*arg)
            super
            @__xmlattr = {}
          end
        end

        attr_accessor :streetNumberPrefix
        attr_accessor :streetNumberNumeric
        attr_accessor :streetNumberSuffix
        attr_accessor :streetDirPrefix
        attr_accessor :streetName
        attr_accessor :streetAdditionalInfo
        attr_accessor :streetSuffix
        attr_accessor :streetSuffixModifier
        attr_accessor :streetDirSuffix
        attr_accessor :subaddressType
        attr_accessor :subaddressIdentifier

        def initialize(streetNumberPrefix = nil, streetNumberNumeric = nil, streetNumberSuffix = nil, streetDirPrefix = nil, streetName = nil, streetAdditionalInfo = nil, streetSuffix = nil, streetSuffixModifier = nil, streetDirSuffix = nil, subaddressType = nil, subaddressIdentifier = nil)
          @streetNumberPrefix = streetNumberPrefix
          @streetNumberNumeric = streetNumberNumeric
          @streetNumberSuffix = streetNumberSuffix
          @streetDirPrefix = streetDirPrefix
          @streetName = streetName
          @streetAdditionalInfo = streetAdditionalInfo
          @streetSuffix = streetSuffix
          @streetSuffixModifier = streetSuffixModifier
          @streetDirSuffix = streetDirSuffix
          @subaddressType = subaddressType
          @subaddressIdentifier = subaddressIdentifier
        end
      end

      attr_accessor :simplified
      attr_accessor :complex

      def initialize(simplified = nil, complex = nil)
        @simplified = simplified
        @complex = complex
      end
    end

    attr_accessor :streetAddressDetail
    attr_accessor :city
    attr_accessor :state
    attr_accessor :postalCode
    attr_accessor :postalCodePlus4
    attr_accessor :county
    attr_accessor :country

    def initialize(streetAddressDetail = nil, city = nil, state = nil, postalCode = nil, postalCodePlus4 = nil, county = nil, country = nil)
      @streetAddressDetail = streetAddressDetail
      @city = city
      @state = state
      @postalCode = postalCode
      @postalCodePlus4 = postalCodePlus4
      @county = county
      @country = country
    end
  end
end
```

First, we define a factory:
```ruby
class BuildingSyncFactory < Isomorphic::Factory::AbstractFactory
  include Singleton

  def initialize
    super(BuildingSync)
  end
end
```

Next, we define an inflector:
```ruby
class BuildingSyncInflector < Isomorphic::Factory::AbstractInflector
  include Singleton

  def initialize
    super(BuildingSync)
  end
end
```

Finally, we declare the isomorphism using the domain-specific language:
```ruby
class Address < ActiveRecord::Base
  validates_presence_of :street_address, :city, :state, :postal_code

  include Isomorphic::Model

  isomorphism_for(BuildingSyncFactory.instance, BuildingSyncInflector.instance, BuildingSync::Address) do
    member :streetAddressDetail, BuildingSync::Address::StreetAddressDetail do
      member :simplified, BuildingSync::Address::StreetAddressDetail::Simplified do
        attribute_for reflect_on_attribute(:street_address), :streetAddress
      end
    end
    attribute_for reflect_on_attribute(:city), :city
    attribute_for reflect_on_attribute(:state), :state
    attribute_for reflect_on_attribute(:postal_code), :postalCode
  end
end
```

Now, we can map instances of the Ruby on Rails model to/from the `<auc:Address>` XML element in [BuildingSync](https://buildingsync.net):
```ruby
orig_record = Address.new(street_address: '123 Fake Street', city: 'York', state: 'PA', postal_code: '17402')

building_sync_address = orig_record.to_building_sync_address

new_record = Address.from_building_sync_address(building_sync_address)
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## License

[The 2-Clause BSD License](https://opensource.org/licenses/BSD-2-Clause)

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/pnnl/isomorphic.
