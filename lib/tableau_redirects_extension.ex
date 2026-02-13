defmodule TableauRedirectsExtension do
  @moduledoc """
  Tableau extension that generates redirect files for moved or migrated content.

  ## Overview

  This extension creates redirect files to maintain URL stability when content moves. It
  supports creating HTML files with `<meta http-equiv="refresh">` tags and a JSON manifest
  that can be used to create server-side redirect configurations (nginx, Apache, or Caddy
  rules, or a Plug for plug-based servers).

  Redirects can be defined globally in configuration or per-page (or post) in frontmatter.

  ## Configuration

  ```elixir
  config :tableau, TableauRedirectsExtension,
    enabled: true,
    html: [
      enabled: true,
      message: "Redirecting to {{ url }}…",
      external_message: "Redirecting to external site {{ url }}…"
    ],
    json: [enabled: true],
    redirects: %{
      "/old/url/" => "/new/url/",
      "/dropped/" => "/about/#old-content",
      "/archived/post/" => "https://archive.example.com/post/"
    }
  ```

  ### Configuration Options

  - `:enabled` (default `false`): Enable or disable the extension.

  - `:html`: Options for HTML redirect files with `<meta>` refresh tags. If `true`, the
    default HTML configuration is enabled; if `false`, the HTML configuration is disabled.

    - `:enabled` (default `true`): Generate HTML redirect files.

    - `:message` (required): Message shown during redirect (supports `{{ url }}`
      placeholder).

    - `:external_message` (optional): Message for external redirects. If `nil`, uses the
      value of `:message`.

  - `:json`: JSON manifest generation options. If `true`, the default JSON configuration
      is enabled; if `false`, the JSON configuration is disabled.

    - `:enabled` (default `true`): Generate `redirects.json` manifest.

  - `:redirects`: Global redirect map (`%{from => to}`)
    - Keys are normalized to have leading/trailing slashes
    - Values can be internal paths or external URLs
    - Content-level redirects take precedence over global redirects

  ### Shorthand Configuration

  Boolean values expand to defaults:

  ```elixir
  config :tableau, TableauRedirectsExtension,
    enabled: true,
    html: true,    # Uses default html config
    json: true     # Uses default json config
  ```

  ## Frontmatter Redirects

  Define redirects in page frontmatter using `aliases` and `fragments`:

  ```yaml
  ---
  title: Understanding Elixir Protocols
  permalink: /posts/elixir-protocols/
  redirects:
    aliases:
      - /blog/2020/old-title/
      - /articles/protocols-guide/
    fragments:
      /old/section/: "#new-section"
      /guides/part-1/: "#introduction"
  ---
  ```

  ### Aliases

  Aliases redirect old URLs to the current page's permalink. Both `/blog/2020/old-title/`
  and `/articles/protocols-guide/` will redirect to `/posts/elixir-protocols/`.

  ### Fragments

  Fragments redirect old URLs to specific sections of the current page. The path
  `/old/section/` redirects to `/posts/elixir-protocols/#new-section`.

  ## Output Files

  ### HTML Redirects

  For each redirect, generates `<from>/index.html` with:

  - `<meta http-equiv="refresh">` tag
  - `<link rel="canonical">` tag
  - JavaScript fallback: `location="<target>"`
  - User-visible message with link

  Example output for `/old/` → `/new/`:

  ```html
  <!DOCTYPE html>
  <meta charset="utf-8">
  <title>Redirecting to /new/…</title>
  <link rel="canonical" href="/new/">
  <meta http-equiv="refresh" content="0; url=/new/">
  <p>Redirecting to <a href="/new/">/new/</a>…</p>
  ```

  External URLs include `rel="nofollow noreferrer noopener"` on the link.

  ### JSON Manifest

  Generates `redirects.json` in the output directory:

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

  The `from` field is always an array listing all URL paths that should redirect to
  the target. The `type` field indicates whether the redirect is for a directory-style
  path (`"path"`) or a file (`"file"`). The `target_type` field indicates whether the
  target is an internal path (`"internal"`) or an external URL (`"external"`).
  Directory-style paths include three variants (`/path`, `/path/`, `/path/index.html`),
  while file paths include only the exact path.

  Redirects are sorted by target URL for stable, git-friendly output.

  A JSON schema is available at `priv/redirects.schema.json` for validation and editor
  support.

  Use this manifest to configure server-side redirects. See the guides for examples
  with nginx, Caddy, and Plug.

  ## Redirect Priority

  When multiple redirect sources exist:

  1. **Content redirects** (frontmatter) take precedence over global config
  2. **Existing content** prevents redirects - a warning is logged if a redirect
     source path matches an actual page permalink

  ## Path Normalization

  All redirect paths are normalized:

  - Leading slash added if missing: `old/` → `/old/`
  - Trailing slash added for internal paths: `/old` → `/old/`
  - External URLs preserve their format: `https://example.com` (no trailing slash)

  ## Examples

  ### Simple Site Migration

  ```elixir
  config :tableau, TableauRedirectsExtension,
    enabled: true,
    redirects: %{
      "/blog/" => "/posts/",
      "/about-us/" => "/about/",
      "/contact-form/" => "https://example.com/contact"
    }
  ```

  ### Per-Post Redirects with Aliases and Fragments

  ```yaml
  ---
  title: Complete Guide
  permalink: /guides/complete/
  redirects:
    aliases:
      - /blog/2020/old-guide/
      - /articles/guide/
    fragments:
      /guides/part-1/: "#introduction"
      /guides/part-2/: "#advanced"
      /guides/part-3/: "#examples"
  ---
  ```
  """

  use Tableau.Extension, key: :redirects, priority: 900

  require Logger

  @default %{
    enabled: false,
    html: %{
      enabled: true,
      message: "Redirecting to {{ url }}…",
      external_message: "Redirecting to external site {{ url }}…"
    },
    json: %{enabled: true},
    redirects: %{}
  }

  @impl Tableau.Extension
  def config(config) do
    {:ok, config} = normalize_config(config)

    merged =
      Map.merge(@default, config, fn
        _key, left, right when is_map(left) and is_map(right) -> Map.merge(left, right)
        _key, _left, right -> right
      end)

    validate_config(merged)
  end

  @impl Tableau.Extension
  def post_write(token) do
    config = token.extensions.redirects.config
    redirects = build_redirects(token, config)

    if config.html.enabled do
      write_html_redirects(token, redirects, config)
    end

    if config.json.enabled do
      write_json_redirects(token, redirects)
    end

    {:ok, token}
  end

  # coveralls-ignore-next-line
  defp external_url?("http://" <> _), do: true
  defp external_url?("https://" <> _), do: true
  defp external_url?(_), do: false

  defp build_redirects(token, config) do
    config.redirects
    |> Enum.reduce(collect_content_redirects(token), &merge_redirect/2)
    |> reject_existing_content(token)
    |> reject_loops()
    |> Map.new()
  end

  defp reject_existing_content(redirects, token) do
    existing = MapSet.new(token.site.pages, & &1.permalink)

    Enum.reject(redirects, fn {from, _to} ->
      if MapSet.member?(existing, from) do
        Logger.warning("[TableauRedirectsExtension] Redirect ignored: content exists at #{from}")
        true
      else
        false
      end
    end)
  end

  defp reject_loops(redirects) do
    sources = MapSet.new(redirects, &elem(&1, 0))

    Enum.reject(redirects, fn {from, to} ->
      normalized_to = normalize_path(to)

      if MapSet.member?(sources, normalized_to) do
        Logger.warning(
          "[TableauRedirectsExtension] Redirect ignored: loop detected #{from} -> #{to} (#{normalized_to})"
        )

        true
      else
        false
      end
    end)
  end

  defp merge_redirect({from, _to}, acc) when is_map_key(acc, from) do
    Logger.warning(
      "[TableauRedirectsExtension] Redirect ignored: global redirect #{from} overridden by content redirect"
    )

    acc
  end

  defp merge_redirect({from, to}, acc) do
    Map.put(acc, from, to)
  end

  defp collect_content_redirects(token) do
    token.site.pages
    |> Enum.flat_map(&extract_page_redirects/1)
    |> Enum.reject(&reject_root_redirect/1)
    |> Map.new()
  end

  defp extract_page_redirects(page) do
    extract_aliases(page[:redirects], page.permalink) ++
      extract_fragments(page[:redirects], page.permalink)
  end

  defp extract_aliases(%{aliases: list}, permalink) when is_list(list) do
    Enum.map(list, &{normalize_path(&1), permalink})
  end

  defp extract_aliases(_, _), do: []

  defp extract_fragments(%{fragments: list}, permalink) when is_list(list) or is_map(list) do
    list
    |> Map.new()
    |> Enum.map(fn {from, fragment} ->
      {normalize_path(to_string(from)), permalink <> fragment}
    end)
  end

  defp extract_fragments(_, _), do: []

  defp reject_root_redirect({"/", _to}) do
    Logger.warning("[TableauRedirectsExtension] Redirect ignored: site root redirect (/) not allowed")
    true
  end

  defp reject_root_redirect(_), do: false

  defp write_html_redirects(token, redirects, config) do
    Enum.each(redirects, fn {from, to} ->
      if html_redirect_allowed?(from) do
        write_html_redirect(token, from, to, config)
      end
    end)
  end

  defp html_redirect_allowed?(path) do
    String.ends_with?(path, "/") or String.match?(path, ~r/\.(html?|php)$/i)
  end

  defp write_html_redirect(token, from, to, config) do
    output_path =
      if directory_path?(from) do
        Path.join([token.site.config.out_dir, from, "index.html"])
      else
        Path.join(token.site.config.out_dir, from)
      end

    File.mkdir_p!(Path.dirname(output_path))

    target = build_target(to, token.site.config.base_path)
    {message, link} = build_message_and_link(to, target, config)
    message = String.replace(message, ~r/\{\{\s*url\s*\}\}/, link)

    File.write!(output_path, generate_redirect_html(target, message))
  end

  defp build_target(to, base_path) do
    cond do
      external_url?(to) -> to
      base_path == "" -> to
      true -> prepend_base_path(to, base_path)
    end
  end

  defp prepend_base_path(to, base_path) do
    suffix = if String.ends_with?(to, "/"), do: "/", else: ""
    joined = Path.join(base_path, to)
    joined <> suffix
  end

  defp build_message_and_link(to, target, config) do
    if external_url?(to) do
      external_msg = config.html.external_message || config.html.message

      {
        external_msg,
        ~s(<a href="#{target}" rel="nofollow noreferrer noopener">#{target}</a>)
      }
    else
      {
        config.html.message,
        ~s(<a href="#{target}">#{target}</a>)
      }
    end
  end

  defp generate_redirect_html(target, message) do
    """
    <!DOCTYPE html>
    <meta charset="utf-8">
    <title>Redirecting to #{target}…</title>
    <link rel="canonical" href="#{target}">
    <meta http-equiv="refresh" content="0; url=#{target}">
    <p>#{message}</p>
    """
  end

  defp write_json_redirects(token, redirects) do
    mapped_redirects =
      Enum.map(redirects, fn {from, to} ->
        type = if directory_path?(from), do: "path", else: "file"
        target_type = if String.starts_with?(to, ["http://", "https://"]), do: "external", else: "internal"
        %{from: path_variants(from), type: type, to: to, target_type: target_type}
      end)

    permanent_redirects = Enum.sort_by(mapped_redirects, & &1.to)
    json_data = %{permanent_redirects: permanent_redirects}

    output_path = Path.join(token.site.config.out_dir, "redirects.json")
    File.write!(output_path, JSON.encode_to_iodata!(json_data))
  end

  defp path_variants(path) do
    if directory_path?(path) do
      base = String.trim_trailing(path, "/")
      [base, base <> "/", base <> "/index.html"]
    else
      [path]
    end
  end

  defp directory_path?(path) do
    String.ends_with?(path, "/") or String.ends_with?(path, "/index.html") or Path.extname(path) == ""
  end

  defp normalize_redirects(redirects) when is_list(redirects), do: normalize_redirects(Map.new(redirects))

  defp normalize_redirects(redirects) when is_map(redirects) do
    Map.new(redirects, fn {from, to} ->
      {normalize_path(to_string(from)), to}
    end)
  end

  defp normalize_path(path) do
    path
    |> String.trim()
    |> normalize_index_html()
    |> ensure_leading_slash()
    |> ensure_trailing_slash_if_directory()
  end

  defp normalize_index_html(path) do
    if String.ends_with?(path, "/index.html") do
      String.replace_suffix(path, "index.html", "")
    else
      path
    end
  end

  defp ensure_leading_slash("/" <> _ = path), do: path
  defp ensure_leading_slash(path), do: "/" <> path

  defp ensure_trailing_slash_if_directory(path) do
    cond do
      # Already has trailing slash
      String.ends_with?(path, "/") ->
        path

      # Has file extension (except /index.html which is treated as directory)
      Path.extname(path) != "" and not String.ends_with?(path, "/index.html") ->
        path

      # No extension, treat as directory
      true ->
        path <> "/"
    end
  end

  defp normalize_config(config) when is_list(config) or is_map(config) do
    {:ok, Map.new(config, &normalize_config/1)}
  end

  defp normalize_config({:html, true}), do: {:html, @default.html}
  defp normalize_config({:html, false}), do: {:html, %{@default.html | enabled: false}}
  defp normalize_config({:json, true}), do: {:json, @default.json}
  defp normalize_config({:json, false}), do: {:json, %{@default.json | enabled: false}}
  defp normalize_config({:redirects, redirects}), do: {:redirects, normalize_redirects(redirects)}

  defp normalize_config({key, value}) when is_list(value) or is_map(value) do
    {:ok, normalized} = normalize_config(value)
    {key, normalized}
  end

  defp normalize_config({key, value}), do: {key, value}

  defp validate_config(config) do
    with :ok <- validate_config_html(config.html),
         :ok <- validate_config_json(config.json),
         :ok <- validate_config_redirects(config.redirects) do
      {:ok, validate_output_enabled(config)}
    end
  end

  defp validate_config_html(config) when is_map(config) do
    with :ok <- validate_enabled(config[:enabled], "html"),
         :ok <- validate_message(config[:message]) do
      validate_external_message(config[:external_message])
    end
  end

  defp validate_config_html(_), do: {:error, "html configuration must be a map or boolean"}

  defp validate_enabled(enabled, _type) when is_boolean(enabled), do: :ok

  defp validate_enabled(_, type), do: {:error, "#{type}.enabled must be a boolean"}

  defp validate_message(message) when is_binary(message), do: :ok
  defp validate_message(_), do: {:error, "html.message must be a string"}

  defp validate_external_message(nil), do: :ok
  defp validate_external_message(message) when is_binary(message), do: :ok
  defp validate_external_message(_), do: {:error, "html.external_message must be a string or nil"}

  defp validate_config_json(config) when is_map(config), do: validate_enabled(config[:enabled], "json")
  defp validate_config_json(_), do: {:error, "json configuration must be a map or boolean"}

  defp validate_config_redirects(redirects) when is_map(redirects) do
    if Map.has_key?(redirects, "/") do
      {:error, "Redirect from root path (/) is not allowed"}
    else
      :ok
    end
  end

  defp validate_output_enabled(%{enabled: true, html: %{enabled: false}, json: %{enabled: false}} = config) do
    Logger.warning("[TableauRedirectsExtension] Extension disabled: no outputs enabled")
    %{config | enabled: false}
  end

  defp validate_output_enabled(config), do: config
end
