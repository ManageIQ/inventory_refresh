require "manageiq/providers/cloud_manager"
require "vm"

module ManageIQ::Providers
  class CloudManager
    class Vm < ::Vm
      belongs_to :availability_zone
      belongs_to :cloud_tenant
      has_and_belongs_to_many :key_pairs,
        :join_table              => :key_pairs_vms,
        :foreign_key             => :vm_id,
        :association_foreign_key => :authentication_id,
        :class_name              => "ManageIQ::Providers::CloudManager::AuthKeyPair"
    end
  end
end
