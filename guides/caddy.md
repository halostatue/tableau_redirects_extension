# Using Redirects with Caddy

Caddy can use the JSON output from TableauRedirectsExtension to configure
redirects.

## JSON Format

The `redirects.json` file has the following structure:

```json
{
  "$schema": "https://raw.githubusercontent.com/halostatue/tableau_redirects_extension/main/priv/redirects.schema.json",
  "permanent_redirects": [
    {
      "from": ["/old", "/old/", "/old/index.html"],
      "type": "path",
      "to": "/new/",
      "target_type": "internal"
    },
    {
      "from": ["/moved", "/moved/", "/moved/index.html"],
      "type": "path",
      "to": "/current/",
      "target_type": "internal"
    },
    {
      "from": ["/old-post.html"],
      "type": "file",
      "to": "/posts/new-post/",
      "target_type": "internal"
    }
  ]
}
```

Fields:

- **from:** array of URL paths that should redirect.
- **type:** `"path"` = directory-like (consumers treat matches as directory
  root); `"file"` = exact file match.
- **to:** destination URI.
- **target_type:** `"internal"` = same-site path; `"external"` = full URL.

Directory-style entries should include the variants: bare, trailing-slash, and
index.html. File entries should list the exact path.

A JSON schema is available at `priv/redirects.schema.json` for validation and
editor support.

## Manual Configuration

Convert the `redirects.json` file to Caddy `redir` directives:

```caddyfile
example.com {
    redir /old/ /new/ permanent
    redir /moved/ /current/ permanent
    redir /external/ https://example.com/page permanent

    # ... rest of your config
}
```

## Automatic Generation with Caddy JSON Config

Caddy's native JSON configuration format makes it easier to generate config
programmatically. Using the `redir` handler is more concise than
`static_response`.

Grouped-route generator (one route per logical redirect):

```bash
#!/bin/bash
# generate-caddy-redirects.sh

JSON_FILE="_site/redirects.json"

jq '{
  apps: {
    http: {
      servers: {
        srv0: {
          routes: [
            (.permanent_redirects[] |
              {
                match: [{ path: .from }],
                handle: [{
                  handler: "redir",
                  to: .to,
                  status_code: 301
                }]
              }
            )
          ]
        }
      }
    }
  }
}' "$JSON_FILE" > caddy-redirects.json || { echo "Invalid JSON"; exit 1; }
```

Validate before running:

```bash
caddy adapt --config caddy-redirects.json
```

Load the generated config:

```bash
caddy run --config caddy-redirects.json
```

Note: This generates only redirect routes. For a complete site, append a
catch-all route that serves your content or proxies to your application.

## Using `Caddyfile` with Templates

Generate a `Caddyfile` snippet from the JSON:

```bash
#!/bin/bash
# generate-caddyfile-redirects.sh

JSON_FILE="_site/redirects.json"
OUTPUT_FILE="redirects.caddyfile"

# Generate entries for all path variants; quote values to be safe
jq -r '.permanent_redirects[] |
    .to as $to |
    .from[] |
    "    redir \"" + . + "\" \"" + $to + "\" permanent"' "$JSON_FILE" > "$OUTPUT_FILE"
```

Then import it in your main `Caddyfile`:

```caddyfile
example.com {
    import redirects.caddyfile

    # ... rest of your config
}
```

## Notes

- Caddy automatically reloads configuration when files change (with
  `caddy reload`).
- The `permanent` keyword generates a 301 redirect.
- Caddy's JSON config is more flexible for programmatic generation.
- External URLs (starting with `http://` or `https://`) work seamlessly.
- The `redir` handler automatically handles both relative and absolute URLs.
- Query strings are preserved by default in redirects.
- Path matching is exact by default in JSON `match.path`; include wild card
  suffixes (e.g., `"/old*"`) for prefix matching. `Caddyfile` `redir` can be
  used with `*` for prefix behavior (e.g., `redir /old* /new permanent`).
- The generation scripts use the `from` array to create entries for all path
  variations.
- The generated JSON only includes redirect routes; add a catch-all route for
  serving content.
- Use `caddy adapt` to validate JSON configuration before running.
- Escape or quote paths containing spaces or special characters when generating
  `Caddyfile` snippets.
- For large numbers of redirects, consider a dedicated redirects server or other
  approaches to avoid performance issues with tens of thousands of routes.
- Add error handling to generation scripts to catch malformed JSON.
