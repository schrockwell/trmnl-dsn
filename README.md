# NASA Deep Space Network Private Plugin for TRMNL

This [TRMNL](https://usetrmnl.com/) plugin displays the current status of the [Deep Space Network](https://www.nasa.gov/directorates/somd/space-communications-navigation-program/what-is-the-deep-space-network/): its three ground-based stations in Spain, the United States, and Australia, and the spaceborne satellites with which they communicate.

Data is provided by NASA's [DSN Now](https://eyes.nasa.gov/apps/dsn-now/dsn.html).

![Preview of TRMNL dashboard](preview.png)

## Self-Hosting on Netlify

The JSON data files are publicly hosted on Netlify at https://trmnl-dsn.netlify.app/dsn.json (updating hourly), so you don't have to do these steps unless you really want to!

Create a new Netlify site with the following settings:

- **Base directory:** (empty)
- **Build command:** `bundle exec bin/generate`
- **Publish directory:** `_build`
- **Environment variables:** Add `BASE_URL` with the value of the site URL without the trailing slash, e.g. `https://[app-name].netlify.app`

After publishing, the site should be live with two files published:

- https://[my-app].netlify.app/dsn.json - the data to be polled by the private plugin

To keep the JSON data up-to-date, you will need to set up a cron job that periodically calls the [build hook](https://docs.netlify.com/configure-builds/build-hooks/) for the site – ideally the same as the plugin's polling interval.
