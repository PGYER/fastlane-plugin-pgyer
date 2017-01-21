module Fastlane
  module Helper
    class PgyerHelper
      # class methods that you define here become available in your action
      # as `Helper::PgyerHelper.your_method`
      #
      def self.show_message
        UI.message("Hello from the pgyer plugin helper!")
      end
    end
  end
end
