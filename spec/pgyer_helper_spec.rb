describe Fastlane::Helper::PgyerHelper do
  let(:helper) { described_class }

  describe ".build_type" do
    it "detects the type from the file extension" do
      expect(helper.build_type("/tmp/app-release.apk")).to eq("android")
      expect(helper.build_type("/tmp/App.ipa")).to eq("ios")
      expect(helper.build_type("/tmp/entry-default-signed.hap")).to eq("harmony")
    end

    it "ignores the case of the extension" do
      expect(helper.build_type("/tmp/APP.APK")).to eq("android")
    end

    it "rejects other files with a clear error" do
      expect { helper.build_type("/tmp/app.aab") }.to raise_error(FastlaneCore::Interface::FastlaneError, /app\.aab.*\.apk, \.ipa and \.hap/)
      expect { helper.build_type("/tmp/App.app.zip") }.to raise_error(FastlaneCore::Interface::FastlaneError)
    end
  end

  describe ".install_type" do
    it "accepts strings and numbers" do
      expect(helper.install_type("2")).to eq("2")
      expect(helper.install_type(3)).to eq("3")
      expect(helper.install_type(" 1 ")).to eq("1")
    end

    it "treats an empty value as unset" do
      expect(helper.install_type(nil)).to be_nil
      expect(helper.install_type("")).to be_nil
    end

    it "rejects unknown install types" do
      expect { helper.install_type("4") }.to raise_error(FastlaneCore::Interface::FastlaneError, /install_type/)
    end
  end

  describe ".oversea" do
    {
      true => "1",
      "true" => "1",
      "TRUE" => "1",
      1 => "1",
      "1" => "1",
      false => "2",
      "false" => "2",
      2 => "2",
      "2" => "2",
      0 => nil,
      "0" => nil,
      "" => nil,
      nil => nil,
    }.each do |value, expected|
      it "maps #{value.inspect} to #{expected.inspect}" do
        expect(helper.oversea(value)).to eq(expected)
      end
    end

    it "rejects other values" do
      expect { helper.oversea("3") }.to raise_error(FastlaneCore::Interface::FastlaneError, /oversea/)
      expect { helper.oversea("cn") }.to raise_error(FastlaneCore::Interface::FastlaneError, /oversea/)
    end
  end

  describe ".token_form" do
    before { capture_ui }

    def form(values = {})
      helper.token_form({ api_key: "key" }.merge(values), "android")
    end

    it "sends only the API key and build type when nothing else is set" do
      expect(form).to eq("_api_key" => "key", "buildType" => "android")
    end

    it "does not send an install type unless one is set, so PGYER keeps the previous setting" do
      expect(form(update_description: "notes")).not_to include("buildInstallType")
    end

    it "sends the install type that is set" do
      expect(form(install_type: "1")).to include("buildInstallType" => "1")
      expect(form(install_type: 3)).to include("buildInstallType" => "3")
    end

    it "uses install type 2 for a password without an install type" do
      expect(form(password: "123456")).to include("buildInstallType" => "2", "buildPassword" => "123456")
    end

    it "keeps an install type that is set together with a password" do
      expect(form(password: "123456", install_type: "3")).to include("buildInstallType" => "3", "buildPassword" => "123456")
    end

    it "sends the optional texts that are set" do
      result = form(description: "About the app", update_description: "Fixed a crash", channel: "ABCD")
      expect(result).to include("buildDescription" => "About the app", "buildUpdateDescription" => "Fixed a crash", "buildChannelShortcut" => "ABCD")
    end

    it "omits blank optional texts" do
      result = form(description: "", update_description: "  ", channel: "", password: "")
      expect(result).to eq("_api_key" => "key", "buildType" => "android")
    end

    it "sends the install period only when both dates are set" do
      expect(form(install_start_date: "2026-01-01", install_end_date: "2026-02-01")).to include(
        "buildInstallDate" => "1",
        "buildInstallStartDate" => "2026-01-01",
        "buildInstallEndDate" => "2026-02-01"
      )
      expect(form(install_date: "1", install_start_date: "2026-01-01", install_end_date: "2026-02-01")).to include("buildInstallDate" => "1")
    end

    it "rejects an incomplete install period" do
      expect { form(install_start_date: "2026-01-01") }.to raise_error(FastlaneCore::Interface::FastlaneError, /both install_start_date and install_end_date/)
      expect { form(install_date: "1") }.to raise_error(FastlaneCore::Interface::FastlaneError, /install_date 1 needs/)
    end

    it "sends install_date 2 for no time limit" do
      expect(form(install_date: 2)).to include("buildInstallDate" => "2")
      expect(form(install_date: "2")).not_to include("buildInstallStartDate")
    end

    it "keeps the previous install period for other install_date values" do
      expect(form(install_date: "0", install_start_date: "2026-01-01", install_end_date: "2026-02-01")).not_to include("buildInstallDate")
    end

    it "maps oversea and omits it when unset" do
      expect(form(oversea: true)).to include("oversea" => "1")
      expect(form(oversea: false)).to include("oversea" => "2")
      expect(form(oversea: 0)).not_to include("oversea")
      expect(form).not_to include("oversea")
    end
  end

  describe ".download_file_name" do
    before { capture_ui }

    it "defaults to the name of the uploaded file" do
      expect(helper.download_file_name(nil, "/tmp/out/app-release.apk")).to eq("app-release.apk")
    end

    it "uses the configured name" do
      expect(helper.download_file_name("demo.apk", "/tmp/out/app-release.apk")).to eq("demo.apk")
    end

    it "skips names that are not plain ASCII" do
      expect(helper.download_file_name("演示.apk", "/tmp/out/app-release.apk")).to be_nil
      expect(helper.download_file_name(nil, "/tmp/out/演示.apk")).to be_nil
    end
  end

  describe ".hint" do
    it "explains common error codes" do
      expect(helper.hint(1001)).to include("https://www.pgyer.com/account/api")
      expect(helper.hint(1002)).to include("API key")
      expect(helper.hint(1003)).to include("Sub-accounts")
      expect(helper.hint(1019)).to include("https://www.pgyer.com/account/certification")
      expect(helper.hint(1020)).to include("customer service")
      expect(helper.hint(1022)).to include("storage is full")
      expect(helper.hint(1216)).to be_nil
    end
  end

  describe ".add_links" do
    it "adds the download page and QR code URLs" do
      result = helper.add_links("buildKey" => "k1", "buildShortcutUrl" => "abcd", "buildQRCodeURL" => "https://pgyer.com/app/qrcode/abcd")
      expect(result).to include(
        "appPgyerURL" => "https://www.pgyer.com/abcd",
        "appBuildURL" => "https://www.pgyer.com/k1",
        "appQRCodeURL" => "https://pgyer.com/app/qrcode/abcd",
        "fastlaneAddedWholeVisitUrl" => "https://www.pgyer.com/abcd"
      )
    end

    it "falls back to the build key without a short URL" do
      expect(helper.add_links("buildKey" => "k1", "buildShortcutUrl" => "")["appPgyerURL"]).to eq("https://www.pgyer.com/k1")
    end
  end
end
