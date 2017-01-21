describe Fastlane::Actions::PgyerAction do
  describe '#run' do
    it 'prints a message' do
      expect(Fastlane::UI).to receive(:message).with("The pgyer plugin is working!")

      Fastlane::Actions::PgyerAction.run(nil)
    end
  end
end
