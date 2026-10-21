require "fastlane_core/ui/ui"

module Fastlane
  UI = FastlaneCore::UI unless Fastlane.const_defined?("UI")

  module Helper
    class PgyerHelper
      WEB_SERVER = "https://www.pgyer.com"

      BUILD_TYPES = {
        ".apk" => "android",
        ".ipa" => "ios",
        ".hap" => "harmony",
      }

      INSTALL_TYPES = %w(1 2 3)

      HINTS = {
        1001 => "Check that the API key is correct. You can find it at https://www.pgyer.com/account/api",
        1002 => "Check that the API key is correct. You can find it at https://www.pgyer.com/account/api",
        1003 => "Sub-accounts cannot use the API. Use the API key of the main account.",
        1019 => "Complete real-name verification before uploading: https://www.pgyer.com/account/certification",
        1020 => "Uploading is disabled for this account. Contact PGYER customer service.",
        1022 => "Your PGYER storage is full or the file is too large. Free up space or upgrade your plan.",
      }

      def self.blank?(value)
        value.nil? || value.to_s.strip.empty?
      end

      def self.expand_path(path)
        File.expand_path(path.to_s.strip)
      rescue ArgumentError
        # "~unknown_user/..." cannot be expanded; report the path as it was given
        path.to_s
      end

      # android, ios or harmony, from the file extension
      def self.build_type(path)
        type = BUILD_TYPES[File.extname(path.to_s).downcase]
        if type.nil?
          UI.user_error!("Can't upload '#{File.basename(path.to_s)}': PGYER accepts .apk, .ipa and .hap files")
        end
        type
      end

      # "1" public, "2" password, "3" invitation only, or nil to keep the setting of the previous version
      def self.install_type(value)
        return nil if blank?(value)

        type = value.to_s.strip
        unless INSTALL_TYPES.include?(type)
          UI.user_error!("Invalid install_type '#{value}'. Use 1 (public), 2 (password) or 3 (invitation only)")
        end
        type
      end

      # "1" overseas, "2" mainland China, or nil to let PGYER choose by the IP address.
      # Also accepts the values earlier versions documented (1, 2, and 0 for "not set").
      def self.oversea(value)
        case value.to_s.strip.downcase
        when "", "0"
          nil
        when "true", "1"
          "1"
        when "false", "2"
          "2"
        else
          UI.user_error!("Invalid oversea value '#{value}'. Use true (overseas), false (mainland China), or leave it unset to choose by IP address")
        end
      end

      # The form fields for getCOSToken. Only the options the user set are sent, so PGYER keeps
      # the settings of the previous version for everything else.
      def self.token_form(params, build_type)
        form = {
          "_api_key" => params[:api_key].to_s.strip,
          "buildType" => build_type,
        }

        password = params[:password]
        install_type = install_type(params[:install_type])
        if install_type.nil? && !blank?(password)
          install_type = "2"
        end
        form["buildInstallType"] = install_type unless install_type.nil?
        form["buildPassword"] = password.to_s unless blank?(password)

        form["buildDescription"] = params[:description].to_s unless blank?(params[:description])
        form["buildUpdateDescription"] = params[:update_description].to_s unless blank?(params[:update_description])
        form.merge!(install_date_fields(params))
        form["buildChannelShortcut"] = params[:channel].to_s.strip unless blank?(params[:channel])

        oversea = oversea(params[:oversea])
        form["oversea"] = oversea unless oversea.nil?
        form
      end

      def self.install_date_fields(params)
        install_date = params[:install_date].to_s.strip
        start_date = params[:install_start_date]
        end_date = params[:install_end_date]
        dates_given = !blank?(start_date) || !blank?(end_date)

        if install_date == "2"
          UI.important("install_date is 2 (no time limit), so install_start_date and install_end_date are ignored") if dates_given
          return { "buildInstallDate" => "2" }
        end

        unless install_date.empty? || install_date == "1"
          # Any other value keeps the setting of the previous version, as in earlier versions of this plugin
          UI.important("install_date is '#{install_date}', so install_start_date and install_end_date are ignored") if dates_given
          return {}
        end

        if blank?(start_date) && blank?(end_date)
          UI.user_error!("install_date 1 needs install_start_date and install_end_date") if install_date == "1"
          return {}
        end

        if blank?(start_date) || blank?(end_date)
          UI.user_error!("Set both install_start_date and install_end_date, or neither")
        end

        {
          "buildInstallDate" => "1",
          "buildInstallStartDate" => start_date.to_s.strip,
          "buildInstallEndDate" => end_date.to_s.strip,
        }
      end

      # The name users see when they download the build. COS stores it as an HTTP header, so only
      # printable ASCII names can be sent; nil means PGYER uses its default name.
      def self.download_file_name(configured, build_file)
        name = blank?(configured) ? File.basename(build_file) : configured.to_s.strip
        return name if printable_ascii?(name)

        unless blank?(configured)
          UI.important("The download file name '#{name}' is not plain ASCII, so PGYER will use its default name")
        end
        nil
      end

      def self.printable_ascii?(text)
        text.each_char.all? { |c| c.ord >= 0x20 && c.ord < 0x7f }
      end

      def self.hint(code)
        HINTS[code.to_i]
      end

      # Adds the download page and QR code URLs to the build information returned by buildInfo
      def self.add_links(info)
        result = info.dup
        build_key = result["buildKey"].to_s
        shortcut = result["buildShortcutUrl"].to_s
        download_url = "#{WEB_SERVER}/#{shortcut.empty? ? build_key : shortcut}"

        result["appPgyerURL"] = download_url
        result["appBuildURL"] = "#{WEB_SERVER}/#{build_key}"
        result["appQRCodeURL"] = result["buildQRCodeURL"].to_s
        # Kept for compatibility with earlier versions of this plugin
        result["fastlaneAddedWholeVisitUrl"] = download_url
        result
      end
    end
  end
end
