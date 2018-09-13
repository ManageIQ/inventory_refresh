describe InventoryRefresh::Logging do
  let(:log_output) { StringIO.new }

  before do
    InventoryRefresh.logger = Logger.new(log_output)
  end

  after do
    InventoryRefresh.logger = nil
  end

  context "InventoryRefresh.logger" do
    it "log to info" do
      InventoryRefresh.logger.info("Hello, world!")

      log_output.rewind
      expect(log_output.read).to end_with("Hello, world!\n")
    end
  end

  context "#logger" do
    let(:mock_instance) do
      Class.new do
        include InventoryRefresh::Logging
      end.new
    end

    it "log to info" do
      mock_instance.logger.info("Hello, world!")

      log_output.rewind
      expect(log_output.read).to end_with("Hello, world!\n")
    end
  end
end
