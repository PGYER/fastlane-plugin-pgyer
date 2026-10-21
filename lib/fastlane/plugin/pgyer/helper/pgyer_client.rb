require "faraday"
require "faraday/multipart"
require "json"
require "net/http"
require "openssl"
require "uri"
require "fastlane_core/ui/ui"
require_relative "../version"
require_relative "pgyer_helper"

module Fastlane
  UI = FastlaneCore::UI unless Fastlane.const_defined?("UI")

  module Helper
    # Uploads a build with the PGYER API: get a COS upload token, send the file to COS, then wait
    # until PGYER has processed the build.
    class PgyerClient
      # Tried in order; the later ones help when DNS for the main domain is blocked or hijacked
      API_SERVERS = [
        "https://www.pgyer.com",
        "https://www.xcxwo.com",
        "https://www.pgyerapp.com",
      ].freeze

      PROCESSING_CODES = [1246, 1247].freeze
      API_TIMEOUT = 30
      OPEN_TIMEOUT = 15
      UPLOAD_TIMEOUT = 300
      POLL_INTERVAL = 3
      DOH_URL = "https://dns.alidns.com/resolve"

      # The server could not be reached or did not answer with PGYER's JSON, so the next one is tried
      class NetworkError < StandardError; end

      NETWORK_ERRORS = [
        Faraday::Error,
        SystemCallError,
        IOError,
        SocketError,
        Timeout::Error,
        OpenSSL::SSL::SSLError,
      ].freeze

      attr_reader :server

      def initialize(servers: API_SERVERS, doh: false, poll_interval: POLL_INTERVAL, clock: nil, sleeper: nil)
        @servers = servers
        @doh = doh ? doh_supported? : false
        @poll_interval = poll_interval
        @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        @sleeper = sleeper || ->(seconds) { sleep(seconds) }
        @addresses = {}
        @secrets = []
      end

      def self.user_agent
        fastlane_version = defined?(Fastlane::VERSION) ? Fastlane::VERSION : "unknown"
        "fastlane-plugin-pgyer/#{Fastlane::Pgyer::VERSION} fastlane/#{fastlane_version} Ruby/#{RUBY_VERSION}"
      end

      # Uploads the file and returns the build information once PGYER has published it
      def upload(file, form, file_name: nil, processing_timeout: 600)
        add_secrets(form["_api_key"], form["buildPassword"])
        token = request_token(form)
        send_file(token, file, file_name)
        UI.message("Upload finished. Waiting for PGYER to process the build...")
        wait_for_build(form["_api_key"], token["key"], processing_timeout)
      end

      def request_token(form)
        @servers.each_with_index do |server, index|
          begin
            json = post_form(server, "/apiv2/app/getCOSToken", form)
          rescue NetworkError => e
            next_step = index < @servers.length - 1 ? ", trying the next server" : ""
            UI.important("#{server} is not reachable (#{e.message})#{next_step}")
            next
          end

          api_error!(json) unless json["code"].to_i == 0
          data = json["data"]
          token = data.kind_of?(Hash) ? data : {}
          if blank?(token["key"]) || blank?(token["endpoint"]) || !token["params"].kind_of?(Hash)
            UI.user_error!("PGYER returned an incomplete upload token")
          end
          add_secrets(token["params"]["signature"], token["params"]["x-cos-security-token"])
          @server = server
          return token
        end

        UI.user_error!("None of the PGYER API servers could be reached: #{@servers.join(', ')}")
      end

      def send_file(token, file, file_name)
        fields = {}
        token["params"].each { |name, value| fields[name.to_s] = value.to_s }
        fields["x-cos-meta-file-name"] = file_name unless blank?(file_name)
        # COS needs the file as the last field
        fields["file"] = Faraday::Multipart::FilePart.new(file, content_type(file), upload_file_name(file))

        UI.message("Uploading #{File.basename(file)} (#{human_size(File.size(file))})...")
        connection = Faraday.new(nil, request: { timeout: UPLOAD_TIMEOUT, open_timeout: OPEN_TIMEOUT }, headers: { "User-Agent" => self.class.user_agent }) do |c|
          c.request(:multipart)
          c.request(:url_encoded)
          c.adapter(:net_http)
        end

        begin
          response = connection.post(token["endpoint"], fields)
        rescue *NETWORK_ERRORS => e
          UI.user_error!(redact("Uploading the file to storage failed: #{e.message}"))
        ensure
          fields["file"].close
        end

        unless response.status.between?(200, 299)
          UI.user_error!(redact("Uploading the file to storage failed with HTTP #{response.status}: #{abbreviate(response.body)}"))
        end
      end

      def wait_for_build(api_key, build_key, timeout)
        form = { "_api_key" => api_key, "buildKey" => build_key }
        deadline = @clock.call + timeout
        reported_network_error = false

        loop do
          json = nil
          begin
            json = post_form(@server, "/apiv2/app/buildInfo", form)
          rescue NetworkError => e
            # The file is already uploaded, so keep polling through short network problems
            unless reported_network_error
              UI.important("Checking the build status failed (#{e.message}), retrying...")
              reported_network_error = true
            end
          end

          unless json.nil?
            code = json["code"].to_i
            if code == 0
              UI.user_error!("PGYER returned no build information. Build key: #{build_key}") unless json["data"].kind_of?(Hash)
              return json["data"]
            end
            api_error!(json, build_key) unless PROCESSING_CODES.include?(code)
          end

          if @clock.call > deadline
            UI.user_error!("PGYER is still processing the build after #{timeout} seconds. It may still be published; check your app list on PGYER. Build key: #{build_key}")
          end
          @sleeper.call(@poll_interval)
        end
      end

      # Posts a form to the PGYER API and returns the parsed JSON. Raises NetworkError when the server
      # can't be reached or the answer is not PGYER's JSON (a captive portal, a hijacked DNS record or a proxy error page)
      def post_form(server, path, form)
        begin
          response = api_connection(server).post(path, form)
        rescue *NETWORK_ERRORS => e
          raise NetworkError, redact(e.message)
        end

        begin
          json = JSON.parse(response.body.to_s)
        rescue JSON::ParserError
          raise NetworkError, "HTTP #{response.status} with a non-JSON response"
        end
        unless json.kind_of?(Hash) && json.key?("code")
          raise NetworkError, "HTTP #{response.status} with an unexpected response"
        end

        json
      end

      def api_connection(server)
        address = @doh ? doh_address(URI.parse(server).host) : nil
        Faraday.new(server, request: { timeout: API_TIMEOUT, open_timeout: OPEN_TIMEOUT }, headers: { "User-Agent" => self.class.user_agent }) do |c|
          c.request(:url_encoded)
          c.adapter(:net_http) { |http| self.class.connect_to(http, address) }
        end
      end

      # Connects to the address found with DoH. Net::HTTP still uses the host name of the URL for SNI,
      # the Host header and certificate verification, so TLS is verified as usual.
      def self.connect_to(http, address)
        http.ipaddr = address unless address.nil?
      end

      # DNS over HTTPS, for networks whose DNS blocks or hijacks the PGYER domains
      def doh_address(host)
        return @addresses[host] if @addresses.key?(host)

        begin
          connection = Faraday.new(nil, request: { timeout: API_TIMEOUT, open_timeout: OPEN_TIMEOUT }, headers: { "User-Agent" => self.class.user_agent }) do |c|
            c.adapter(:net_http)
          end
          response = connection.get(DOH_URL, { name: host, type: "A" })
          answers = JSON.parse(response.body.to_s)["Answer"] || []
        rescue JSON::ParserError, NoMethodError, TypeError, *NETWORK_ERRORS => e
          raise NetworkError, "DNS over HTTPS lookup of #{host} failed: #{e.message}"
        end

        record = answers.find { |answer| answer.kind_of?(Hash) && answer["type"] == 1 && !blank?(answer["data"]) }
        raise NetworkError, "DNS over HTTPS found no address for #{host}" if record.nil?

        UI.message("DNS over HTTPS: #{host} is #{record['data']}")
        @addresses[host] = record["data"]
      end

      private

      def doh_supported?
        return true if Net::HTTP.method_defined?(:ipaddr=)

        UI.important("The doh option needs Ruby 2.7 or later, so the system DNS is used")
        false
      end

      def api_error!(json, build_key = nil)
        code = json["code"]
        message = "PGYER API error #{code}"
        server_message = json["message"].to_s.strip
        message += ": #{server_message}" unless server_message.empty?
        message += " (build key: #{build_key})" unless build_key.nil?
        hint = PgyerHelper.hint(code)
        message += "\n#{hint}" unless hint.nil?
        UI.user_error!(redact(message))
      end

      def add_secrets(*values)
        values.each do |value|
          @secrets << value.to_s unless blank?(value) || @secrets.include?(value.to_s)
        end
      end

      # Removes the API key, the password and the upload credentials from text that gets printed
      def redact(text)
        result = text.to_s.dup
        @secrets.each { |secret| result = result.gsub(secret, "******") }
        result.gsub(/(q-(?:ak|signature)=)[^&\s"<]+/, '\1******')
      end

      def blank?(value)
        PgyerHelper.blank?(value)
      end

      def content_type(file)
        File.extname(file).casecmp(".apk").zero? ? "application/vnd.android.package-archive" : "application/octet-stream"
      end

      # The file name in the multipart header; non-ASCII names are replaced as some servers reject them
      def upload_file_name(file)
        name = File.basename(file)
        return name if PgyerHelper.printable_ascii?(name) && !name.include?('"')

        "upload#{File.extname(name)}"
      end

      def human_size(bytes)
        if bytes < 1024 * 1024
          format("%.1f KB", bytes / 1024.0)
        else
          format("%.1f MB", bytes / (1024.0 * 1024))
        end
      end

      def abbreviate(text)
        text = text.to_s
        text.length > 500 ? "#{text[0, 500]}..." : text
      end
    end
  end
end
