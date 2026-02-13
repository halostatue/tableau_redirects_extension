# Using Redirects with nginx

The JSON output from TableauRedirectsExtension can be used to generate nginx
redirect rules.

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
- **type:** `"path"` = directory-like; `"file"` = exact file match.
- **to:** destination URI.
- **target_type:** `"internal"` = same-site path; `"external"` = full URL.

Directory-style entries include three variants (bare, trailing slash,
index.html). File entries list only the exact path. Redirects are sorted by
target for stable output.

A JSON schema is available at `priv/redirects.schema.json` for validation and
editor support.

## Manual Configuration

Convert the `redirects.json` file to nginx `map` directives:

```nginx
# In http context (e.g., /etc/nginx/conf.d/redirects.conf)
map $uri $redirect_uri {
    default "";
    /old/ /new/;
    /moved/ /current/;
    /external/ https://example.com/page;
}
```

Then use the map in your server block:

```nginx
server {
    listen 80;
    server_name example.com;

    if ($redirect_uri != "") {
        return 301 $redirect_uri$is_args$args;
    }

    # ... rest of your config
}
```

## Automatic Generation

nginx cannot directly read JSON files for configuration. Generate the map from
the JSON file during your build or deployment process.

Example script to generate nginx config from `redirects.json`:

```bash
#!/bin/bash
# generate-nginx-redirects.sh
set -euo pipefail

JSON_FILE="_site/redirects.json"
OUTPUT_FILE="nginx-redirects.conf"

# Verify JSON is valid
if ! jq -e . "$JSON_FILE" >/dev/null 2>&1; then
    echo "Error: redirects.json is not valid JSON"
    exit 1
fi

{
    echo 'map $uri $redirect_uri {'
    echo '    default "";'
    
    # Use from array to generate all path matches
    # Note: Reject entries containing control characters, newlines, or semicolons
    # before emitting map lines to prevent malformed nginx tokens
    jq -r '.permanent_redirects[] | 
        .to as $to | 
        .from[] | 
        "    " + . + " " + $to + ";"' "$JSON_FILE"
    
    echo '}'
} > "$OUTPUT_FILE"

# Validate before using
nginx -t && echo "Config valid"
```

Include the generated file in your nginx http context:

```nginx
http {
    include /path/to/nginx-redirects.conf;

    server {
        listen 80;
        server_name example.com;

        location / {
            if ($redirect_uri) {
                return 301 $redirect_uri$is_args$args;
            }

            # Normal site handling
            try_files $uri $uri/ =404;
        }
    }
}
```

Reload nginx after regenerating:

```bash
nginx -s reload
```

## Notes

- nginx `map` directives are evaluated at configuration load time, not runtime
- Changes to `redirects.json` require regenerating the config and reloading
  nginx
- Use `$uri` (not `$request_uri`) for normalized path matching without query
  strings
- The `$is_args$args` suffix preserves original query strings in redirects
- The `map` directive must be in the `http` context, not inside `server` blocks
- Always validate generated config with `nginx -t` before reloading
- The `if` directive should be the only statement in the `location` block to
  avoid unexpected behavior
- All paths are normalized with leading slashes; directory paths include
  trailing slashes while file paths preserve their extensions
- The generation script uses the `from` array to create exact-match entries for
  all path variations
- For large numbers of redirects (thousands+), consider performance testing
- Add error handling to generation scripts to catch malformed JSON
- nginx map syntax: keys and values are space-separated and terminated with
  semicolons. The generator produces normalized URL paths suitable for use with
  nginx `$uri`. When targeting nginx, ensure generated map keys are in the same
  percent-encoded form nginx uses for `$uri` (do not blindly decode/re-encode).
  If you manually edit the JSON or use it with nginx, ensure paths contain only
  URL-safe characters. Map quoting and validation are nginx-specific concerns;
  this JSON format is platform-agnostic and can be used with Caddy, Apache, or
  custom Plug implementations.
