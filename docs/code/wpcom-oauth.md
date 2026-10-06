# WordPress.com OAuth Setup

The demo apps support connecting to WordPress.com sites via OAuth. This requires creating a WordPress.com application and configuring the project with its credentials.

## Creating a WordPress.com Application

1. Go to the [WordPress.com Developer Apps](https://developer.wordpress.com/apps/) page
2. Click **Create New Application**
3. Fill in the required fields:
    - **Redirect URL**: Set to `gutenbergkit://oauth-callback`
    - Other fields can be set as needed for your use case
4. Note the **Client ID** and **Client Secret** from the created application

For more details on the OAuth flow, see the [WordPress.com OAuth2 documentation](https://developer.wordpress.com/docs/api/oauth2/).

## Configuring Credentials

Copy the example credentials file and fill in your application details:

```bash
cp wp_com_oauth_credentials.json.example wp_com_oauth_credentials.json
```

Edit `wp_com_oauth_credentials.json` with your application's Client ID and Client Secret:

```json
{
	"client_id": 12345,
	"client_secret": "your-client-secret"
}
```

This file is gitignored to prevent credentials from being committed.

## Signing In With a Bearer Token

If you already have a WordPress.com bearer token, you can skip the OAuth application entirely. `make login-ios-app` and `make login-android-app` add a WordPress.com site to a demo app in one command, with no taps. Build and install the app first, e.g. from Xcode or Android Studio.

```bash
make login-ios-app                             # iOS demo app, the booted Simulator
make login-android-app                         # Android demo app, the connected emulator or device
make login-ios-app SITE=example.wordpress.com  # a site other than the account's primary one
make login-ios-app DEVICE=<id>                 # a specific simulator UDID or adb serial
```

Both targets forward to `bin/demo-app-login.sh`, which takes the same options as flags — `--platform`, `--site`, `--device`. When more than one simulator or device is running, it prompts you to choose.

The token is resolved from, in order:

1. the `WPCOM_TOKEN` environment variable;
2. a `~/.wpcom-token` file — the same file `make example-app-login` reads in wordpress-rs.

There's deliberately no token flag or `make` variable — a token passed as an argument would be saved in your shell history.

The demo apps keep one account per site, so the script looks up the site's ID and address from the WordPress.com REST API and passes them to the app along with the token. The app stores them as an account at launch, replacing any account it already holds for that site, so running the command again picks up a new token.

To launch with a token by hand:

```bash
# iOS Simulator
xcrun simctl launch --terminate-running-process booted org.wordpress.gutenberg.development \
  -wpcom-token <token> -wpcom-site-id <site-id> -wpcom-site-host <site-domain>

# Android (single-quote the token — the device shell interprets it)
adb shell am start -S -n com.example.gutenbergkit/.MainActivity \
  --es wpcom-token "'<token>'" --es wpcom-site-id <site-id> --es wpcom-site-host <site-domain>
```

Either way, the token briefly appears in the process list while the launch command runs; that's inherent to passing it as a launch argument.
