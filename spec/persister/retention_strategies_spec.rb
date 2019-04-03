require_relative '../helpers/spec_mocked_data'
require_relative '../helpers/spec_parsed_data'
require_relative 'targeted_refresh_spec_helper'

describe InventoryRefresh::Persister do
  include SpecMockedData
  include SpecParsedData
  include TargetedRefreshSpecHelper

  ######################################################################################################################
  # Spec scenarios for various retentions_strategies, causing non existent records to be deleted or archived
  ######################################################################################################################
  #
  before do
    @ems = FactoryBot.create(:ems_cloud,
                             :network_manager => FactoryBot.create(:ems_network))
  end

  it "checks valid retentions strategies" do
    expect do
      create_persister(:retention_strategy => "made_up_name")
    end.to(
      raise_error("Unknown InventoryCollection retention strategy: :made_up_name, allowed strategies are :destroy and :archive")
    )
  end
end
