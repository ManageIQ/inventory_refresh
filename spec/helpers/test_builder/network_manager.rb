require_relative "../test_builder"
class TestBuilder::NetworkManager < TestBuilder
  def network_ports
    add_properties(
      :use_ar_object  => true,
    )

    add_common_default_values
  end

  protected

  def add_common_default_values
    add_default_values(:ems_id => default_ems_id)
  end

  def default_ems_id
    ->(persister) { persister.manager.try(:network_manager).try(:id) || persister.manager.id }
  end
end
