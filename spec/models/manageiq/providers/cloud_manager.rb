require "manageiq/providers/base_manager"

module ManageIQ
  module Providers
    class CloudManager < ManageIQ::Providers::BaseManager
      has_many :availability_zones, :foreign_key => :ems_id
      has_many :cloud_tenants, :foreign_key => :ems_id
      has_many :flavors, :foreign_key => :ems_id
      has_many :key_pairs, :class_name => "AuthKeyPair", :as => :resource
      has_many :orchestration_stacks, :foreign_key => :ems_id
      has_many :orchestration_stacks_resources, :through => :orchestration_stacks, :source => :resources
      has_one :network_manager,
              :foreign_key => :parent_ems_id,
              :class_name  => "NetworkManager"

      has_one :network_manager,
              :foreign_key => :parent_ems_id,
              :class_name  => "ManageIQ::Providers::NetworkManager",
              :autosave    => true

      delegate :network_ports,
               :to        => :network_manager,
               :allow_nil => true
    end
  end
end
