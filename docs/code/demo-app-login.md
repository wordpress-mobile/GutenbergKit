# Signing In to the Demo Apps

`make login-ios-app` and `make login-android-app` add WordPress sites to a demo app in one command, using credentials stored on your machine. There is no login screen and nothing to tap. Build and install the app first, e.g. from Xcode or Android Studio.

```bash
make login-ios-app                             # iOS demo app, every site you have credentials for
make login-android-app                         # Android demo app, the connected emulator or device
make login-ios-app SITE=example.com            # only this site from ~/.config/wp/sites
make login-ios-app SITE=example.wordpress.com  # only this WordPress.com site
make login-ios-app DEVICE=<id>                 # a specific simulator UDID or adb serial
```

Both targets forward to `bin/demo-app-login.sh`, which takes the same options as flags — `--platform`, `--site`, `--device`. When more than one simulator or device is running, it prompts you to choose.

The app has to be a build that includes these targets. An older one ignores the accounts it is launched with, so if no sites appear, rebuild and reinstall it.

Without `SITE`, every site in `~/.config/wp/sites` is added, along with the WordPress.com account's primary site when there is a token. They all reach the app in a single launch. A site that can't be signed in to is reported and left out, and the command then exits with an error after adding the rest.

`SITE` adds one site instead. It is looked up in `~/.config/wp/sites` first, and a site that isn't listed there is taken to be a WordPress.com site.

Credentials are deliberately never a flag or a `make` variable — anything passed as an argument would be saved in your shell history.

## Self-Hosted Sites

List each site in `~/.config/wp/sites`, one per line, as a URL, a username and an [application password](https://make.wordpress.org/core/2020/11/05/application-passwords-integration-guide/):

```
# <url> <username> <application password>
https://example.com          admin   abcd EFGH 1234 ijkl MNOP 5678
https://staging.example.com  editor  qrst UVWX 9012 yzab CDEF 3456
```

The password is the rest of the line, so it can be pasted with its spaces. Blank lines and lines starting with `#` are skipped, and `$XDG_CONFIG_HOME` is used in place of `~/.config` when it is set. The file holds passwords, so keep it private:

```bash
chmod 600 ~/.config/wp/sites
```

For each site, the script finds its REST API from the `Link` header of its home page, checks that the site accepts the username and password, and passes all of that to the app.

Those requests are made from your computer, so the site has to answer at the same URL from the device as well. A site on `localhost` doesn't from an Android emulator unless the port is forwarded with `adb reverse tcp:<port> tcp:<port>`. For the wp-env site, the app's built-in **Local WordPress** entry already handles this — see [Local WordPress](./local-wordpress.md).

## WordPress.com Sites

A WordPress.com bearer token stands in for the OAuth application described in [WordPress.com OAuth](./wpcom-oauth.md). The token is resolved from, in order:

1. the `WPCOM_TOKEN` environment variable;
2. a `~/.wpcom-token` file — the same file `make example-app-login` reads in wordpress-rs.

The demo apps keep one account per site, so the script looks up the site's ID and address from the WordPress.com REST API and passes them to the app along with the token.

Once the app holds a WordPress.com token, **Add WordPress Site** reuses it. Entering another WordPress.com site that the token's user can edit adds it straight away, with no OAuth application and no login screen. Any other WordPress.com site still goes through OAuth.

## Launching by Hand

The app takes the accounts as one JSON array, in an `accounts` launch argument. It stores each one at launch, replacing any account it already holds for that site, so running the command again picks up new credentials.

```json
[
	{
		"siteUrl": "https://example.com",
		"username": "admin",
		"password": "abcd EFGH 1234 ijkl MNOP 5678",
		"siteApiRoot": "https://example.com/wp-json/"
	},
	{
		"wpcomToken": "<token>",
		"wpcomSiteId": 123456,
		"wpcomSiteHost": "example.wordpress.com"
	}
]
```

```bash
# iOS Simulator
xcrun simctl launch --terminate-running-process booted org.wordpress.gutenberg.development \
  -accounts '<json>'

# Android (the device shell interprets the value, so it needs its own layer of quotes)
adb shell am start -S -n com.example.gutenbergkit/.MainActivity --es accounts "'<json>'"
```

Either way, the credentials briefly appear in the process list while the launch command runs; that's inherent to passing them as launch arguments.
