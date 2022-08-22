# pgyer plugin

[![fastlane Plugin Badge](https://rawcdn.githack.com/fastlane/fastlane/master/fastlane/assets/plugin-badge.svg)](https://rubygems.org/gems/fastlane-plugin-pgyer)

## Getting Started

This project is a [fastlane](https://github.com/fastlane/fastlane) plugin. To get started with `fastlane-plugin-pgyer`, add it to your project by running:

```bash
fastlane add_plugin pgyer
```

## About pgyer

This pluginin allow you distribute app automatically to [pgyer beta testing service](https://www.pgyer.com) in fastlane workflow.

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

And more params

```

password: Set password to protect app.

update_description: Set update description for app.

install_type: Set install type for app (1=public, 2=password, 3=invite), Please set as a string.

install_date: Set install type for app (1=Set valid time, 2=Long-term effective, other=Do not modify the last setting), Please set as a string.

install_start_date: The value is a string of characters, for example, 2018-01-01.

install_end_date: The value is a string of characters, such as 2018-12-31.

channel: Need to update the specified channel of the download short link, can specify only one channel, string type, such as: ABCD. Specifies channel uploads. If you do not have one, do not use this parameter.

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
