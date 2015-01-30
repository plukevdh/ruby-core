module Keybase::Core
  # A Keybase user containing all attributes you have permission to see
  class User

    attr_reader :id, :basics, :invitation_stats, :profile, :emails,
                :public_keys, :private_keys

    def initialize(params)
      @id = params['id']
      @invitation_stats = OpenStruct.new(params['invitation_stats'])

      set_basics(params['basics'])             if params['basics']
      set_profile(params['profile'])           if params['profile']
      set_emails(params['emails'])             if params['emails']
      set_public_keys(params['public_keys'])   if params['public_keys']
      set_private_keys(params['private_keys']) if params['private_keys']
    end

    # Lookup a user on Keybase
    #
    # @param [String] username the username of the user you are searching for
    # @raise [Keybase::UserNotFoundError] if the user is not found
    # @raise [Keybase::InputError] if the username is empty or invalid
    # @return [Keybase::Model::User] the user, if they exist
    def self.lookup(username)
      new(Request::User.lookup(username))
    end

    # Login to Keybase
    #
    # @param [String] email_or_username the email or username of the account
    # @param [String] passphrase the passphrase for the account
    # @raise [Keybase::UserNotFoundError] if the user is not found
    # @raise [Keybase::InputError] if the submitted parameters are empty or invalid
    # @raise [Keybase::BadPasswordError] if the submitted passphrase is incorrect
    # @return [Keybase::Model::User] the user, if login is successful
    def self.login(email_or_username, passphrase)
      salt, login_session = Request::Root.get_salt_and_login_session(email_or_username)
      pwh = Crypto.scrypt(passphrase, salt)
      hmac_pwh = Crypto.hmac_sha512(pwh, login_session)
      response = Request::Root.login(email_or_username, hmac_pwh, login_session)
      return new(response['me'])
    end

    # Log out of Keybase
    #
    def logout
      return Request::Session.kill_all
    end

    # Post a self-signed authentication certificate to Keybase
    #
    # This requires login first.
    #
    # The payload of the signature should take the form of other keybase signatures,
    # like self-signing keys, or proving ownership of remote accounts.
    #
    # An example looks like:
    #
    # {
    #   "body": {
    #     "key": {
    #       "fingerprint": "da99a6ebeca98b14d944cb6e1ca9bfeab344f0fc",
    #       "host": "keybase.io",
    #       "key_id": "1ca9bfeab344f0fc",
    #       "uid": "15a9e2826313eaf005291a1ae00c3f00",
    #       "username": "taco422107"
    #     },
    #     "nonce": null,
    #     "type": "auth",
    #     "version": 1
    #   },
    #   "ctime": 1386537779,
    #   "expire_in": 86400,
    #   "tag": "signature"
    # }
    #
    # The client can provide an optional nonce to randomize the signatures. The server
    # will check the signature for validatity, and on success, will return an auth_token,
    # which is the SHA-256 hash of the full signature body, from the "---- BEGIN" all the
    # way through to the ---- END PGP MESSAGE ----.
    #
    # @param [String] sig the whole certificate contents
    # @raise [Keybase::InputError] if the certificate is empty or invalid
    # @raise [Keybase::BadSessionError] if the session is not valid
    # @raise [Keybase::CSRFVerificationError] if the CSRF token is not valid
    # @return [String] the authentication token
    def post_auth(sig)
      Request::Sig.post_auth(basics.username, sig)
    end

    # Add a new public key to Keybase
    #
    # This requires login first.
    #
    # @param [String] key the public key
    # @raise [Keybase::InputError] if the key is empty or invalid
    # @raise [Keybase::BadSessionError] if the session is not valid
    # @raise [Keybase::CSRFVerificationError] if the CSRF token is not valid
    # @return [String] The Key ID for the uploaded key
    def add_public_key(key)
      Request::Key.add(public_key: key)
    end

    # Add a new private key to Keybase
    #
    # This requires login first.
    #
    # @param [String] key the private key
    # @raise [Keybase::InputError] if the key is empty or invalid
    # @raise [Keybase::BadSessionError] if the session is not valid
    # @raise [Keybase::CSRFVerificationError] if the CSRF token is not valid
    # @return [String] The Key ID for the uploaded key
    def add_private_key(key)
      Request::Key.add(private_key: key)
    end

    # Revoke a key from Keybase
    #
    # This requires login first.
    #
    # Currently the key is simply deleted - full revokation is due in later
    # revisions of the API.
    #
    # @param [String] kid the key id to be revoked
    # @raise [Keybase::InputError] if the key id is empty or invalid
    # @raise [Keybase::BadSessionError] if the session is not valid
    # @raise [Keybase::CSRFVerificationError] if the CSRF token is not valid
    # @return [Boolean] success
    def revoke_key(kid)
      Request::Key.revoke(kid)
    end

    private

    def set_basics(params)
      @basics = OpenStruct.new(params.merge(created_at: nil, updated_at: nil))
      @basics.created_at = Time.at(@basics.ctime) if @basics.ctime
      @basics.updated_at = Time.at(@basics.mtime) if @basics.mtime
    end

    def set_profile(params)
      @profile = OpenStruct.new(params.merge(updated_at: nil))
      @profile.updated_at = Time.at(@profile.mtime) if @profile.mtime
    end

    def set_emails(params)
      @emails = OpenStruct.new(params)
      params.each do |k,v|
        v.merge!('is_verified?' => (v['is_verified'] == 1 ? true : false))
        @emails.send("#{k}=".to_sym, OpenStruct.new(v))
      end
    end

    def set_public_keys(params)
      @public_keys = OpenStruct.new(params)
      @public_keys = parse_data(params, @public_keys)
    end

    def set_private_keys(params)
      @private_keys = OpenStruct.new(params)
      @private_keys = parse_data(params, @private_keys)
    end

    def parse_data(params, collection)
      parse_primary(params, collection)
      parse_sub_keys('subkeys', params, collection)
      parse_sub_keys('sibkeys', params, collection)
      parse_families(params, collection)
    end

    def update_collection(key, data, collection)
      collection.send("#{k}=".to_sym, OpenStruct.new(v))
      collection
    end

    def parse_key(data)
      data.merge!('created_at' => Time.at(data['ctime']))
      data.merge!('updated_at' => Time.at(data['mtime']))

      OpenStruct.new(data)
    end

    def parse_primary(data, collection)
      collection.primary = parse_key(data["primary"])
    end

    # unsure of what this format looks like...
    def parse_sub_keys(key, data, collection)
      raw = data[key]
      return nil unless raw

      keys = raw.map do |key, key_info|
        parse_key(key_info)
      end

      collection.subkeys = keys
    end


    def parse_families(data, collection)
      families = {}

      fam_data = data['families']
      return nil unless fam_data

      fam_data.each do |key, keys|
        families[key] = keys.map do |key|
          parse_key(key)
        end
      end

      collection.families = families
    end
  end
end
