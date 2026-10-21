describe Fastlane::Actions::PgyerAction do
  let!(:output) { capture_ui }
  let(:apk) { build_file("app-release.apk") }
  let(:ipa) { build_file("Demo.ipa") }
  let(:hap) { build_file("entry-default-signed.hap") }
  let(:lane_context) { Fastlane::Actions.lane_context }
  let(:shared_values) { Fastlane::Actions::SharedValues }

  before do
    use_fake_clock
    stub_pgyer
  end

  def error_of
    yield
    raise "expected an error"
  rescue FastlaneCore::Interface::FastlaneError => e
    e.message
  end

  def uploaded_file_name
    upload_requests.first.body[/name="file"; filename="([^"]+)"/, 1]
  end

  describe "choosing the build file" do
    it "uploads the file passed as an option even when gym ran earlier in the lane" do
      lane_context[shared_values::IPA_OUTPUT_PATH] = ipa
      run_action(apk: apk)
      expect(uploaded_file_name).to eq("app-release.apk")
      expect(sent_token_form["buildType"]).to eq("android")
    end

    it "uploads the hap passed as an option even when other builds are in the lane context" do
      lane_context[shared_values::IPA_OUTPUT_PATH] = ipa
      lane_context[shared_values::GRADLE_APK_OUTPUT_PATH] = apk
      run_action(hap: hap)
      expect(uploaded_file_name).to eq("entry-default-signed.hap")
      expect(sent_token_form["buildType"]).to eq("harmony")
    end

    it "falls back to the lane context in the order ipa, apk, hap" do
      lane_context[shared_values::GRADLE_APK_OUTPUT_PATH] = apk
      lane_context[shared_values::IPA_OUTPUT_PATH] = ipa
      lane_context[:HVIGOR_HAP_OUTPUT_PATH] = hap
      run_action({})
      expect(uploaded_file_name).to eq("Demo.ipa")
      expect(sent_token_form["buildType"]).to eq("ios")
    end

    it "uses the gradle output when there is no ipa" do
      lane_context[shared_values::GRADLE_APK_OUTPUT_PATH] = apk
      lane_context[:HVIGOR_HAP_OUTPUT_PATH] = hap
      run_action({})
      expect(sent_token_form["buildType"]).to eq("android")
    end

    it "uses the hvigor output when there is nothing else" do
      lane_context[:HVIGOR_HAP_OUTPUT_PATH] = hap
      run_action({})
      expect(sent_token_form["buildType"]).to eq("harmony")
    end

    it "detects the type from the file, not from the option it came from" do
      run_action(ipa: apk)
      expect(sent_token_form["buildType"]).to eq("android")
    end

    it "rejects two build files passed as options" do
      expect { run_action(apk: apk, ipa: ipa) }.to raise_error(FastlaneCore::Interface::FastlaneError, /can't use/)
    end

    it "rejects two build files when one comes from an environment variable" do
      with_env("PGYER_IPA" => ipa) do
        expect(error_of { run_action(apk: apk) }).to include("Set only one of the ipa, apk and hap options (found ipa, apk)")
      end
      expect(token_requests).to be_empty
    end

    it "fails without a build file" do
      expect(error_of { run_action({}) }).to include("You have to provide a build file")
    end

    it "fails when the lane context points to a missing file" do
      lane_context[shared_values::GRADLE_APK_OUTPUT_PATH] = File.join(build_dir, "missing.apk")
      expect(error_of { run_action({}) }).to include("Couldn't find build file")
    end

    it "rejects files PGYER does not accept" do
      expect(error_of { run_action(apk: build_file("app.aab")) }).to include(".apk, .ipa and .hap")
      expect(token_requests).to be_empty
    end

    it "expands ~ in paths" do
      home = File.dirname(apk)
      with_env("HOME" => home) do
        run_action(apk: "~/app-release.apk")
      end
      expect(uploaded_file_name).to eq("app-release.apk")
    end
  end

  describe "options sent to PGYER" do
    it "omits the options that are not set" do
      run_action(apk: apk)
      expect(sent_token_form).to eq("_api_key" => api_key, "buildType" => "android")
    end

    it "sends the options that are set" do
      run_action(apk: apk, install_type: 3, description: "About", update_description: "Notes", channel: "ABCD", oversea: false, install_start_date: "2026-01-01", install_end_date: "2026-12-31")
      expect(sent_token_form).to eq(
        "_api_key" => api_key,
        "buildType" => "android",
        "buildInstallType" => "3",
        "buildDescription" => "About",
        "buildUpdateDescription" => "Notes",
        "buildChannelShortcut" => "ABCD",
        "oversea" => "2",
        "buildInstallDate" => "1",
        "buildInstallStartDate" => "2026-01-01",
        "buildInstallEndDate" => "2026-12-31"
      )
    end

    it "sends install type 2 with a password" do
      run_action(apk: apk, password: "123456")
      expect(sent_token_form).to include("buildInstallType" => "2", "buildPassword" => "123456")
    end

    it "reads oversea from PGYER_OVERSEA" do
      with_env("PGYER_OVERSEA" => "true") { run_action(apk: apk) }
      expect(sent_token_form["oversea"]).to eq("1")
    end

    it "accepts the legacy numeric oversea values" do
      with_env("PGYER_OVERSEA" => "2") { run_action(apk: apk) }
      expect(sent_token_form["oversea"]).to eq("2")
    end

    it "treats oversea 0 as unset" do
      run_action(apk: apk, oversea: 0)
      expect(sent_token_form).not_to include("oversea")
    end

    it "rejects an invalid oversea value before uploading" do
      expect { run_action(apk: apk, oversea: "3") }.to raise_error(FastlaneCore::Interface::FastlaneError, /oversea/)
    end

    it "reads install_type from PGYER_INSTALL_TYPE" do
      with_env("PGYER_INSTALL_TYPE" => "1") { run_action(apk: apk) }
      expect(sent_token_form["buildInstallType"]).to eq("1")
    end
  end

  describe "download file name" do
    def sent_file_name
      upload_requests.first.body[/name="x-cos-meta-file-name"\r\n\r\n([^\r]*)\r\n/, 1]
    end

    it "defaults to the name of the uploaded file" do
      run_action(apk: apk)
      expect(sent_file_name).to eq("app-release.apk")
    end

    it "uses user_download_file_name" do
      run_action(apk: apk, user_download_file_name: "demo.apk")
      expect(sent_file_name).to eq("demo.apk")
    end

    it "reads PGYER_USER_DOWNLOAD_FILE_NAME and the legacy USER_DOWNLOAD_FILE_NAME" do
      with_env("PGYER_USER_DOWNLOAD_FILE_NAME" => "new.apk", "USER_DOWNLOAD_FILE_NAME" => "old.apk") { run_action(apk: apk) }
      expect(sent_file_name).to eq("new.apk")

      PgyerSpecSupport.requests.clear
      with_env("USER_DOWNLOAD_FILE_NAME" => "old.apk") { run_action(apk: apk) }
      expect(sent_file_name).to eq("old.apk")
    end
  end

  describe "result" do
    it "returns the build information with the download page and QR code URLs" do
      result = run_action(apk: apk)
      expect(result).to include(
        "buildName" => "Demo",
        "appPgyerURL" => "https://www.pgyer.com/abcd",
        "appQRCodeURL" => "https://pgyer.com/app/qrcodeHistory/0123456789abcdef",
        "fastlaneAddedWholeVisitUrl" => "https://www.pgyer.com/abcd"
      )
    end

    it "stores the result in the lane context" do
      result = run_action(apk: apk)
      expect(lane_context[shared_values::PGYER_OUTPUT]).to eq(result)
      expect(lane_context[shared_values::PGYER_DOWNLOAD_URL]).to eq("https://www.pgyer.com/abcd")
      expect(lane_context[shared_values::PGYER_QRCODE_URL]).to eq("https://pgyer.com/app/qrcodeHistory/0123456789abcdef")
    end

    it "saves the result as JSON when asked" do
      Dir.chdir(build_dir) do
        result = run_action(apk: apk, save_uploaded_info_json: true)
        expect(JSON.parse(File.read("pgyer-fastlane-uploaded-app-info.json"))).to eq(result)
      end
    end
  end

  describe "processing timeout" do
    before { stub_request(:post, build_info_url).to_return(json_response(processing_body)) }

    it "waits 600 seconds by default" do
      expect(error_of { run_action(apk: apk) }).to include("after 600 seconds")
      expect(fake_clock.now).to be_between(600, 606)
    end

    it "reads processing_timeout and PGYER_PROCESSING_TIMEOUT" do
      expect(error_of { run_action(apk: apk, processing_timeout: 30) }).to include("after 30 seconds")
      with_env("PGYER_PROCESSING_TIMEOUT" => "45") do
        expect(error_of { run_action(apk: apk) }).to include("after 45 seconds")
      end
    end

    it "rejects a timeout that is not positive" do
      expect { run_action(apk: apk, processing_timeout: 0) }.to raise_error(FastlaneCore::Interface::FastlaneError, /processing_timeout/)
    end
  end

  it "never prints the API key, the password or the upload credentials" do
    stub_request(:post, build_info_url).to_return(json_response(processing_body), json_response(build_info_body))
    result = run_action(apk: apk, password: password, update_description: "Notes")
    printed = output.join("\n")
    [api_key, password, security_token, signature, "5ec7e75eca1e"].each do |secret|
      expect(printed).not_to include(secret)
      expect(result.to_json).not_to include(secret)
    end
    expect(printed).to include("Download page: https://www.pgyer.com/abcd")
  end

  it "marks the API key and password as sensitive" do
    sensitive = described_class.available_options.select(&:sensitive).map(&:key)
    expect(sensitive).to contain_exactly(:api_key, :password)
  end

  it "keeps the option names and environment variables of earlier versions" do
    options = described_class.available_options.to_h { |option| [option.key, option.env_name] }
    expect(options).to include(
      api_key: "PGYER_API_KEY",
      apk: "PGYER_APK",
      ipa: "PGYER_IPA",
      hap: "PGYER_HAP",
      password: "PGYER_PASSWORD",
      update_description: "PGYER_UPDATE_DESCRIPTION",
      save_uploaded_info_json: "PGYER_SAVE_UPLOADED_INFO_JSON",
      install_type: "PGYER_INSTALL_TYPE",
      install_date: "PGYER_INSTALL_DATE",
      install_start_date: "PGYER_INSTALL_START_DATE",
      install_end_date: "PGYER_INSTALL_END_DATE",
      oversea: "PGYER_OVERSEA",
      channel: "PGYER_SPECIFIED_CHANNEL",
      doh: "PGYER_DOH"
    )
    expect(options).to include(:user_download_file_name)
  end

  it "declares faraday-multipart as a runtime dependency" do
    specification = Gem::Specification.load(File.expand_path("../fastlane-plugin-pgyer.gemspec", __dir__))
    expect(specification.runtime_dependencies.map(&:name)).to include("faraday-multipart")
  end
end
