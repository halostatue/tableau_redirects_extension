# TableauRedirectsExtension Usage Rules

TableauRedirectsExtension is a Tableau extension that generates redirect files
and manifests for maintaining stable URLs when content moves.

## Core Behavior

Generates two types of redirects:

1. **HTML meta-refresh redirects** - For browser-based redirects
2. **JSON manifest** - For server-side redirect configuration

Redirects can be defined globally in configuration or per-page in frontmatter.

## Configuration Format

```elixir
config :tableau, TableauRedirectsExtension,
  enabled: true,                    # optional, default: false
  html: %{
    enabled: true,                  # optional, default: true
    message: "Redirecting...",      # optional, default provided
    external_message: "Leaving..."  # optional, default: same as message
  },
  json: %{
    enabled: true                   # optional, default: true
  },
  redirects: %{
    "/old-url/" => "/new-url/",
    "/moved/" => "/current/"
  }
```

At least one output format (HTML or JSON) must be enabled.

## Redirect Sources

### Global Redirects (Configuration)

```elixir
config :tableau, TableauRedirectsExtension,
  redirects: %{
    "/old-path/" => "/new-path/",
    "/external/" => "https://example.com"
  }
```

### Content Redirects (Frontmatter)

```yaml
---
title: My Post
permalink: /posts/my-post/
redirects:
  aliases:
    - /blog/old-post
    - /old-location/post
  fragments:
    old-section: "#new-section"
    deprecated: "#updated"
---
```

**Aliases** redirect to the page's permalink. **Fragments** redirect to the
page's permalink with a fragment appended.

## Path Normalization

All redirect paths are normalized:

1. Leading `/` is added if missing
2. Trailing `/` is added for directory-style paths (no extension)
3. `/index.html` suffix is treated as directory and normalized to `/path/`
4. File extensions are preserved (`.html`, `.htm`, `.php`, `.gif`, etc.)

Examples:

- `old-url` → `/old-url/`
- `/file.html` → `/file.html`
- `/path/index.html` → `/path/`
- `no-extension` → `/no-extension/`

## Redirect Priority

When multiple redirects target the same source path:

1. **Content redirects** (frontmatter) override global redirects
2. **Existing content** prevents redirects (logged warning)
3. **Redirect loops** are rejected (logged warning)

## HTML Redirect Generation

HTML redirects are generated for:

- Directory-style paths (ending with `/`)
- HTML-like files (`.html`, `.htm`, `.php`)

HTML redirects are NOT generated for:

- Other file types (`.gif`, `.jpg`, `.pdf`, etc.) - only in JSON

### Output Locations

- **Directories**: `path/index.html`
- **HTML files**: exact path (e.g., `old-page.html`)

### HTML Format

```html
<!DOCTYPE html>
<meta charset="utf-8">
<title>Redirecting to /target/…</title>
<link rel="canonical" href="/target/">
<meta http-equiv="refresh" content="0; url=/target/">
<p>Redirecting to <a href="/target/">/target/</a>…</p>
```

External URLs include `rel="nofollow noreferrer noopener"` on links.

## JSON Manifest Generation

Generates `redirects.json` in the output directory:

```json
{
  "permanent_redirects": [
    {
      "from": ["/old", "/old/", "/old/index.html"],
      "type": "path",
      "to": "/new/",
      "target_type": "internal"
    },
    {
      "from": ["/file.html"],
      "type": "file",
      "to": "/new-file.html",
      "target_type": "internal"
    }
  ]
}
```

### JSON Fields

- **from**: Array of URL paths that should redirect (all variants)
- **type**: `"path"` for directory-style, `"file"` for files
- **to**: Target URL (absolute path or full URL)
- **target_type**: `"internal"` for same-site, `"external"` for full URLs

### Path Variants

**Directory-style paths** include three variants:

- `/path` (bare)
- `/path/` (trailing slash)
- `/path/index.html` (index file)

**File paths** include only the exact path:

- `/file.html`

Redirects are sorted by target URL for stable, git-friendly output.

## Base Path Support

For sites deployed to subdirectories (e.g., `https://example.com/blog/`):

```elixir
config :tableau, :config,
  url: "https://example.com/blog/"
```

The extension automatically prepends the base path to internal redirect targets
in HTML files:

- Redirect to `/post/` becomes `/blog/post/`
- External URLs are not modified

JSON manifest contains paths without base path - consumers should handle this.

## Restrictions

### Root Path Redirects

Redirects from `/` are rejected with error (global config) or warning (content):

```elixir
# This will fail validation
redirects: %{"/" => "/home/"}
```

```yaml
# This will be ignored with warning
redirects:
  aliases:
    - /
```

### Redirect Loops

Redirects that target another redirect source are rejected:

```elixir
# This will be rejected
redirects: %{
  "/a/" => "/b/",
  "/b/" => "/c/"  # /b/ is also a source
}
```

## JSON Schema

A JSON schema is available at `priv/redirects.schema.json` for validation and
editor support. The schema uses JSON Schema draft 2020-12.

## Common Issues

1. **Root path redirect rejected**: Cannot redirect from `/`. This would shadow
   the site's home page.

2. **Redirect loop detected**: A redirect target is also a redirect source.
   Check your redirect configuration for circular references.

3. **Content exists at path**: Cannot create redirect when actual content exists
   at that path. Content takes precedence.

4. **HTML redirect not created for file type**: Only `.html`, `.htm`, `.php`
   files and directories get HTML redirects. Other file types only appear in
   JSON manifest.

5. **Base path not applied**: HTML redirects automatically include base path for
   internal targets. JSON consumers must handle base path themselves.

## Resources

- [HexDocs](https://hexdocs.pm/tableau_redirects_extension) - Full API
  documentation
- JSON Schema: `priv/redirects.schema.json`
