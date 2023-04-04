# pgyer plugin

[![fastlane Plugin Badge](https://rawcdn.githack.com/fastlane/fastlane/master/fastlane/assets/plugin-badge.svg)](https://rubygems.org/gems/fastlane-plugin-pgyer)

## Getting Started

This project is a [fastlane](https://github.com/fastlane/fastlane) plugin. To get started with `fastlane-plugin-pgyer`, add it to your project by running:

```bash
fastlane add_plugin pgyer
```

## About pgyer

This pluginin allow you distribute app automatically to [pgyer beta testing service](https://www.pgyer.com) in fastlane workflow.

## How to update pgyer plugin to the latest version

**Due to the adjustment of the API interface, please ensure that the plugin version is at least `0.2.4`**

Plan A: update all plguins (Recommended)


```bash
fastlane update_plugins
```

Plan B: update pgyer plugin only

modify `fastlane/Pluginfile`, update the following line:

```ruby
gem 'fastlane-plugin-pgyer', ">= 0.2.4" # ensure plugin version >= 0.2.4
```

and run `bundle install` at the root of your fastlane project to update gemfile.lock

## Plugin avaliable options

please visit [https://github.com/shishirui/fastlane-plugin-pgyer/blob/master/lib/fastlane/plugin/pgyer/actions/pgyer_action.rb#L135-L205](https://github.com/shishirui/fastlane-plugin-pgyer/blob/master/lib/fastlane/plugin/pgyer/actions/pgyer_action.rb#L135-L205) to know the options.


## Example

Check out the [example `Fastfile`](fastlane/Fastfile) to see how to use this plugin. Try it by cloning the repo, running `fastlane install_plugins` and `bundle exec fastlane test`.

Just specify the `api_key` associated with your pgyer account.

```
lane :beta do
  gym
  pgyer(api_key: "7f15xxxxxxxxxxxxxxxxxx141")
end
```

You can also set a password to protect the App from being downloaded publicly:

```
lane :beta do
  gym
  pgyer(api_key: "7f15xxxxxxxxxxxxxxxxxx141", password: "123456", install_type: "2")
end
```

Set a version update description for App:

```
lane :beta do
  gym
  pgyer(api_key: "7f15xxxxxxxxxxxxxxxxxx141", update_description: "update by fastlane")
end
```


If the upload is successful, you will get information about the app after it is uploaded, which is returned from the API interface app/buildinfo . You can pass it to other plugins, or export it to the terminal for use by other scripts:

```ruby
lane :beta do
  gym
  answer = pgyer(api_key: "xxxxxx")
  puts answer
  # terminal outputs like this if uploaded successfully
  # {"buildKey"=>"xxxx", "buildType"=>"2", "buildIsFirst"=>"0", "buildIsLastest"=>"1", "buildFileKey"=>"xxx.apk", "buildFileName"=>"", "buildFileSize"=>"111111", "buildName"=>"testApk", "buildVersion"=>"0.11.0", "buildVersionNo"=>"13", "buildBuildVersion"=>"10", "buildIdentifier"=>"com.pgyer.testapk", "buildIcon"=>"xxxx", "buildDescription"=>"", "buildUpdateDescription"=>"", "buildScreenshots"=>"", "buildShortcutUrl"=>"xxxxxxx", "buildCreated"=>"2023-04-04 11:33:24", "buildUpdated"=>"2023-04-04 11:33:24", "buildQRCodeURL"=>"https://www.pgyer.com/app/qrcodeHistory/xxxxxx", "fastlaneAddedWholeVisitUrl"=>"https://www.pgyer.com/xxxxxx"}
  puts "url = #{answer["fastlaneAddedWholeVisitUrl"]}"

  # terminal outputs like this if uploaded successfully
  # url = https://www.pgyer.com/xxxxxx

  # More information please visit https://www.pgyer.com/doc/view/api#fastUploadApp to check API "https://www.pgyer.com/apiv2/app/buildInfo"

end
```




And more params

```

password: Set password to protect app.

update_description: Set update description for app.

install_type: Set install type for app (1=public, 2=password, 3=invite), Please set as a string.

install_date: Set install type for app (1=Set valid time, 2=Long-term effective, other=Do not modify the last setting), Please set as a string.

install_start_date: The value is a string of characters, for example, 2018-01-01.

install_end_date: The value is a string of characters, such as 2018-12-31.

channel: Need to update the specified channel of the download short link, can specify only one channel, string type, such as: ABCD. Specifies channel uploads. If you do not have one, do not use this parameter.

save_uploaded_info_json: (true or false, default to false) Whether to save the information returned by the API interface to a json file.

```
## Run tests for this plugin

To run both the tests, and code style validation, run

```
rake
```

To automatically fix many of the styling issues, use
```
rubocop -a
```

## Issues and Feedback

For any other issues and feedback about this plugin, please submit it to this repository.

## Troubleshooting

If you have trouble using plugins, check out the [Plugins Troubleshooting](https://docs.fastlane.tools/plugins/plugins-troubleshooting/) guide.

## Using `fastlane` Plugins

For more information about how the `fastlane` plugin system works, check out the [Plugins documentation](https://docs.fastlane.tools/plugins/create-plugin/).

## About `fastlane`

`fastlane` is the easiest way to automate beta deployments and releases for your iOS and Android apps. To learn more, check out [fastlane.tools](https://fastlane.tools).
