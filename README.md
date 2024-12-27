# Deep Space Network Private Plugin for TRMNL

## Hosting on Netlify

The JSON data file is publicly hosted on Netlify at https://trmnl-dsn.netlify.app/dsn.json so you don't have to do these steps unless you really want to!

Create a new Netlify site with the following settings:

- **Base directory:** (empty)
- **Build command:** `bundle exec ./generate.rb`
- **Publish directory:** `_site`
- **Environment variables:** Add `BASE_URL` with the value of the site URL without the trailing slash, e.g. `https://[app-name].netlify.app`

After publishing, the site should be live with two files published:

- https://[my-app].netlify.app/ - an HTML preview of the dashboard
- https://[my-app].netlify.app/dsn.json - the data to be polled by the private plugin

To keep the JSON data up-to-date, you will need to set up a cron job that periodically calls the [build hook](https://docs.netlify.com/configure-builds/build-hooks/) for the site – ideally the same as the plugin's polling interval.
