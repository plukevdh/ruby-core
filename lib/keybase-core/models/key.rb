module Keybase::Core
  # A Keybase user containing all attributes you have permission to see
  class Key
    extend Forwardable

    def self.fetch(ids, ops)
      keys = Request::Key.fetch(ids, ops)
      keys.map {|key| new key }
    end

    def_delegators :@key, :uid, :bundle, :username, :kid, :fingerprint, :subkeys

    def initialize(params)
      @key = OpenStruct.new params
    end

    %w[self_signed secret primary_bundle_in_keyring].each do |name|
      define_method "#{name}?" do
        is? @key.send name
      end
    end

    private

    def is?(var)
      var == 1
    end
  end
end
