# POST /key/fetch.json
# pgp_key_ids:  "6052b2ad31a6631c,980A3F0D01FE04DF"
# ops:          3
#
# Ops can be for:
#   1 — encrypt
#   2 — decrypt
#   4 — verify
#   8 — sign
#
# Bitmaskable
#
module Keybase::Core
  module Request
    class Key < Base
      OPS = {
        encrypt: 1,
        decrypt: 2,
        verify:  4,
        sign:    8,
      }

      # keys: an array of keys, ex: ["6052b2ad31a6631c", "980A3F0D01FE04DF"]
      # permissions, an array (or list) of permissions, ex: [:encrypt, :verify]
      #
      def self.fetch(keys, *permissions)
        params = {
          pgp_key_ids: keys.join(","),
          ops: ops(permissions)
        }

        get('key/fetch.json', params)['keys']
      end

      private

      def self.ops(ops)
        ops.map {|op| OPS[op]}.reduce(:|)
      end
    end
  end
end
