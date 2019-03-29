module InventoryRefresh
  module Exception
    class SweeperError < StandardError; end
    class SweeperNonExistentScopeKeyFoundError < StandardError; end
    class SweeperNonUniformScopeKeyFoundError < StandardError; end
  end
end
