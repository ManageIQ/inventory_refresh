module InventoryRefresh
  module Exception
    class SweeperError < StandardError; end
    class SweeperNonExistentScopeKeyFoundError < SweeperError; end
    class SweeperNonUniformScopeKeyFoundError < SweeperError; end
    class SweeperScopeBadFormat < SweeperError; end
  end
end
