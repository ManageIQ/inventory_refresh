require "manageiq/providers/cloud_manager"
require "vm"

module ManageIQ::Providers
  class CloudManager
    class Vm < ::Vm
      belongs_to :availability_zone
      belongs_to :cloud_tenant
    end
  end
end
