require "manageiq/providers/cloud_manager"
require "auth_key_pair"

module ManageIQ::Providers
  class CloudManager
    class AuthKeyPair < ::AuthKeyPair
      has_and_belongs_to_many :vms, :join_table => :key_pairs_vms, :foreign_key => :authentication_id
    end
  end
end
