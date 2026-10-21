# pgyer plugin

[![fastlane Plugin Badge](https://rawcdn.githack.com/fastlane/fastlane/master/fastlane/assets/plugin-badge.svg)](https://rubygems.org/gems/fastlane-plugin-pgyer)

Upload `.ipa`, `.apk` and HarmonyOS `.hap` builds to [PGYER](https://www.pgyer.com) from your [fastlane](https://github.com/fastlane/fastlane) lanes.

## Getting Started

```bash
fastlane add_plugin pgyer
```

Get your API key at <https://www.pgyer.com/account/api> and make it available as the `PGYER_API_KEY` environment variable (for example as a CI secret), so it stays out of your Fastfile:

```bash
export PGYER_API_KEY=your_api_key
```

You can also pass it as `pgyer(api_key: ...)`.

## Examples

Android, uploading the APK built by `gradle` in the same lane:

```ruby
lane :beta do
  gradle(task: "assembleRelease")
  pgyer(update_description: "Fixed the login crash")
end
```

iOS, uploading the IPA built by `gym`, protected with an install password:

```ruby
lane :beta do
  gym(export_method: "ad-hoc")
  pgyer(password: "123456", update_description: "Fixed the login crash")
end
```

HarmonyOS, uploading a signed `.hap` (build it first, for example with `hvigorw assembleHap`):

```ruby
lane :beta_harmony do
  pgyer(hap: "entry/build/default/outputs/default/entry-default-signed.hap", update_description: "Fixed the login crash")
end
```

From the command line:

```bash
fastlane run pgyer hap:entry/build/default/outputs/default/entry-default-signed.hap
```

## Options

| Option | Environment variable | Description |
| --- | --- | --- |
| `api_key` | `PGYER_API_KEY` | **Required.** API key of your PGYER account |
| `apk`, `ipa`, `hap` | `PGYER_APK`, `PGYER_IPA`, `PGYER_HAP` | File to upload; set at most one. Without one, the output of `gym`, `gradle` or hvigor in the same lane is used (checked in that order: ipa, apk, hap). The type comes from the file extension; `~` is expanded |
| `update_description` | `PGYER_UPDATE_DESCRIPTION` | Release notes of this version |
| `description` | `PGYER_DESCRIPTION` | App description |
| `install_type` | `PGYER_INSTALL_TYPE` | `1` public, `2` password, `3` invitation only. Unset keeps the setting of the previous version, or uses `2` when `password` is set |
| `password` | `PGYER_PASSWORD` | Install password |
| `install_date` | `PGYER_INSTALL_DATE` | `1` installable between the two dates below, `2` no time limit. Unset keeps the previous setting, or uses `1` when both dates are set |
| `install_start_date`, `install_end_date` | `PGYER_INSTALL_START_DATE`, `PGYER_INSTALL_END_DATE` | Install period, such as `2026-01-01`. Set both or neither |
| `channel` | `PGYER_SPECIFIED_CHANNEL` | Short link of one existing download channel to update, such as `ABCD` |
| `user_download_file_name` | `PGYER_USER_DOWNLOAD_FILE_NAME` (`USER_DOWNLOAD_FILE_NAME` still works) | File name testers download, such as `demo.apk`. Plain ASCII only. Defaults to the name of the uploaded file |
| `oversea` | `PGYER_OVERSEA` | Upload storage: `true` overseas, `false` mainland China. Unset: chosen by your IP address. `1`, `2` and `0` (unset) still work |
| `processing_timeout` | `PGYER_PROCESSING_TIMEOUT` | Seconds to wait for PGYER to process the build after the upload. Default `600` |
| `save_uploaded_info_json` | `PGYER_SAVE_UPLOADED_INFO_JSON` | `true` also writes the result to `pgyer-fastlane-uploaded-app-info.json`. Default `false` |
| `doh` | `PGYER_DOH` | `true` looks up the PGYER API servers with DNS over HTTPS (Alibaba Cloud public DNS) instead of the system DNS. Certificates are still verified. Needs Ruby 2.7 or later. Default `false` |

Run `fastlane action pgyer` to see them in your terminal.

## Outputs

`pgyer` returns a Hash with the build information from PGYER's [buildInfo API](https://www.pgyer.com/doc/view/api_upload) (`buildKey`, `buildName`, `buildVersion`, `buildVersionNo`, `buildShortcutUrl`, `buildQRCodeURL`, ...) plus:

| Key | Value |
| --- | --- |
| `appPgyerURL` | Download page, such as `https://www.pgyer.com/abcd` |
| `appBuildURL` | Page of this exact build, `https://www.pgyer.com/<buildKey>` |
| `appQRCodeURL` | QR code image of the download page (same as `buildQRCodeURL`) |
| `fastlaneAddedWholeVisitUrl` | Same as `appPgyerURL`, kept for earlier versions |

The same values are stored in the lane context:

| `lane_context` key | Value |
| --- | --- |
| `SharedValues::PGYER_OUTPUT` | The Hash above |
| `SharedValues::PGYER_DOWNLOAD_URL` | Download page |
| `SharedValues::PGYER_QRCODE_URL` | QR code image URL |

```ruby
lane :beta do
  gym(export_method: "ad-hoc")
  result = pgyer(update_description: "Fixed the login crash")
  slack(message: "New beta: #{result['appPgyerURL']}")
end
```

## Troubleshooting

- **`Error loading plugin 'fastlane-plugin-pgyer'` / `Unable to activate faraday_middleware` / "No actions found"**: plugin 0.3.x needs Faraday 1 and does not load on fastlane 2.238.0 or later. Upgrade the plugin with `bundle update fastlane-plugin-pgyer` (or `fastlane update_plugins`), and make sure `fastlane/Pluginfile` does not pin an old version.
- **API errors** (wrong API key, sub-account key, missing real-name verification, uploads disabled, storage full) are printed with the PGYER error code and a hint on how to fix them.
- **`PGYER is still processing the build after 600 seconds`**: the upload finished, so the build may still appear in your app list. Raise `processing_timeout` for very large builds.
- **`None of the PGYER API servers could be reached`**: the plugin tries `www.pgyer.com`, `www.xcxwo.com` and `www.pgyerapp.com` in turn. Check your network and proxy (`HTTPS_PROXY` is honoured), or try `doh: true` if your DNS blocks these domains.
- **The wrong file was uploaded**: pass the file explicitly with `apk`, `ipa` or `hap`.

See also the fastlane [Plugins Troubleshooting](https://docs.fastlane.tools/plugins/plugins-troubleshooting/) guide.

## Changelog

### 0.5.0

- An `apk`, `ipa` or `hap` option now always wins over builds in the lane context, and the build type comes from the file extension. `~` in paths is expanded.
- `install_type` is only sent when you set it. Earlier versions sent `1` (public) on every upload without it, which made password-protected apps public.
- Waiting for PGYER is limited by `processing_timeout` (default 600 seconds) and survives short network errors.
- `oversea` accepts `true`/`false` and works from `PGYER_OVERSEA`.
- The fallback servers are only tried on network errors; API errors stop at once and include a hint.
- Request parameters and credentials are no longer printed, and `doh` mode no longer turns off TLS certificate verification.
- The name of the uploaded file is sent as the download file name unless `user_download_file_name` is set.
- New: `description` and `processing_timeout` options, `PGYER_OUTPUT`, `PGYER_DOWNLOAD_URL` and `PGYER_QRCODE_URL` outputs, `PGYER_USER_DOWNLOAD_FILE_NAME`.

## Development

```bash
bundle install
bundle exec rake   # specs and RuboCop
```

Issues and pull requests are welcome at <https://github.com/PGYER/fastlane-plugin-pgyer>.
