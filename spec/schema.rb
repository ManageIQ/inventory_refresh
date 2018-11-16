ActiveRecord::Schema.define(version: 20180906121026) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "authentications", id: :bigserial, force: :cascade do |t|
    t.string   "name"
    t.string   "authtype"
    t.string   "userid"
    t.string   "password"
    t.bigint   "resource_id"
    t.string   "resource_type"
    t.datetime "created_on"
    t.datetime "updated_on"
    t.datetime "last_valid_on"
    t.datetime "last_invalid_on"
    t.datetime "credentials_changed_on"
    t.string   "status"
    t.string   "status_details"
    t.string   "type"
    t.text     "auth_key"
    t.string   "fingerprint"
    t.string   "service_account"
    t.boolean  "challenge"
    t.boolean  "login"
    t.text     "public_key"
    t.text     "htpassd_users",                             default: [], array: true
    t.text     "ldap_id",                                   default: [], array: true
    t.text     "ldap_email",                                default: [], array: true
    t.text     "ldap_name",                                 default: [], array: true
    t.text     "ldap_preferred_user_name",                  default: [], array: true
    t.string   "ldap_bind_dn"
    t.boolean  "ldap_insecure"
    t.string   "ldap_url"
    t.string   "request_header_challenge_url"
    t.string   "request_header_login_url"
    t.text     "request_header_headers",                    default: [], array: true
    t.text     "request_header_preferred_username_headers", default: [], array: true
    t.text     "request_header_name_headers",               default: [], array: true
    t.text     "request_header_email_headers",              default: [], array: true
    t.string   "open_id_sub_claim"
    t.string   "open_id_user_info"
    t.string   "open_id_authorization_endpoint"
    t.string   "open_id_token_endpoint"
    t.text     "open_id_extra_scopes",                      default: [], array: true
    t.text     "open_id_extra_authorize_parameters"
    t.text     "certificate_authority"
    t.string   "google_hosted_domain"
    t.text     "github_organizations",                      default: [], array: true
    t.string   "rhsm_sku"
    t.string   "rhsm_pool_id"
    t.string   "rhsm_server"
    t.string   "manager_ref"
    t.text     "options"
    t.index ["resource_id", "resource_type"], name: "index_authentications_on_resource_id_and_resource_type", using: :btree
    t.index ["type"], name: "index_authentications_on_type", using: :btree
  end

  create_table "availability_zones", id: :bigserial, force: :cascade do |t|
    t.bigint "ems_id"
    t.string "name"
    t.string "ems_ref"
    t.string "type"
    t.index ["ems_id"], name: "index_availability_zones_on_ems_id", using: :btree
    t.index ["type"], name: "index_availability_zones_on_type", using: :btree
  end

  create_table "cloud_tenants", id: :bigserial, force: :cascade do |t|
    t.string   "name"
    t.text     "description"
    t.boolean  "enabled"
    t.string   "ems_ref"
    t.bigint   "ems_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "type"
    t.bigint   "parent_id"
    t.index ["type"], name: "index_cloud_tenants_on_type", using: :btree
  end

  create_table "vms", id: :bigserial, force: :cascade do |t|
    t.string   "vendor"
    t.string   "format"
    t.string   "version"
    t.string   "name"
    t.text     "description"
    t.string   "location"
    t.string   "config_xml"
    t.string   "autostart"
    t.bigint   "host_id"
    t.datetime "last_sync_on"
    t.datetime "created_on"
    t.datetime "updated_on"
    t.bigint   "storage_id"
    t.string   "guid"
    t.bigint   "ems_id"
    t.datetime "last_scan_on"
    t.datetime "last_scan_attempt_on"
    t.string   "uid_ems"
    t.datetime "retires_on"
    t.boolean  "retired"
    t.datetime "boot_time"
    t.string   "tools_status"
    t.string   "standby_action"
    t.string   "power_state"
    t.datetime "state_changed_on"
    t.string   "previous_state"
    t.string   "connection_state"
    t.datetime "last_perf_capture_on"
    t.boolean  "registered"
    t.boolean  "busy"
    t.boolean  "smart"
    t.integer  "memory_reserve"
    t.boolean  "memory_reserve_expand"
    t.integer  "memory_limit"
    t.integer  "memory_shares"
    t.string   "memory_shares_level"
    t.integer  "cpu_reserve"
    t.boolean  "cpu_reserve_expand"
    t.integer  "cpu_limit"
    t.integer  "cpu_shares"
    t.string   "cpu_shares_level"
    t.string   "cpu_affinity"
    t.datetime "ems_created_on"
    t.boolean  "template",                 default: false
    t.bigint   "evm_owner_id"
    t.string   "ems_ref_obj"
    t.bigint   "miq_group_id"
    t.boolean  "linked_clone"
    t.boolean  "fault_tolerance"
    t.string   "type"
    t.string   "ems_ref"
    t.bigint   "ems_cluster_id"
    t.bigint   "retirement_warn"
    t.datetime "retirement_last_warn"
    t.integer  "vnc_port"
    t.bigint   "flavor_id"
    t.bigint   "availability_zone_id"
    t.boolean  "cloud"
    t.string   "retirement_state"
    t.bigint   "cloud_network_id"
    t.bigint   "cloud_subnet_id"
    t.bigint   "cloud_tenant_id"
    t.string   "raw_power_state"
    t.boolean  "publicly_available"
    t.bigint   "orchestration_stack_id"
    t.string   "retirement_requester"
    t.bigint   "tenant_id"
    t.bigint   "resource_group_id"
    t.boolean  "deprecated"
    t.bigint   "storage_profile_id"
    t.boolean  "cpu_hot_add_enabled"
    t.boolean  "cpu_hot_remove_enabled"
    t.boolean  "memory_hot_add_enabled"
    t.integer  "memory_hot_add_limit"
    t.integer  "memory_hot_add_increment"
    t.string   "hostname"
    t.bigint   "source_region_id"
    t.bigint   "subscription_id"
    t.datetime "archived_on"
    t.index ["availability_zone_id"], name: "index_vms_on_availability_zone_id", using: :btree
    t.index ["evm_owner_id"], name: "index_vms_on_evm_owner_id", using: :btree
    t.index ["flavor_id"], name: "index_vms_on_flavor_id", using: :btree
    t.index ["guid"], name: "index_vms_on_guid", unique: true, using: :btree
    t.index ["host_id"], name: "index_vms_on_host_id", using: :btree
    t.index ["location"], name: "index_vms_on_location", using: :btree
    t.index ["miq_group_id"], name: "index_vms_on_miq_group_id", using: :btree
    t.index ["name"], name: "index_vms_on_name", using: :btree
    t.index ["storage_id"], name: "index_vms_on_storage_id", using: :btree
    t.index ["type"], name: "index_vms_on_type", using: :btree
    t.index ["uid_ems"], name: "index_vms_on_vmm_uuid", using: :btree
    t.index ["source_region_id"], name: "index_vms_on_source_region_id", using: :btree
    t.index ["subscription_id"], name: "index_vms_on_subscription_id", using: :btree
    t.index ["archived_on"], name: "index_vms_on_archived_on", using: :btree
    t.index ["ems_id", "ems_ref"], name: "index_vms_on_ems_id_and_ems_ref", unique: true, using: :btree
  end

  create_table "hardwares", id: :bigserial, force: :cascade do |t|
    t.bigint  "vm_or_template_id"
    t.string  "config_version"
    t.string  "virtual_hw_version"
    t.string  "guest_os"
    t.integer "cpu_sockets",          default: 1
    t.string  "bios"
    t.string  "bios_location"
    t.string  "time_sync"
    t.text    "annotation"
    t.integer "memory_mb"
    t.bigint  "host_id"
    t.integer "cpu_speed"
    t.string  "cpu_type"
    t.bigint  "size_on_disk"
    t.string  "manufacturer",         default: ""
    t.string  "model",                default: ""
    t.integer "number_of_nics"
    t.integer "cpu_usage"
    t.integer "memory_usage"
    t.integer "cpu_cores_per_socket"
    t.integer "cpu_total_cores"
    t.boolean "vmotion_enabled"
    t.bigint  "disk_free_space"
    t.bigint  "disk_capacity"
    t.string  "guest_os_full_name"
    t.integer "memory_console"
    t.integer "bitness"
    t.string  "virtualization_type"
    t.string  "root_device_type"
    t.bigint  "computer_system_id"
    t.bigint  "disk_size_minimum"
    t.bigint  "memory_mb_minimum"
    t.boolean "introspected"
    t.string  "provision_state"
    t.string  "serial_number"
    t.bigint  "switch_id"
    t.string  "firmware_type"
    t.bigint  "canister_id"
    t.datetime "archived_on"
    t.index ["computer_system_id"], name: "index_hardwares_on_computer_system_id", using: :btree
    t.index ["host_id"], name: "index_hardwares_on_host_id", using: :btree
    t.index ["vm_or_template_id"], name: "index_hardwares_on_vm_or_template_id", unique: true, using: :btree
  end

  add_foreign_key :hardwares, :vms, on_delete: :cascade, column: 'vm_or_template_id'

  create_table "disks", id: :bigserial, force: :cascade do |t|
    t.string   "device_name"
    t.string   "device_type"
    t.string   "location"
    t.string   "filename"
    t.bigint   "hardware_id"
    t.string   "mode"
    t.string   "controller_type"
    t.bigint   "size"
    t.bigint   "free_space"
    t.bigint   "size_on_disk"
    t.boolean  "present",            default: true
    t.boolean  "start_connected",    default: true
    t.boolean  "auto_detect"
    t.datetime "created_on"
    t.datetime "updated_on"
    t.string   "disk_type"
    t.bigint   "storage_id"
    t.bigint   "backing_id"
    t.string   "backing_type"
    t.bigint   "storage_profile_id"
    t.boolean  "bootable"
    t.datetime "archived_on"
    t.index ["hardware_id", "device_name"], name: "index_disks_on_hardware_id_and_device_name", unique: true, using: :btree
    t.index ["device_type"], name: "index_disks_on_device_type", using: :btree
    t.index ["storage_id"], name: "index_disks_on_storage_id", using: :btree
  end

  add_foreign_key :disks, :hardwares, on_delete: :cascade

  create_table "event_streams", id: :bigserial, force: :cascade do |t|
    t.string   "event_type"
    t.text     "message"
    t.datetime "timestamp"
    t.string   "host_name"
    t.bigint   "host_id"
    t.string   "vm_name"
    t.string   "vm_location"
    t.bigint   "vm_or_template_id"
    t.string   "dest_host_name"
    t.bigint   "dest_host_id"
    t.string   "dest_vm_name"
    t.string   "dest_vm_location"
    t.bigint   "dest_vm_or_template_id"
    t.string   "source"
    t.bigint   "chain_id"
    t.bigint   "ems_id"
    t.boolean  "is_task"
    t.text     "full_data"
    t.datetime "created_on"
    t.string   "username"
    t.bigint   "ems_cluster_id"
    t.string   "ems_cluster_name"
    t.string   "ems_cluster_uid"
    t.bigint   "dest_ems_cluster_id"
    t.string   "dest_ems_cluster_name"
    t.string   "dest_ems_cluster_uid"
    t.bigint   "availability_zone_id"
    t.bigint   "container_node_id"
    t.string   "container_node_name"
    t.bigint   "container_group_id"
    t.string   "container_group_name"
    t.string   "container_namespace"
    t.string   "type"
    t.string   "target_type"
    t.bigint   "target_id"
    t.bigint   "container_id"
    t.string   "container_name"
    t.bigint   "container_replicator_id"
    t.string   "container_replicator_name"
    t.bigint   "middleware_server_id"
    t.string   "middleware_server_name"
    t.bigint   "middleware_deployment_id"
    t.string   "middleware_deployment_name"
    t.bigint   "generating_ems_id"
    t.bigint   "physical_server_id"
    t.string   "ems_ref"
    t.bigint   "middleware_domain_id"
    t.string   "middleware_domain_name"
    t.bigint   "user_id"
    t.bigint   "group_id"
    t.bigint   "tenant_id"
    t.string   "vm_ems_ref"
    t.string   "dest_vm_ems_ref"
    t.bigint   "physical_chassis_id"
    t.bigint   "physical_switch_id"
    t.index ["availability_zone_id", "type"], name: "index_event_streams_on_availability_zone_id_and_type", using: :btree
    t.index ["chain_id", "ems_id"], name: "index_event_streams_on_chain_id_and_ems_id", using: :btree
    t.index ["dest_host_id"], name: "index_event_streams_on_dest_host_id", using: :btree
    t.index ["dest_vm_or_template_id"], name: "index_event_streams_on_dest_vm_or_template_id", using: :btree
    t.index ["ems_cluster_id"], name: "index_event_streams_on_ems_cluster_id", using: :btree
    t.index ["ems_id"], name: "index_event_streams_on_ems_id", using: :btree
    t.index ["event_type"], name: "index_event_streams_on_event_type", using: :btree
    t.index ["generating_ems_id"], name: "index_event_streams_on_generating_ems_id", using: :btree
    t.index ["host_id"], name: "index_event_streams_on_host_id", using: :btree
    t.index ["timestamp"], name: "index_event_streams_on_timestamp", using: :btree
    t.index ["vm_or_template_id"], name: "index_event_streams_on_vm_or_template_id", using: :btree
  end

  create_table "ext_management_systems", id: :bigserial, force: :cascade do |t|
    t.string   "name"
    t.datetime "created_on"
    t.datetime "updated_on"
    t.string   "guid"
    t.bigint   "zone_id"
    t.string   "type"
    t.string   "api_version"
    t.string   "uid_ems"
    t.integer  "host_default_vnc_port_start"
    t.integer  "host_default_vnc_port_end"
    t.string   "provider_region"
    t.text     "last_refresh_error"
    t.datetime "last_refresh_date"
    t.bigint   "provider_id"
    t.string   "realm"
    t.bigint   "tenant_id"
    t.string   "project"
    t.bigint   "parent_ems_id"
    t.string   "subscription"
    t.text     "last_metrics_error"
    t.datetime "last_metrics_update_date"
    t.datetime "last_metrics_success_date"
    t.boolean  "tenant_mapping_enabled"
    t.boolean  "enabled"
    t.text     "options"
    t.index ["guid"], name: "index_ext_management_systems_on_guid", unique: true, using: :btree
    t.index ["parent_ems_id"], name: "index_ext_management_systems_on_parent_ems_id", using: :btree
    t.index ["type"], name: "index_ext_management_systems_on_type", using: :btree
  end

  create_table "flavors", id: :bigserial, force: :cascade do |t|
    t.bigint  "ems_id"
    t.string  "name"
    t.string  "description"
    t.integer "cpus"
    t.integer "cpu_cores"
    t.bigint  "memory"
    t.string  "ems_ref"
    t.string  "type"
    t.boolean "supports_32_bit"
    t.boolean "supports_64_bit"
    t.boolean "enabled"
    t.boolean "supports_hvm"
    t.boolean "supports_paravirtual"
    t.boolean "block_storage_based_only"
    t.boolean "cloud_subnet_required"
    t.bigint  "ephemeral_disk_size"
    t.integer "ephemeral_disk_count"
    t.bigint  "root_disk_size"
    t.bigint  "swap_disk_size"
    t.boolean "publicly_available"
    t.index ["ems_id"], name: "index_flavors_on_ems_id", using: :btree
    t.index ["type"], name: "index_flavors_on_type", using: :btree
  end

  create_table "hosts", id: :bigserial, force: :cascade do |t|
    t.string   "name"
    t.string   "hostname"
    t.string   "ipaddress"
    t.string   "vmm_vendor"
    t.string   "vmm_version"
    t.string   "vmm_product"
    t.string   "vmm_buildnumber"
    t.datetime "created_on"
    t.datetime "updated_on"
    t.string   "guid"
    t.bigint   "ems_id"
    t.string   "user_assigned_os"
    t.string   "power_state",             default: ""
    t.integer  "smart"
    t.string   "settings"
    t.datetime "last_perf_capture_on"
    t.string   "uid_ems"
    t.string   "connection_state"
    t.string   "ssh_permit_root_login"
    t.string   "ems_ref_obj"
    t.boolean  "admin_disabled"
    t.string   "service_tag"
    t.string   "asset_tag"
    t.string   "ipmi_address"
    t.string   "mac_address"
    t.string   "type"
    t.boolean  "failover"
    t.string   "ems_ref"
    t.boolean  "hyperthreading"
    t.bigint   "ems_cluster_id"
    t.integer  "next_available_vnc_port"
    t.string   "hypervisor_hostname"
    t.bigint   "availability_zone_id"
    t.boolean  "maintenance"
    t.string   "maintenance_reason"
    t.bigint   "physical_server_id"
    t.index ["availability_zone_id"], name: "index_hosts_on_availability_zone_id", using: :btree
    t.index ["ems_id"], name: "index_hosts_on_ems_id", using: :btree
    t.index ["guid"], name: "index_hosts_on_guid", unique: true, using: :btree
    t.index ["hostname"], name: "index_hosts_on_hostname", using: :btree
    t.index ["ipaddress"], name: "index_hosts_on_ipaddress", using: :btree
    t.index ["type"], name: "index_hosts_on_type", using: :btree
  end

  create_table "key_pairs_vms", id: :bigserial, force: :cascade do |t|
    t.bigint "authentication_id"
    t.bigint "vm_id"
  end

  create_table "networks", id: :bigserial, force: :cascade do |t|
    t.bigint   "hardware_id"
    t.bigint   "device_id"
    t.string   "description"
    t.string   "guid"
    t.boolean  "dhcp_enabled"
    t.string   "ipaddress"
    t.string   "subnet_mask"
    t.datetime "lease_obtained"
    t.datetime "lease_expires"
    t.string   "default_gateway"
    t.string   "dhcp_server"
    t.string   "dns_server"
    t.string   "hostname"
    t.string   "domain"
    t.string   "ipv6address"
    t.datetime "archived_on"
    t.index ["hardware_id", "description"], name: "index_networks_on_hardware_id_and_description", unique: true, using: :btree
    t.index ["device_id"], name: "index_networks_on_device_id", using: :btree
  end

  add_foreign_key :networks, :hardwares, on_delete: :cascade

  create_table "network_ports", id: :bigserial, force: :cascade do |t|
    t.string  "type"
    t.string  "name"
    t.string  "ems_ref"
    t.bigint  "ems_id"
    t.string  "mac_address"
    t.string  "status"
    t.boolean "admin_state_up"
    t.string  "device_owner"
    t.string  "device_ref"
    t.bigint  "device_id"
    t.string  "device_type"
    t.bigint  "cloud_tenant_id"
    t.string  "binding_host_id"
    t.string  "binding_virtual_interface_type"
    t.text    "extra_attributes"
    t.string  "source"
    t.datetime "archived_on"
    t.index ["cloud_tenant_id"], name: "index_network_ports_on_cloud_tenant_id", using: :btree
    t.index ["device_id", "device_type"], name: "index_network_ports_on_device_id_and_device_type", using: :btree
    t.index ["type"], name: "index_network_ports_on_type", using: :btree
    t.index ["archived_on"], name: "index_network_ports_on_archived_on", using: :btree
    t.index ["ems_id", "ems_ref"], name: "index_network_ports_on_ems_id_and_ems_ref", unique: true, using: :btree
  end

  create_table "orchestration_stack_resources", id: :bigserial, force: :cascade do |t|
    t.string   "name"
    t.text     "description"
    t.text     "logical_resource"
    t.text     "physical_resource"
    t.string   "resource_category"
    t.string   "resource_status"
    t.text     "resource_status_reason"
    t.datetime "last_updated"
    t.bigint   "stack_id"
    t.text     "ems_ref"
    t.datetime "start_time"
    t.datetime "finish_time"
    t.index ["stack_id"], name: "index_orchestration_stack_resources_on_stack_id", using: :btree
  end

  create_table "orchestration_stacks", id: :bigserial, force: :cascade do |t|
    t.string   "name"
    t.string   "type"
    t.text     "description"
    t.string   "status"
    t.text     "ems_ref"
    t.string   "ancestry"
    t.bigint   "ems_id"
    t.bigint   "orchestration_template_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.boolean  "retired"
    t.datetime "retires_on"
    t.bigint   "retirement_warn"
    t.datetime "retirement_last_warn"
    t.string   "retirement_state"
    t.string   "retirement_requester"
    t.text     "status_reason"
    t.bigint   "cloud_tenant_id"
    t.string   "resource_group"
    t.datetime "start_time"
    t.datetime "finish_time"
    t.bigint   "configuration_script_base_id"
    t.integer  "verbosity"
    t.text     "hosts",                        array: true
    t.index "ancestry varchar_pattern_ops", name: "index_orchestration_stacks_on_ancestry_vpo", using: :btree
    t.index ["ancestry"], name: "index_orchestration_stacks_on_ancestry", using: :btree
    t.index ["orchestration_template_id"], name: "index_orchestration_stacks_on_orchestration_template_id", using: :btree
    t.index ["type"], name: "index_orchestration_stacks_on_type", using: :btree
  end

  create_table "physical_servers", id: :bigserial, force: :cascade do |t|
    t.bigint   "ems_id"
    t.string   "name"
    t.string   "type"
    t.string   "uid_ems"
    t.string   "ems_ref"
    t.datetime "created_at",             null: false
    t.datetime "updated_at",             null: false
    t.string   "health_state"
    t.string   "power_state"
    t.string   "hostname"
    t.string   "product_name"
    t.string   "manufacturer"
    t.string   "machine_type"
    t.string   "model"
    t.string   "serial_number"
    t.string   "field_replaceable_unit"
    t.string   "raw_power_state"
    t.string   "vendor"
    t.string   "location_led_state"
    t.bigint   "physical_rack_id"
    t.string   "ems_compliance_name"
    t.string   "ems_compliance_status"
    t.bigint   "physical_chassis_id"
  end

  create_table "services", id: :bigserial, force: :cascade do |t|
    t.string   "name"
    t.string   "description"
    t.string   "guid"
    t.string   "type"
    t.bigint   "service_template_id"
    t.text     "options"
    t.boolean  "display"
    t.datetime "created_at",           null: false
    t.datetime "updated_at",           null: false
    t.bigint   "evm_owner_id"
    t.bigint   "miq_group_id"
    t.boolean  "retired"
    t.datetime "retires_on"
    t.bigint   "retirement_warn"
    t.datetime "retirement_last_warn"
    t.string   "retirement_state"
    t.string   "retirement_requester"
    t.bigint   "tenant_id"
    t.string   "ancestry"
    t.string   "initiator",                         comment: "Entity that initiated the service creation"
    t.index "ancestry varchar_pattern_ops", name: "index_services_on_ancestry_vpo", using: :btree
    t.index ["ancestry"], name: "index_services_on_ancestry", using: :btree
    t.index ["type"], name: "index_services_on_type", using: :btree
  end

  create_table "container_groups", id: :bigserial, force: :cascade do |t|
    t.string   "ems_ref"
    t.string   "name"
    t.datetime "ems_created_on"
    t.string   "resource_version_string"
    t.string   "restart_policy"
    t.string   "dns_policy"
    t.bigint   "ems_id", null: false
    t.bigint   "container_node_id"
    t.datetime "last_perf_capture_on"
    t.bigint   "container_replicator_id"
    t.string   "ipaddress"
    t.string   "type"
    t.bigint   "container_project_id"
    t.string   "phase"
    t.string   "message"
    t.string   "reason"
    t.bigint   "container_build_pod_id"
    t.datetime "created_on"
    t.datetime "archived_on"
    t.bigint   "old_ems_id"
    t.bigint   "old_container_project_id"
    t.datetime "updated_on"
    t.datetime "resource_timestamp"
    t.jsonb    "resource_timestamps", default: {}
    t.datetime "resource_timestamps_max"
    t.integer  "resource_counter"
    t.jsonb    "resource_counters", default: {}
    t.integer  "resource_counters_max"
    t.string   "resource_version"
    t.index ["archived_on"], name: "index_container_groups_on_archived_on", using: :btree
    t.index ["ems_id", "ems_ref"], name: "index_container_groups_on_ems_id_and_ems_ref", unique: true, using: :btree
    t.index ["ems_id"], name: "index_container_groups_on_ems_id", using: :btree
    t.index ["type"], name: "index_container_groups_on_type", using: :btree
  end

  create_table "containers", id: :bigserial, force: :cascade do |t|
    t.string   "ems_ref"
    t.integer  "restart_count"
    t.string   "state"
    t.string   "name"
    t.string   "backing_ref"
    t.datetime "last_perf_capture_on"
    t.string   "type"
    t.bigint   "container_image_id"
    t.string   "reason"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.integer  "exit_code"
    t.integer  "signal"
    t.string   "message"
    t.string   "last_state"
    t.string   "last_reason"
    t.datetime "last_started_at"
    t.datetime "last_finished_at"
    t.integer  "last_exit_code"
    t.integer  "last_signal"
    t.string   "last_message"
    t.datetime "archived_on"
    t.bigint   "ems_id", null: false
    t.bigint   "old_ems_id"
    t.float    "request_cpu_cores"
    t.bigint   "request_memory_bytes"
    t.float    "limit_cpu_cores"
    t.bigint   "limit_memory_bytes"
    t.string   "image"
    t.string   "image_pull_policy"
    t.string   "memory"
    t.float    "cpu_cores"
    t.bigint   "container_group_id"
    t.boolean  "privileged"
    t.bigint   "run_as_user"
    t.boolean  "run_as_non_root"
    t.string   "capabilities_add"
    t.string   "capabilities_drop"
    t.text     "command"
    t.datetime "resource_timestamp"
    t.jsonb    "resource_timestamps", default: {}
    t.datetime "resource_timestamps_max"
    t.index ["archived_on"], name: "index_containers_on_archived_on", using: :btree
    t.index ["ems_id", "ems_ref"], name: "index_containers_on_ems_id_and_ems_ref", unique: true, using: :btree
    t.index ["type"], name: "index_containers_on_type", using: :btree
  end

  create_table "nested_containers", id: :bigserial, force: :cascade do |t|
    t.string   "ems_ref"
    t.integer  "restart_count"
    t.string   "state"
    t.string   "name"
    t.string   "backing_ref"
    t.datetime "last_perf_capture_on"
    t.string   "type"
    t.bigint   "container_image_id"
    t.string   "reason"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.integer  "exit_code"
    t.integer  "signal"
    t.string   "message"
    t.string   "last_state"
    t.string   "last_reason"
    t.datetime "last_started_at"
    t.datetime "last_finished_at"
    t.integer  "last_exit_code"
    t.integer  "last_signal"
    t.string   "last_message"
    t.datetime "archived_on"
    t.bigint   "old_ems_id"
    t.float    "request_cpu_cores"
    t.bigint   "request_memory_bytes"
    t.float    "limit_cpu_cores"
    t.bigint   "limit_memory_bytes"
    t.string   "image"
    t.string   "image_pull_policy"
    t.string   "memory"
    t.float    "cpu_cores"
    t.bigint   "container_group_id", :null => false
    t.boolean  "privileged"
    t.bigint   "run_as_user"
    t.boolean  "run_as_non_root"
    t.string   "capabilities_add"
    t.string   "capabilities_drop"
    t.text     "command"
    t.datetime "resource_timestamp"
    t.jsonb    "resource_timestamps", default: {}
    t.datetime "resource_timestamps_max"
    t.index ["archived_on"], name: "index_nested_containers_on_archived_on", using: :btree
    t.index ["container_group_id", "name"], name: "index_nested_containers_uniq", unique: true, using: :btree
    t.index ["type"], name: "index_nested_containers_on_type", using: :btree
  end

  create_table "container_image_registries", id: :bigserial, force: :cascade do |t|
    t.string "name"
    t.string "host"
    t.string "port"
    t.bigint "ems_id"
    t.index ["ems_id", "host", "port"], name: "index_container_image_registries_on_ems_id_and_host_and_port", unique: true, using: :btree
  end

  create_table "container_images", id: :bigserial, force: :cascade do |t|
    t.string   "tag"
    t.string   "name"
    t.string   "image_ref"
    t.bigint   "container_image_registry_id"
    t.bigint   "ems_id", null: false
    t.datetime "last_sync_on"
    t.datetime "last_scan_attempt_on"
    t.string   "digest"
    t.datetime "registered_on"
    t.string   "architecture"
    t.string   "author"
    t.string   "command",                     default: [], array: true
    t.string   "entrypoint",                  default: [], array: true
    t.string   "docker_version"
    t.text     "exposed_ports"
    t.text     "environment_variables"
    t.bigint   "size"
    t.datetime "created_on"
    t.bigint   "old_ems_id"
    t.datetime "archived_on"
    t.string   "type"
    t.jsonb    "timestamps",                  default: {}
    t.index ["archived_on"], name: "index_container_images_on_archived_on", using: :btree
    t.index ["ems_id", "image_ref"], name: "index_container_images_unique_multi_column", unique: true, using: :btree
    t.index ["ems_id"], name: "index_container_images_on_ems_id", using: :btree
  end

  create_table "container_projects", id: :bigserial, force: :cascade do |t|
    t.string   "ems_ref"
    t.string   "name"
    t.datetime "ems_created_on"
    t.string   "resource_version_string"
    t.string   "display_name"
    t.bigint   "ems_id"
    t.datetime "created_on"
    t.datetime "archived_on"
    t.bigint   "old_ems_id"
    t.index ["archived_on"], name: "index_container_projects_on_archived_on", using: :btree
    t.index ["ems_id", "ems_ref"], name: "index_container_projects_on_ems_id_and_ems_ref", unique: true, using: :btree
    t.index ["ems_id"], name: "index_container_projects_on_ems_id", using: :btree
  end

  create_table "container_replicators", id: :bigserial, force: :cascade do |t|
    t.string   "ems_ref"
    t.string   "name"
    t.datetime "ems_created_on"
    t.bigint   "ems_id"
    t.string   "resource_version_string"
    t.integer  "replicas"
    t.integer  "current_replicas"
    t.bigint   "container_project_id"
    t.datetime "created_on"
    t.index ["ems_id", "ems_ref"], name: "index_container_replicators_on_ems_id_and_ems_ref", unique: true, using: :btree
  end

  create_table "container_nodes", id: :bigserial, force: :cascade do |t|
    t.string   "ems_ref"
    t.string   "name"
    t.datetime "ems_created_on"
    t.string   "resource_version_string"
    t.bigint   "ems_id"
    t.string   "lives_on_type"
    t.bigint   "lives_on_id"
    t.datetime "last_perf_capture_on"
    t.string   "identity_infra"
    t.string   "identity_machine"
    t.string   "identity_system"
    t.string   "type"
    t.string   "kubernetes_kubelet_version"
    t.string   "kubernetes_proxy_version"
    t.string   "container_runtime_version"
    t.integer  "max_container_groups"
    t.datetime "created_on"
    t.bigint   "old_ems_id"
    t.datetime "archived_on"
    t.index ["archived_on"], name: "index_container_nodes_on_archived_on", using: :btree
    t.index ["ems_id", "ems_ref"], name: "index_container_nodes_on_ems_id_and_ems_ref", unique: true, using: :btree
    t.index ["ems_id"], name: "index_container_nodes_on_ems_id", using: :btree
    t.index ["type"], name: "index_container_nodes_on_type", using: :btree
  end

  create_table "container_build_pods", id: :bigserial, force: :cascade do |t|
    t.string   "ems_ref"
    t.string   "name"
    t.datetime "ems_created_on"
    t.string   "resource_version_string"
    t.string   "namespace"
    t.string   "message"
    t.string   "phase"
    t.string   "reason"
    t.string   "output_docker_image_reference"
    t.string   "completion_timestamp"
    t.string   "start_timestamp"
    t.bigint   "duration"
    t.bigint   "container_build_id"
    t.bigint   "ems_id"
    t.datetime "created_on"
    t.index ["ems_id", "ems_ref"], name: "index_container_build_pods_on_ems_id_and_ems_ref", unique: true, using: :btree
    t.index ["ems_id"], name: "index_container_build_pods_on_ems_id", using: :btree
  end

  create_table "source_regions", force: :cascade do |t|
    t.bigint "ems_id", null: false
    t.string "ems_ref"
    t.string "name"
    t.string "endpoint"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "archived_on"
    t.index ["archived_on"], name: "index_source_regions_on_archived_on"
    t.index ["ems_id", "ems_ref"], name: "index_source_regions_on_ems_id_and_ems_ref", unique: true
    t.index ["ems_id"], name: "index_source_regions_on_ems_id"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.bigint "ems_id", null: false
    t.string "ems_ref"
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "archived_on"
    t.index ["archived_on"], name: "index_subscriptions_on_archived_on"
    t.index ["ems_id", "ems_ref"], name: "index_subscriptions_on_ems_id_and_ems_ref", unique: true
    t.index ["ems_id"], name: "index_subscriptions_on_ems_id"
  end
end
