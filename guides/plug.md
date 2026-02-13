# Using Redirects with Plug

The JSON output from TableauRedirectsExtension can be used to create a Plug that
handles redirects in your Phoenix or Plug application.

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
index.html). File entries list only the exact path.

A JSON schema is available at `priv/redirects.schema.json` for validation and
editor support.

## Basic Redirect Plug

Create a plug that reads the redirect map and performs 301 redirects:

```elixir
defmodule MyAppWeb.RedirectPlug do
  @moduledoc """
  Handles permanent redirects from a redirect map.
  """
  import Plug.Conn

  @redirect_map File.read!("priv/static/redirects.json")
                |> JSON.decode!()
                |> then(& &1["permanent_redirects"])
                |> Enum.flat_map(fn %{"from" => from_uris, "to" => to} ->
                  Enum.map(from_uris, fn from -> {from, to} end)
                end)
                |> Map.new()

  def init(opts), do: opts

  def call(conn, _opts) do
    case Map.get(@redirect_map, conn.request_path) do
      nil ->
        conn

      target ->
        body = ~s(<a href="#{target}">Moved</a>)

        conn
        |> put_resp_header("location", target)
        |> send_resp(301, body)
        |> halt()
    end
  end
end
```

Add it to your endpoint or router:

```elixir
# In your endpoint.ex
plug MyAppWeb.RedirectPlug

# Or in your router.ex before other routes
pipeline :redirects do
  plug MyAppWeb.RedirectPlug
end

scope "/", MyAppWeb do
  pipe_through [:redirects, :browser]
  # ... your routes
end
```

## Runtime Reload Support

For applications that need to reload redirects without recompiling, extract the
Agent into a separate module:

```elixir
defmodule MyApp.Redirects do
  @moduledoc """
  Manages redirect map with runtime reload support.
  """
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> load_redirects() end, name: __MODULE__)
  end

  def get_map do
    Agent.get(__MODULE__, & &1)
  end

  def reload do
    Agent.update(__MODULE__, fn _ -> load_redirects() end)
  end

  defp load_redirects do
    "priv/static/redirects.json"
    |> File.read!()
    |> JSON.decode!()
    |> then(& &1["permanent_redirects"])
    |> Enum.flat_map(fn %{"from" => from_uris, "to" => to} ->
      Enum.map(from_uris, fn from -> {from, to} end)
    end)
    |> Map.new()
  end
end

defmodule MyAppWeb.RedirectPlug do
  @moduledoc """
  Handles permanent redirects with runtime reload support.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    redirect_map = MyApp.Redirects.get_map()

    case Map.get(redirect_map, conn.request_path) do
      nil ->
        conn

      target ->
        body = ~s(<a href="#{target}">Moved</a>)

        conn
        |> put_resp_header("location", target)
        |> send_resp(301, body)
        |> halt()
    end
  end
end
```

Add the agent to your application supervision tree:

```elixir
# In application.ex
def start(_type, _args) do
  children = [
    MyApp.Redirects,
    # ... other children
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

Reload redirects at runtime:

```elixir
MyApp.Redirects.reload()
```

## Notes

- The compile-time version (`@redirect_map`) is faster but requires
  recompilation when redirects change
- The runtime version allows reloading redirects with `MyApp.Redirects.reload()`
- Map lookups are very efficient for typical redirect counts (dozens to
  thousands)
- The plug should be placed early in your pipeline to avoid unnecessary
  processing
- External redirects (starting with `http://` or `https://`) work automatically
- The `permanent_redirects` key indicates these are 301 (permanent) redirects
- Target values in the JSON are absolute paths (starting with `/`) for internal
  redirects and full URLs (starting with `http://` or `https://`) for external
  redirects
- Redirects match exact paths only; the `from` array contains the three
  canonical variants for directory-style paths (bare, trailing slash,
  index.html) and the exact path for files. This is not prefix matching.
- Query strings are not included in the path match but are automatically
  preserved by most browsers. To explicitly preserve query strings:
  ```elixir
  redirect_to =
    if conn.query_string == "",
      do: target,
      else: target <> "?" <> conn.query_string
  ```
- Consider emitting telemetry events for monitoring redirect usage:
  ```elixir
  :telemetry.execute([:myapp, :redirect], %{count: 1}, %{from: conn.request_path, to: redirect_to})
  ```
- Path normalization (percent-encoding, trailing slashes) should match your
  site's URL structure; the generator normalizes paths consistently
- For absolute URLs in the Location header (preferred by some clients):
  ```elixir
  target = 
    conn
    |>Plug.Conn.request_url()
    |> URI.merge(target)
    |> to_string()
  ```
