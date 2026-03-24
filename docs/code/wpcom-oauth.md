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
