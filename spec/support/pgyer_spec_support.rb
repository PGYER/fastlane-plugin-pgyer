require "json"
require "uri"

# Fake PGYER API (via WebMock) and helpers shared by the specs
module PgyerSpecSupport
  API_KEY = "spec-api-key-0123456789"
  SIGNATURE = "q-sign-algorithm=sha1&q-ak=AKIDspecaccess&q-sign-time=1&q-key-time=1&q-header-list=&q-url-param-list=&q-signature=5ec7e75eca1e"
  SECURITY_TOKEN = "spec-cos-security-token-9876"
  PASSWORD = "spec-password-42"
  BUILD_KEY = "0123456789abcdef0123456789abcdef.apk"
  COS_ENDPOINT = "https://upload-spec.cos.ap-shanghai.myqcloud.com"
  SERVERS = Fastlane::Helper::PgyerClient::API_SERVERS

  # The constants above for the examples, whose blocks don't see module constants
  {
    api_key: API_KEY,
    signature: SIGNATURE,
    security_token: SECURITY_TOKEN,
    password: PASSWORD,
    build_key: BUILD_KEY,
    cos_endpoint: COS_ENDPOINT,
    servers: SERVERS,
  }.each do |name, value|
    define_method(name) { value }
  end

  # Time that only moves when the client sleeps, so polling specs run instantly
  class FakeClock
    attr_reader :now, :sleeps

    def initialize
      @now = 0.0
      @sleeps = []
    end

    def sleep(seconds)
      @sleeps << seconds
      @now += seconds
    end
  end

  def fake_clock
    @fake_clock ||= FakeClock.new
  end

  # Makes every client the action creates use the fake clock
  def use_fake_clock
    clock = fake_clock
    allow(Fastlane::Helper::PgyerClient).to receive(:new).and_wrap_original do |original, *args, **options|
      original.call(*args, **options, clock: -> { clock.now }, sleeper: ->(seconds) { clock.sleep(seconds) })
    end
  end

  def json_response(body, status: 200)
    { status: status, body: body.to_json, headers: { "Content-Type" => "application/json" } }
  end

  def token_body(key: BUILD_KEY)
    {
      code: 0,
      message: "",
      data: {
        endpoint: COS_ENDPOINT,
        key: key,
        params: {
          "signature" => SIGNATURE,
          "x-cos-security-token" => SECURITY_TOKEN,
          "key" => key,
        },
      },
    }
  end

  def build_info_body(shortcut: "abcd")
    {
      code: 0,
      message: "",
      data: {
        "buildKey" => "0123456789abcdef0123456789abcdef",
        "buildType" => 2,
        "buildName" => "Demo",
        "buildVersion" => "1.2.3",
        "buildVersionNo" => "45",
        "buildShortcutUrl" => shortcut,
        "buildQRCodeURL" => "https://pgyer.com/app/qrcodeHistory/0123456789abcdef",
      },
    }
  end

  def processing_body(code = 1247)
    { code: code, message: "App is being processed. Please call this API later to get the information" }
  end

  def token_url(server = SERVERS.first)
    "#{server}/apiv2/app/getCOSToken"
  end

  def build_info_url(server = SERVERS.first)
    "#{server}/apiv2/app/buildInfo"
  end

  # Stubs a whole successful upload through the given server and records the requests
  def stub_pgyer(server: SERVERS.first, token: json_response(token_body), upload: { status: 204 }, build_info: [json_response(build_info_body)])
    stub_request(:post, token_url(server)).to_return(token)
    stub_request(:post, COS_ENDPOINT).to_return(upload)
    stub_request(:post, build_info_url(server)).to_return(*build_info)
  end

  def form_of(request)
    URI.decode_www_form(request.body).to_h
  end

  def token_requests(server = SERVERS.first)
    requests_to(token_url(server))
  end

  def upload_requests
    requests_to(COS_ENDPOINT)
  end

  def build_info_requests(server = SERVERS.first)
    requests_to(build_info_url(server))
  end

  # Every request the specs make, in order
  def self.requests
    @requests ||= []
  end

  def requests_to(url)
    PgyerSpecSupport.requests.select { |request| request.uri.omit(:port).to_s.chomp("/") == url.chomp("/") }
  end

  def sent_token_form(server = SERVERS.first)
    requests = token_requests(server)
    expect(requests.length).to eq(1)
    form_of(requests.first)
  end

  # Collects everything the plugin prints
  def capture_ui
    output = []
    [:message, :success, :important, :error, :verbose, :header, :deprecated, :command_output].each do |level|
      allow(FastlaneCore::UI).to receive(level) { |*args| output << args.join(" ") }
    end
    output
  end

  def build_dir
    @build_dir ||= Dir.mktmpdir("pgyer-spec")
  end

  def build_file(name, content = "fake build")
    path = File.join(build_dir, name)
    File.write(path, content)
    path
  end

  def configuration(values)
    FastlaneCore::Configuration.create(Fastlane::Actions::PgyerAction.available_options, values)
  end

  def run_action(values)
    Fastlane::Actions::PgyerAction.run(configuration({ api_key: API_KEY }.merge(values)))
  end

  def with_env(values)
    saved = values.keys.to_h { |name| [name, ENV.fetch(name, nil)] }
    values.each { |name, value| ENV[name] = value }
    yield
  ensure
    saved.each { |name, value| ENV[name] = value }
  end
end

WebMock.after_request { |request, _response| PgyerSpecSupport.requests << request }
