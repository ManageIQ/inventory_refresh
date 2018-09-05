ActiveRecord::Schema.define(version: 20180830121026) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

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
end
