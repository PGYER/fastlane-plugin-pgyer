require "faraday"
require "faraday_middleware"
require "timeout"

module Fastlane
  module Actions
    class PgyerAction < Action
      def self.run(params)
        UI.message("The pgyer plugin is working.")

        api_key = params[:api_key]

        build_file = [
          params[:ipa],
          params[:apk],
          params[:hap],
        ].detect { |e| !e.to_s.empty? }

        if build_file.nil?
          UI.user_error!("You have to provide a build file")
        end

        type = get_type(params)

        UI.message "build_file: #{build_file}, type: #{type}"

        install_type = params[:install_type]
        if install_type.nil?
          install_type = "1"
        end

        password = params[:password]
        if password.nil?
          password = ""
        end

        request_params = {
          "_api_key" => api_key,
          "buildType" => type,
          "buildInstallType" => install_type,
          "buildPassword" => password,
        }
        request_params["oversea"] = params[:oversea] unless params[:oversea].nil?

        update_description = params[:update_description]

        if update_description != nil
          request_params["buildUpdateDescription"] = update_description
        end

        install_date = params[:install_date]

        if install_date != nil
          if install_date == "1"
            request_params["buildInstallDate"] = install_date
            install_start_date = params[:install_start_date]
            request_params["buildInstallStartDate"] = install_start_date
            install_end_date = params[:install_end_date]
            request_params["buildInstallEndDate"] = install_end_date
          elsif install_date == "2"
            request_params["buildInstallDate"] = install_date
          end
        end

        channel = params[:channel]
        if channel != nil
          request_params["buildChannelShortcut"] = channel
        end

        # start upload
        conn_options = {
          request: {
            timeout: 1000,
            open_timeout: 300,
          },
        }

        # 选择可用的 API 域名
        use_doh = params[:doh] == true
        api_host, pgyer_client, info = self.select_available_api_host(conn_options, request_params, use_doh)

        if info["code"] != 0
          UI.user_error!("Get token is failed, info: #{info}")
        end

        key = info["data"]["key"]

        endpoint = info["data"]["endpoint"]

        request_params = info["data"]["params"]

        if key.nil? || endpoint.nil? || request_params.nil?
          UI.user_error!("Get token is failed")
        end
        content_type = type == "android" ? "application/vnd.android.package-archive" : "application/octet-stream"

        if !params[:user_download_file_name].nil?
          request_params["x-cos-meta-file-name"] = params[:user_download_file_name]
        end
        request_params["file"] = Faraday::UploadIO.new(build_file, content_type)

        UI.message "Start upload #{build_file} to pgyer..."

        UI.message "Upload endpoint: #{endpoint}"

        UI.message "Upload request_params: #{request_params}"



        response = pgyer_client.post endpoint, request_params

        if response.status != 204
          UI.user_error!("PGYER Plugin Upload Error: #{response.body}")
        end

        # 如果使用 DoH，需要传递 DoH 相关信息
        doh_info = nil
        if use_doh && api_host.include?("www.pgyer.com")
          domain = "www.pgyer.com"
          ip_address = resolve_domain_via_doh(domain)
          if ip_address
            doh_info = { domain: domain, ip_address: ip_address }
          end
        end
        answer = self.checkPublishStatus(pgyer_client, api_host, api_key, key, doh_info)

        if params[:save_uploaded_info_json]
          File.open("pgyer-fastlane-uploaded-app-info.json", "w") do |f|
            f.write(answer.to_json)
          end
        end
        answer
      end

      def self.description
        "distribute app to pgyer beta testing service"
      end

      def self.authors
        ["rexshi"]
      end

      def self.return_value
        # If your method provides a return value, you can describe here what it does
      end

      def self.details
        # Optional:
        "distribute app to pgyer beta testing service"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :api_key,
                                       env_name: "PGYER_API_KEY",
                                       description: "api_key in your pgyer account",
                                       optional: false,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :apk,
                                       env_name: "PGYER_APK",
                                       description: "Path to your APK file",
                                       default_value: Actions.lane_context[SharedValues::GRADLE_APK_OUTPUT_PATH],
                                       optional: true,
                                       verify_block: proc do |value|
                                         UI.user_error!("Couldn't find apk file at path '#{value}'") unless File.exist?(value)
                                       end,
                                       conflicting_options: [:ipa, :hap],
                                       conflict_block: proc do |value|
                                         UI.user_error!("You can't use 'apk' and '#{value.key}' options in one run")
                                       end),
          FastlaneCore::ConfigItem.new(key: :ipa,
                                       env_name: "PGYER_IPA",
                                       description: "Path to your IPA file. Optional if you use the _gym_ or _xcodebuild_ action. For Mac zip the .app. For Android provide path to .apk file",
                                       default_value: Actions.lane_context[SharedValues::IPA_OUTPUT_PATH],
                                       optional: true,
                                       verify_block: proc do |value|
                                         UI.user_error!("Couldn't find ipa file at path '#{value}'") unless File.exist?(value)
                                       end,
                                       conflicting_options: [:apk, :hap],
                                       conflict_block: proc do |value|
                                         UI.user_error!("You can't use 'ipa' and '#{value.key}' options in one run")
                                       end),
          FastlaneCore::ConfigItem.new(key: :hap,
                                       env_name: "PGYER_HAP",
                                       description: "Path to your HAP file",
                                       default_value: Actions.lane_context[:HVIGOR_HAP_OUTPUT_PATH],
                                       optional: true,
                                       verify_block: proc do |value|
                                         UI.user_error!("Couldn't find hap file at path '#{value}'") unless File.exist?(value)
                                       end,
                                       conflicting_options: [:apk, :ipa],
                                       conflict_block: proc do |value|
                                         UI.user_error!("You can't use 'hap' and '#{value.key}' options in one run")
                                       end),
          FastlaneCore::ConfigItem.new(key: :password,
                                       env_name: "PGYER_PASSWORD",
                                       description: "Set password to protect app",
                                       optional: true,
                                       type: String),

          FastlaneCore::ConfigItem.new(key: :user_download_file_name,
                                       env_name: "USER_DOWNLOAD_FILE_NAME",
                                       description: "Rename the file name that user downloaded from pgyer",
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
                                       description: "Set install type for app (1=public, 2=password, 3=invite). Please set as a string",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :install_date,
                                       env_name: "PGYER_INSTALL_DATE",
                                       description: "Set install type for app (1=Set valid time, 2=Long-term effective, other=Do not modify the last setting). Please set as a string",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :install_start_date,
                                       env_name: "PGYER_INSTALL_START_DATE",
                                       description: "The value is a string of characters, for example, 2018-01-01",
                                       optional: true,
                                       type: String),

          FastlaneCore::ConfigItem.new(key: :install_end_date,
                                       env_name: "PGYER_INSTALL_END_DATE",
                                       description: "The value is a string of characters, such as 2018-12-31",
                                       optional: true,
                                       type: String),

          FastlaneCore::ConfigItem.new(key: :oversea,
                                       env_name: "PGYER_OVERSEA",
                                       description: "Whether to use overseas acceleration. 1 for overseas accelerated upload, 0 for domestic accelerated upload, not filled in for automatic judgment based on IP",
                                       optional: true,
                                       type: Numeric),
          FastlaneCore::ConfigItem.new(key: :channel,
                                       env_name: "PGYER_SPECIFIED_CHANNEL",
                                       description: "Need to update the specified channel of the download short link, can specify only one channel, string type, such as: ABCD",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :doh,
                                       env_name: "PGYER_DOH",
                                       description: "Use DNS over HTTPS (DoH) to resolve domain names, bypassing local DNS. Experimental feature",
                                       optional: true,
                                       default_value: false,
                                       type: Boolean),
        ]
      end

      def self.is_supported?(platform)
        # Adjust this if your plugin only works for a particular platform (iOS vs. Android, for example)
        # See: https://github.com/fastlane/fastlane/blob/master/fastlane/docs/Platforms.md
        #
        [:ios, :mac, :android].include?(platform)
        true
      end

      private

      def self.select_available_api_host(conn_options, request_params, use_doh = false)
        # 如果启用 DoH，直接使用 DoH 解析 www.pgyer.com，跳过三个域名测试
        if use_doh
          return select_api_host_via_doh(conn_options, request_params)
        end

        # 尝试多个域名，防止 DNS 劫持
        api_hosts = [
          "https://www.pgyer.com/apiv2/app",
          "https://www.xcxwo.com/apiv2/app",
          "https://www.pgyerapp.com/apiv2/app",
        ]

        api_host = nil
        pgyer_client = nil
        info = nil

        api_hosts.each_with_index do |host, index|
          UI.message "尝试使用域名 #{index + 1}/#{api_hosts.length}: #{host}"

          begin
            # 为域名检测设置 5 秒超时
            test_conn_options = {
              request: {
                timeout: 5,
                open_timeout: 5,
              },
            }
            test_client = create_faraday_client(test_conn_options, nil)

            # 使用超时控制，5 秒后如果还没响应就放弃
            test_response = nil
            test_info = nil

            begin
              Timeout.timeout(5) do
                test_response = test_client.post "#{host}/getCOSToken", request_params
                test_info = test_response.body
              end
            rescue Timeout::Error
              UI.message "域名 #{host} 请求超时（5秒），切换到下一个域名"
              next
            end

            # 检查响应是否有效：如果返回了有效的 JSON 且包含 code 字段，说明域名解析正常
            if test_info && test_info.is_a?(Hash) && test_info.key?("code")
              if test_info["code"] == 0
                # API 调用成功，使用该域名
                # 使用原始的超时设置重新创建客户端（用于后续上传）
                api_host = host
                pgyer_client = create_faraday_client(conn_options, nil)
                info = test_info
                UI.success "成功使用域名: #{host}"
                break
              else
                # API 返回了业务错误，但域名解析正常
                # 保存第一个可用的域名作为备选，继续尝试其他域名看是否有返回 code == 0 的
                if api_host.nil?
                  api_host = host
                  # 使用原始的超时设置重新创建客户端
                  pgyer_client = create_faraday_client(conn_options, nil)
                  info = test_info
                  UI.message "域名 #{host} 解析正常，但 API 返回错误，保存为备选: #{test_info}"
                else
                  UI.message "域名 #{host} 可用，但 API 返回错误: #{test_info}"
                end
              end
            else
              # 响应格式不正确，可能是 DNS 劫持
              UI.message "域名 #{host} 返回的响应格式不正确，可能遭遇 DNS 劫持"
            end
          rescue => e
            UI.message "域名 #{host} 测试失败（可能是 DNS 劫持或超时）: #{e.message}"
            next
          end
        end

        if api_host.nil? || pgyer_client.nil? || info.nil?
          UI.user_error!("所有域名都无法使用，可能都遭遇了 DNS 劫持。尝试的域名: #{api_hosts.join(', ')}")
        end

        return api_host, pgyer_client, info
      end

      # DoH 模式：使用 DoH 解析 www.pgyer.com（实验性功能）
      def self.select_api_host_via_doh(conn_options, request_params)
        UI.message "启用 DoH 模式，使用 DoH 解析 www.pgyer.com"

        host = "https://www.pgyer.com/apiv2/app"
        domain = "www.pgyer.com"

        # 通过 DoH 解析域名
        ip_address = resolve_domain_via_doh(domain)

        if ip_address.nil?
          UI.user_error!("DoH 解析失败，无法获取 www.pgyer.com 的 IP 地址")
        end

        UI.message "DoH 解析成功: #{domain} -> #{ip_address}"

        # 使用 IP 地址替换域名，但保留 Host header
        actual_url = host.gsub(domain, ip_address)
        host_header = domain

        begin
          test_client = create_faraday_client(conn_options, host_header)

          # 设置 Host header
          request_headers = { "Host" => host_header }

          test_response = test_client.post "#{actual_url}/getCOSToken", request_params, request_headers
          test_info = test_response.body

          if test_info && test_info.is_a?(Hash) && test_info.key?("code")
            if test_info["code"] == 0
              UI.success "DoH 模式：成功使用域名 #{host}"
              return host, test_client, test_info
            else
              UI.user_error!("DoH 模式：API 返回错误: #{test_info}")
            end
          else
            UI.user_error!("DoH 模式：返回的响应格式不正确: #{test_info}")
          end
        rescue => e
          UI.user_error!("DoH 模式：请求失败: #{e.message}")
        end
      end

      # DoH 相关方法（实验性功能）
      def self.resolve_domain_via_doh(domain)
        # 使用阿里云公共 DoH 服务
        doh_url = "https://dns.alidns.com/resolve"

        begin
          doh_client = Faraday.new do |c|
            c.request :url_encoded
            c.response :json
            c.adapter :net_http
          end

          response = doh_client.get(doh_url, { name: domain, type: "A" })
          result = response.body

          if result && result.is_a?(Hash) && result["Answer"]
            # 获取第一个 A 记录
            a_record = result["Answer"].find { |r| r["type"] == 1 }
            if a_record && a_record["data"]
              return a_record["data"]
            end
          end
        rescue => e
          UI.message "DoH 解析出错: #{e.message}"
        end

        return nil
      end

      def self.extract_domain_from_url(url)
        # 从 URL 中提取域名
        # 例如: https://www.pgyer.com/apiv2/app -> www.pgyer.com
        uri = URI.parse(url)
        return uri.host
      end

      def self.create_faraday_client(conn_options, host_header = nil)
        # 创建基础的 Faraday 客户端
        # Host header 将在请求时通过 headers 参数设置
        # DoH 模式下禁用 SSL 证书验证（因为使用 IP 地址，证书绑定域名）
        final_options = conn_options.dup

        Faraday.new(nil, final_options) do |c|
          c.request :multipart
          c.request :url_encoded
          c.response :json, content_type: /\bjson$/
          c.adapter :net_http do |http|
            if host_header
              # DoH 模式：使用 IP 地址，禁用 SSL 证书验证
              http.verify_mode = OpenSSL::SSL::VERIFY_NONE
              UI.message "DoH 模式：已禁用 SSL 证书验证（实验性功能）"
            else
              # 普通模式：使用默认 SSL 验证
              http.verify_mode = OpenSSL::SSL::VERIFY_PEER
            end
          end
        end
      end

      def self.get_type(params)
        type = params[:ipa].nil? ? "android" : "ios"

        if !params[:hap].nil?
          type = "hap"
        end

        type
      end

      def self.checkPublishStatus(client, api_host, api_key, buildKey, doh_info = nil)
        # URL 保持使用域名（用于显示）
        url = "#{api_host}/buildInfo"
        UI.message "checkPublishStatus url: #{url}"

        # 如果使用 DoH，实际请求时使用 IP 地址，但设置 Host header
        actual_url = api_host
        request_headers = {}

        if doh_info && doh_info[:ip_address]
          # 实际连接使用 IP 地址
          actual_url = api_host.gsub(doh_info[:domain], doh_info[:ip_address])
          # 设置 Host header 为原始域名
          request_headers["Host"] = doh_info[:domain]
          UI.message "DoH 模式：实际连接使用 IP 地址 #{doh_info[:ip_address]}，Host header: #{doh_info[:domain]}"
        end

        response = client.post "#{actual_url}/buildInfo", { :_api_key => api_key, :buildKey => buildKey }, request_headers
        info = response.body
        code = info["code"]
        if code == 0
          UI.success "Upload success. BuildInfo is #{info["data"]}."
          shortUrl = info["data"]["buildShortcutUrl"]
          if shortUrl.nil? || shortUrl == ""
            shortUrl = info["data"]["buildKey"]
          end
          info["data"]["fastlaneAddedWholeVisitUrl"] = "https://www.pgyer.com/#{shortUrl}"
          UI.success "Upload success. Visit this URL to see: #{info["data"]["fastlaneAddedWholeVisitUrl"]}"
          return info["data"]
        elsif code == 1246 || code == 1247
          sleep 3
          self.checkPublishStatus(client, api_host, api_key, buildKey, doh_info)
        else
          UI.user_error!("PGYER Plugin Published Error: #{info} buildKey: #{buildKey}")
        end
      end
    end
  end
end
