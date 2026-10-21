describe Fastlane::Helper::PgyerClient do
  let!(:output) { capture_ui }
  let(:apk) { build_file("app-release.apk", "apk content") }
  let(:form) { { "_api_key" => api_key, "buildType" => "android", "buildPassword" => password } }
  let(:client) do
    clock = fake_clock
    described_class.new(clock: -> { clock.now }, sleeper: ->(seconds) { clock.sleep(seconds) })
  end

  def upload(timeout: 600)
    client.upload(apk, form, file_name: "app-release.apk", processing_timeout: timeout)
  end

  def error_of
    yield
    raise "expected an error"
  rescue FastlaneCore::Interface::FastlaneError => e
    e.message
  end

  it "uploads the file and returns the build information" do
    stub_pgyer
    expect(upload).to include("buildShortcutUrl" => "abcd", "buildName" => "Demo")
    expect(client.server).to eq("https://www.pgyer.com")
  end

  it "sends a User-Agent naming the plugin, fastlane and Ruby on every request" do
    stub_pgyer
    upload
    agent = %r{\Afastlane-plugin-pgyer/#{Regexp.escape(Fastlane::Pgyer::VERSION)} fastlane/\S+ Ruby/#{Regexp.escape(RUBY_VERSION)}\z}o
    requests = token_requests + upload_requests + build_info_requests
    expect(requests.length).to eq(3)
    requests.each { |request| expect(request.headers["User-Agent"]).to match(agent) }
  end

  describe "server fallback" do
    it "tries the next server after a network error" do
      stub_request(:post, token_url(servers[0])).to_raise(SocketError.new("getaddrinfo: nodename nor servname provided"))
      stub_pgyer(server: servers[1])
      upload
      expect(token_requests(servers[1]).length).to eq(1)
      expect(output.join("\n")).to include("https://www.pgyer.com is not reachable")
    end

    it "tries the next server after a timeout" do
      stub_request(:post, token_url(servers[0])).to_timeout
      stub_pgyer(server: servers[1])
      upload
      expect(token_requests(servers[1]).length).to eq(1)
    end

    it "tries the next server when the answer is not JSON, such as a hijacked DNS record" do
      stub_request(:post, token_url(servers[0])).to_return(status: 200, body: "<html>Welcome to the hotel Wi-Fi</html>")
      stub_request(:post, token_url(servers[1])).to_return(status: 502, body: "Bad Gateway")
      stub_pgyer(server: servers[2])
      upload
      expect(token_requests(servers[2]).length).to eq(1)
      expect(output.join("\n")).to include("non-JSON response")
    end

    it "stops at the first JSON error without trying other servers" do
      stub_request(:post, token_url(servers[0])).to_return(json_response({ code: 1001, message: "Invalid _api_key" }))
      message = error_of { upload }
      expect(message).to include("PGYER API error 1001: Invalid _api_key")
      expect(message).to include("Check that the API key is correct")
      expect(token_requests(servers[1])).to be_empty
      expect(upload_requests).to be_empty
    end

    it "fails when no server can be reached" do
      servers.each { |server| stub_request(:post, token_url(server)).to_raise(Errno::ECONNREFUSED) }
      expect(error_of { upload }).to include("None of the PGYER API servers could be reached")
    end

    it "polls the server that answered" do
      stub_request(:post, token_url(servers[0])).to_raise(SocketError.new("no route"))
      stub_pgyer(server: servers[1])
      upload
      expect(build_info_requests(servers[1]).length).to eq(1)
      expect(build_info_requests(servers[0])).to be_empty
    end

    it "rejects an incomplete token" do
      stub_request(:post, token_url).to_return(json_response({ code: 0, data: { key: build_key } }))
      expect(error_of { upload }).to include("incomplete upload token")
    end
  end

  describe "error hints" do
    {
      1002 => "Check that the API key is correct. You can find it at https://www.pgyer.com/account/api",
      1003 => "Sub-accounts cannot use the API. Use the API key of the main account.",
      1019 => "Complete real-name verification before uploading: https://www.pgyer.com/account/certification",
      1020 => "Uploading is disabled for this account. Contact PGYER customer service.",
      1022 => "Your PGYER storage is full or the file is too large. Free up space or upgrade your plan.",
    }.each do |code, hint|
      it "explains error #{code}" do
        stub_request(:post, token_url).to_return(json_response({ code: code, message: "server message" }))
        expect(error_of { upload }).to eq("PGYER API error #{code}: server message\n#{hint}")
      end
    end
  end

  describe "file upload" do
    it "sends the token fields, the download file name and then the file" do
      stub_pgyer
      upload
      body = upload_requests.first.body
      expect(body).to include("name=\"signature\"\r\n\r\n#{signature}\r\n")
      expect(body).to include("name=\"x-cos-security-token\"\r\n\r\n#{security_token}\r\n")
      expect(body).to include("name=\"key\"\r\n\r\n#{build_key}\r\n")
      expect(body).to include("name=\"x-cos-meta-file-name\"\r\n\r\napp-release.apk\r\n")
      expect(body).to include("name=\"file\"; filename=\"app-release.apk\"")
      expect(body).to include("apk content")
      expect(body.index("name=\"file\"")).to be > body.index("name=\"x-cos-meta-file-name\"")
    end

    it "leaves out the download file name when there is none" do
      stub_pgyer
      client.upload(apk, form, file_name: nil, processing_timeout: 600)
      expect(upload_requests.first.body).not_to include("x-cos-meta-file-name")
    end

    it "accepts any 2xx status" do
      stub_pgyer(upload: { status: 200, body: "" })
      expect(upload).to include("buildName" => "Demo")
    end

    it "fails on other statuses without printing the credentials" do
      stub_pgyer(upload: { status: 403, body: "<Error><Code>AccessDenied</Code><Token>#{security_token}</Token><Sign>#{signature}</Sign></Error>" })
      message = error_of { upload }
      expect(message).to include("failed with HTTP 403")
      expect(message).to include("AccessDenied")
      expect(message).not_to include(security_token)
      expect(message).not_to include("5ec7e75eca1e")
      expect(message).not_to include("AKIDspecaccess")
      expect(build_info_requests).to be_empty
    end
  end

  describe "waiting for the build" do
    it "polls every 3 seconds until the build is processed" do
      stub_pgyer(build_info: [json_response(processing_body(1246)), json_response(processing_body(1247)), json_response(build_info_body)])
      expect(upload).to include("buildShortcutUrl" => "abcd")
      expect(build_info_requests.length).to eq(3)
      expect(fake_clock.sleeps).to eq([3, 3])
      build_info_requests.each { |request| expect(form_of(request)).to eq("_api_key" => api_key, "buildKey" => build_key) }
    end

    it "keeps polling after network errors because the file is already uploaded" do
      stub_pgyer
      stub_request(:post, build_info_url)
        .to_raise(SocketError.new("connection reset"))
        .then.to_return(status: 504, body: "<html>Gateway Timeout</html>")
        .then.to_return(json_response(processing_body))
        .then.to_return(json_response(build_info_body))
      expect(upload).to include("buildName" => "Demo")
      expect(build_info_requests.length).to eq(4)
      expect(output.grep(/Checking the build status failed/).length).to eq(1)
    end

    it "gives up after the processing timeout and says the build may still be published" do
      stub_pgyer(build_info: [json_response(processing_body)])
      message = error_of { upload(timeout: 10) }
      expect(message).to include("still processing the build after 10 seconds")
      expect(message).to include("may still be published")
      expect(message).to include(build_key)
      expect(build_info_requests.length).to eq(5)
    end

    it "gives up after the timeout when the server stays unreachable" do
      stub_pgyer
      stub_request(:post, build_info_url).to_raise(Errno::ECONNRESET)
      expect(error_of { upload(timeout: 6) }).to include("may still be published")
    end

    it "stops on other error codes" do
      stub_pgyer(build_info: [json_response(processing_body), json_response({ code: 1216, message: "App failed to publish." })])
      message = error_of { upload }
      expect(message).to eq("PGYER API error 1216: App failed to publish. (build key: #{build_key})")
      expect(build_info_requests.length).to eq(2)
    end
  end

  it "never prints the API key, the password or the upload credentials" do
    stub_pgyer(build_info: [json_response(processing_body), json_response(build_info_body)])
    upload
    printed = output.join("\n")
    [api_key, password, security_token, signature, "5ec7e75eca1e"].each { |secret| expect(printed).not_to include(secret) }
  end

  describe "DNS over HTTPS" do
    let(:client) { described_class.new(doh: true, sleeper: ->(_seconds) {}) }

    def stub_doh(host, body)
      stub_request(:get, "https://dns.alidns.com/resolve").with(query: { name: host, type: "A" }).to_return(json_response(body))
    end

    it "connects to the address it found but keeps verifying the certificate of the host name" do
      stub_doh("www.pgyer.com", { "Status" => 0, "Answer" => [{ "name" => "www.pgyer.com.", "type" => 5, "data" => "cdn.example." }, { "name" => "cdn.example.", "type" => 1, "data" => "203.0.113.7" }] })
      connections = []
      allow(described_class).to receive(:connect_to).and_wrap_original do |original, http, address|
        connections << [http.address, address, http.verify_mode]
        original.call(http, address)
      end
      stub_pgyer
      upload
      expect(connections.length).to eq(2)
      connections.each do |host, address, verify_mode|
        expect(host).to eq("www.pgyer.com")
        expect(address).to eq("203.0.113.7")
        expect(verify_mode).to eq(OpenSSL::SSL::VERIFY_PEER)
      end
    end

    it "moves on to the next server when the lookup fails" do
      stub_doh("www.pgyer.com", { "Status" => 3 })
      stub_doh("www.xcxwo.com", { "Status" => 0, "Answer" => [{ "type" => 1, "data" => "203.0.113.8" }] })
      stub_pgyer(server: servers[1])
      upload
      expect(token_requests(servers[1]).length).to eq(1)
      expect(output.join("\n")).to include("found no address for www.pgyer.com")
    end

    it "sets the address on Net::HTTP without touching TLS verification" do
      http = Net::HTTP.new("www.pgyer.com", 443)
      described_class.connect_to(http, "203.0.113.7")
      expect(http.ipaddr).to eq("203.0.113.7")
      expect(http.verify_mode).to be_nil
    end
  end
end
