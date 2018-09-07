require "manageiq/providers/base_manager"

module ManageIQ
  module Providers
    class NetworkManager < ManageIQ::Providers::BaseManager
      belongs_to :parent_manager,
        :foreign_key => :parent_ems_id,
        :class_name  => "ManageIQ::Providers::BaseManager",
        :autosave    => true
      has_many :network_ports, :foreign_key => :ems_id
    end
  end
end
