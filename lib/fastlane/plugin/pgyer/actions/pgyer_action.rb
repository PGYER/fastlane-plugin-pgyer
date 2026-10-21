require "fastlane/action"
require "json"
require_relative "../helper/pgyer_helper"
require_relative "../helper/pgyer_client"

module Fastlane
  module Actions
    module SharedValues
      PGYER_OUTPUT = :PGYER_OUTPUT
      PGYER_DOWNLOAD_URL = :PGYER_DOWNLOAD_URL
      PGYER_QRCODE_URL = :PGYER_QRCODE_URL
    end

    class PgyerAction < Action
      BUILD_FILE_OPTIONS = [:ipa, :apk, :hap]

      def self.run(params)
        build_file = select_build_file(params)
        build_type = Helper::PgyerHelper.build_type(build_file)
        UI.message("Build file: #{build_file} (#{build_type})")

        form = Helper::PgyerHelper.token_form(params, build_type)
        configured_name = params[:user_download_file_name]
        configured_name = ENV.fetch("USER_DOWNLOAD_FILE_NAME", nil) if Helper::PgyerHelper.blank?(configured_name)
        file_name = Helper::PgyerHelper.download_file_name(configured_name, build_file)

        client = Helper::PgyerClient.new(doh: params[:doh] == true)
        info = client.upload(build_file, form, file_name: file_name, processing_timeout: params[:processing_timeout])
        result = Helper::PgyerHelper.add_links(info)

        Actions.lane_context[SharedValues::PGYER_OUTPUT] = result
        Actions.lane_context[SharedValues::PGYER_DOWNLOAD_URL] = result["appPgyerURL"]
        Actions.lane_context[SharedValues::PGYER_QRCODE_URL] = result["appQRCodeURL"]

        UI.success("Published #{result['buildName']} #{result['buildVersion']} (build #{result['buildVersionNo']})")
        UI.success("Download page: #{result['appPgyerURL']}")
        UI.success("QR code: #{result['appQRCodeURL']}")

        if params[:save_uploaded_info_json]
          File.write("pgyer-fastlane-uploaded-app-info.json", result.to_json)
        end
        result
      end

      # An ipa, apk or hap option the user set wins. Without one, the output of gym, gradle or hvigor
      # in this lane is used, in the same ipa, apk, hap order as earlier versions.
      def self.select_build_file(params)
        given = BUILD_FILE_OPTIONS.reject { |key| Helper::PgyerHelper.blank?(params[key]) }
        if given.length > 1
          UI.user_error!("Set only one of the ipa, apk and hap options (found #{given.join(', ')})")
        end

        if given.length == 1
          path = params[given.first]
        else
          path = [
            Actions.lane_context[SharedValues::IPA_OUTPUT_PATH],
            Actions.lane_context[SharedValues::GRADLE_APK_OUTPUT_PATH],
            Actions.lane_context[:HVIGOR_HAP_OUTPUT_PATH],
          ].find { |value| !Helper::PgyerHelper.blank?(value) }
          if path.nil?
            UI.user_error!("You have to provide a build file: set the ipa, apk or hap option, or build one with gym or gradle earlier in the lane")
          end
        end

        path = Helper::PgyerHelper.expand_path(path)
        UI.user_error!("Couldn't find build file at path '#{path}'") unless File.file?(path)
        path
      end

      def self.description
        "distribute app to pgyer beta testing service"
      end

      def self.authors
        ["rexshi"]
      end

      def self.output
        [
          ["PGYER_OUTPUT", "The build information returned by PGYER (a Hash, same as the return value)"],
          ["PGYER_DOWNLOAD_URL", "The download page of the app, such as https://www.pgyer.com/abcd"],
          ["PGYER_QRCODE_URL", "The URL of the QR code image of the download page"],
        ]
      end

      def self.return_type
        :hash
      end

      def self.return_value
        "A Hash with the build information from PGYER's buildInfo API (buildKey, buildName, buildVersion, buildShortcutUrl, buildQRCodeURL, ...) plus appPgyerURL (download page), appBuildURL (page of this build), appQRCodeURL and fastlaneAddedWholeVisitUrl (same as appPgyerURL)"
      end

      def self.details
        "Uploads an .ipa, .apk or .hap file to PGYER (https://www.pgyer.com) and waits until PGYER has published it"
      end

      def self.example_code
        [
          'pgyer(api_key: ENV["PGYER_API_KEY"], update_description: "Fixed the login crash")',
          'pgyer(apk: "app/build/outputs/apk/release/app-release.apk", password: "123456")',
          'pgyer(hap: "entry/build/default/outputs/default/entry-default-signed.hap", install_type: 3)',
        ]
      end

      def self.category
        :beta
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :api_key,
                                       env_name: "PGYER_API_KEY",
                                       description: "API key of your PGYER account, see https://www.pgyer.com/account/api",
                                       optional: false,
                                       sensitive: true,
                                       type: String,
                                       verify_block: proc do |value|
                                         UI.user_error!("No PGYER API key given, pass it with api_key or PGYER_API_KEY") if value.to_s.strip.empty?
                                       end),
          FastlaneCore::ConfigItem.new(key: :apk,
                                       env_name: "PGYER_APK",
                                       description: "Path to your APK file. Defaults to the output of the gradle action",
                                       optional: true,
                                       verify_block: proc do |value|
                                         UI.user_error!("Couldn't find apk file at path '#{value}'") unless File.exist?(Helper::PgyerHelper.expand_path(value))
                                       end,
                                       conflicting_options: [:ipa, :hap],
                                       conflict_block: proc do |value|
                                         UI.user_error!("You can't use 'apk' and '#{value.key}' options in one run")
                                       end),
          FastlaneCore::ConfigItem.new(key: :ipa,
                                       env_name: "PGYER_IPA",
                                       description: "Path to your IPA file. Defaults to the output of the gym or xcodebuild action",
                                       optional: true,
                                       verify_block: proc do |value|
                                         UI.user_error!("Couldn't find ipa file at path '#{value}'") unless File.exist?(Helper::PgyerHelper.expand_path(value))
                                       end,
                                       conflicting_options: [:apk, :hap],
                                       conflict_block: proc do |value|
                                         UI.user_error!("You can't use 'ipa' and '#{value.key}' options in one run")
                                       end),
          FastlaneCore::ConfigItem.new(key: :hap,
                                       env_name: "PGYER_HAP",
                                       description: "Path to your HarmonyOS HAP file. Defaults to lane_context[:HVIGOR_HAP_OUTPUT_PATH]",
                                       optional: true,
                                       verify_block: proc do |value|
                                         UI.user_error!("Couldn't find hap file at path '#{value}'") unless File.exist?(Helper::PgyerHelper.expand_path(value))
                                       end,
                                       conflicting_options: [:apk, :ipa],
                                       conflict_block: proc do |value|
                                         UI.user_error!("You can't use 'hap' and '#{value.key}' options in one run")
                                       end),
          FastlaneCore::ConfigItem.new(key: :password,
                                       env_name: "PGYER_PASSWORD",
                                       description: "Set password to protect app. Without install_type, this also sets install_type to 2",
                                       optional: true,
                                       sensitive: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :user_download_file_name,
                                       env_name: "PGYER_USER_DOWNLOAD_FILE_NAME",
                                       description: "The file name users get when they download the app, such as app.apk (plain ASCII only). Defaults to the name of the uploaded file. USER_DOWNLOAD_FILE_NAME is also read",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :description,
                                       env_name: "PGYER_DESCRIPTION",
                                       description: "Set the app description",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :update_description,
                                       env_name: "PGYER_UPDATE_DESCRIPTION",
                                       description: "Set update description for app",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :save_uploaded_info_json,
                                       env_name: "PGYER_SAVE_UPLOADED_INFO_JSON",
                                       description: "Save uploaded info json to file named pgyer-fastlane-uploaded-app-info.json",
                                       optional: true,
                                       default_value: false,
                                       type: Boolean),
          FastlaneCore::ConfigItem.new(key: :install_type,
                                       env_name: "PGYER_INSTALL_TYPE",
                                       description: "Set install type for app (1=public, 2=password, 3=invite). Unset keeps the setting of the previous version, or 2 when a password is set",
                                       optional: true,
                                       skip_type_validation: true, # a String or a number
                                       verify_block: proc do |value|
                                         Helper::PgyerHelper.install_type(value)
                                       end),
          FastlaneCore::ConfigItem.new(key: :install_date,
                                       env_name: "PGYER_INSTALL_DATE",
                                       description: "Set the install period (1=between install_start_date and install_end_date, 2=no time limit). Unset keeps the previous setting, or uses 1 when both dates are set",
                                       optional: true,
                                       skip_type_validation: true), # a String or a number
          FastlaneCore::ConfigItem.new(key: :install_start_date,
                                       env_name: "PGYER_INSTALL_START_DATE",
                                       description: "The first day the app can be installed, such as 2018-01-01",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :install_end_date,
                                       env_name: "PGYER_INSTALL_END_DATE",
                                       description: "The last day the app can be installed, such as 2018-12-31",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :oversea,
                                       env_name: "PGYER_OVERSEA",
                                       description: "Upload storage region: true (or 1) for overseas, false (or 2) for mainland China. Unset lets PGYER choose by your IP address",
                                       optional: true,
                                       skip_type_validation: true, # true, false, 1, 2 or a String of them
                                       verify_block: proc do |value|
                                         Helper::PgyerHelper.oversea(value)
                                       end),
          FastlaneCore::ConfigItem.new(key: :channel,
                                       env_name: "PGYER_SPECIFIED_CHANNEL",
                                       description: "Need to update the specified channel of the download short link, can specify only one channel, string type, such as: ABCD",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :processing_timeout,
                                       env_name: "PGYER_PROCESSING_TIMEOUT",
                                       description: "Seconds to wait for PGYER to process the build after the upload",
                                       optional: true,
                                       default_value: 600,
                                       type: Integer,
                                       verify_block: proc do |value|
                                         UI.user_error!("processing_timeout must be a positive number of seconds") unless value.to_i > 0
                                       end),
          FastlaneCore::ConfigItem.new(key: :doh,
                                       env_name: "PGYER_DOH",
                                       description: "Look up the PGYER API servers with DNS over HTTPS instead of the system DNS. TLS certificates are still verified. Needs Ruby 2.7 or later",
                                       optional: true,
                                       default_value: false,
                                       type: Boolean),
        ]
      end

      def self.is_supported?(platform)
        # Works for any platform that produces an .ipa, .apk or .hap file
        true
      end
    end
  end
end
