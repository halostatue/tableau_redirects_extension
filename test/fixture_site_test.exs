defmodule TableauRedirectsExtension.FixtureSiteTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  @moduletag :fixture_site
  @moduletag timeout: 60_000

  @fixtures_source Path.expand("fixtures", __DIR__)
  @site_output Path.expand("../tmp/test/_site", __DIR__)
  @site_output_base Path.expand("../tmp/test/_site_base", __DIR__)
  @site_output_root Path.expand("../tmp/test/_site_root", __DIR__)
  @fixtures_temp Path.expand("../tmp/test/fixtures", __DIR__)

  setup_all do
    File.rm_rf!(@site_output)
    File.rm_rf!(@site_output_base)
    File.rm_rf!(@site_output_root)
    File.rm_rf!(@fixtures_temp)

    # Build main fixture site with redirects that will trigger warnings
    Application.put_env(:tableau, TableauRedirectsExtension,
      enabled: true,
      redirects: %{
        "/old-url/" => "/about/",
        "/external/" => "https://example.com",
        "/dropped/" => "/about/#section",
        "/old-page.html" => "/about/",
        "/old/index.html" => "/about/",
        "/no-extension" => "/about/",
        "/old-image.gif" => "/about/",
        # This will be overridden by frontmatter in old-post.md
        "/blog/old-post/" => "/wrong/",
        # This will collide with existing content
        "/about/" => "/somewhere/",
        # This will create a loop
        "/loop-a/" => "/loop-b/",
        "/loop-b/" => "/loop-c/"
      }
    )

    TableauRedirectsExtension.FixtureBuilder.build()

    # Build base_path fixture site
    Application.put_env(:tableau, TableauRedirectsExtension,
      enabled: true,
      redirects: %{"/old/" => "/test/"}
    )

    TableauRedirectsExtension.FixtureBuilder.build(
      base_path: "/blogorama",
      out_dir: @site_output_base
    )

    :ok
  end

  describe "HTML redirect generation" do
    test "creates redirect file for global redirect" do
      redirect = read_output("old-url/index.html")

      assert redirect =~ ~s(<title>Redirecting to /about/…</title>)
      assert redirect =~ ~s(<link rel="canonical" href="/about/">)
      assert redirect =~ ~s(<meta http-equiv="refresh" content="0; url=/about/">)
      assert redirect =~ ~s(<a href="/about/">/about/</a>)
      refute redirect =~ ~s(<script>)
    end

    test "creates redirect file directly for file path" do
      assert File.exists?(Path.join(@site_output, "old-page.html"))
      redirect = read_output("old-page.html")

      assert redirect =~ ~s(<title>Redirecting to /about/…</title>)
      assert redirect =~ ~s(<meta http-equiv="refresh" content="0; url=/about/">)
    end

    test "normalizes /index.html to directory and creates redirect" do
      # /old/index.html normalizes to /old/ and creates /old/index.html
      assert File.exists?(Path.join(@site_output, "old/index.html"))
      redirect = read_output("old/index.html")

      assert redirect =~ ~s(<title>Redirecting to /about/…</title>)
      assert redirect =~ ~s(<meta http-equiv="refresh" content="0; url=/about/">)
    end

    test "does not create HTML redirect for non-HTML file types" do
      # .gif should not have an HTML redirect file
      refute File.exists?(Path.join(@site_output, "old-image.gif"))
    end

    test "creates redirect with nofollow for external URL" do
      redirect = read_output("external/index.html")

      assert redirect =~ ~s(<title>Redirecting to https://example.com…</title>)
      assert redirect =~ ~s(<a href="https://example.com" rel="nofollow noreferrer noopener">)
      assert redirect =~ "Redirecting to external site"
    end

    test "creates redirect with fragment" do
      redirect = read_output("dropped/index.html")

      assert redirect =~ ~s(<link rel="canonical" href="/about/#section">)
      assert redirect =~ ~s(<meta http-equiv="refresh" content="0; url=/about/#section">)
    end

    test "creates redirect for frontmatter alias" do
      redirect = read_output("blog/old-post/index.html")

      assert redirect =~ ~s(<link rel="canonical" href="/posts/old-post/">)
      assert redirect =~ ~s(<a href="/posts/old-post/">/posts/old-post/</a>)
    end

    test "creates redirect for frontmatter fragment" do
      redirect = read_output("blog/old-section/index.html")

      assert redirect =~ ~s(<link rel="canonical" href="/posts/old-post/#section">)
    end
  end

  describe "JSON manifest generation" do
    test "creates redirects.json with all redirects" do
      json = read_output("redirects.json")
      data = JSON.decode!(json)

      redirects = data["permanent_redirects"]
      assert is_list(redirects)
      assert length(redirects) >= 7

      # Check global directory redirects - from is now an array with variants
      assert Enum.any?(redirects, fn r ->
               r["from"] == ["/old-url", "/old-url/", "/old-url/index.html"] and
                 r["type"] == "path" and
                 r["to"] == "/about/" and
                 r["target_type"] == "internal"
             end)

      assert Enum.any?(redirects, fn r ->
               r["from"] == ["/external", "/external/", "/external/index.html"] and
                 r["type"] == "path" and
                 r["to"] == "https://example.com" and
                 r["target_type"] == "external"
             end)

      # Check file-style redirect - from is array with single entry
      assert Enum.any?(redirects, fn r ->
               r["from"] == ["/old-page.html"] and
                 r["type"] == "file" and
                 r["to"] == "/about/" and
                 r["target_type"] == "internal"
             end)

      # Check .gif file redirect - should be in JSON
      assert Enum.any?(redirects, fn r ->
               r["from"] == ["/old-image.gif"] and
                 r["type"] == "file" and
                 r["to"] == "/about/" and
                 r["target_type"] == "internal"
             end)

      # Check /index.html normalizes to directory
      assert Enum.any?(redirects, fn r ->
               r["from"] == ["/old", "/old/", "/old/index.html"] and
                 r["type"] == "path" and
                 r["to"] == "/about/" and
                 r["target_type"] == "internal"
             end)

      # Check frontmatter redirects
      assert Enum.any?(redirects, fn r ->
               r["from"] == ["/blog/old-post", "/blog/old-post/", "/blog/old-post/index.html"] and
                 r["type"] == "path" and
                 r["to"] == "/posts/old-post/" and
                 r["target_type"] == "internal"
             end)

      assert Enum.any?(redirects, fn r ->
               r["from"] == ["/blog/old-section", "/blog/old-section/", "/blog/old-section/index.html"] and
                 r["type"] == "path" and
                 r["to"] == "/posts/old-post/#section" and
                 r["target_type"] == "internal"
             end)
    end

    test "content redirects override global redirects with warning" do
      # /blog/old-post/ is defined in frontmatter of old-post.md
      # Global config has /old-url/ -> /about/
      # If we had /blog/old-post/ in global, it would be overridden
      json =
        "redirects.json"
        |> read_output()
        |> JSON.decode!()

      redirects = json["permanent_redirects"]

      # Verify the frontmatter redirect exists
      assert Enum.any?(redirects, fn r ->
               r["from"] == ["/blog/old-post", "/blog/old-post/", "/blog/old-post/index.html"] and
                 r["to"] == "/posts/old-post/"
             end)
    end

    test "redirects to existing content are ignored" do
      # /about/ is an actual page, so a redirect to it should be ignored
      # This is tested by the fact that we don't have a redirect FROM /about/
      json =
        "redirects.json"
        |> read_output()
        |> JSON.decode!()

      redirects = json["permanent_redirects"]

      refute Enum.any?(redirects, fn r -> "/about/" in r["from"] end)
    end

    test "rejects redirect loops" do
      # The fixture setup doesn't include loops, but we can verify
      # that no redirect target appears as a source
      json =
        "redirects.json"
        |> read_output()
        |> JSON.decode!()

      redirects = json["permanent_redirects"]

      sources =
        redirects
        |> Enum.flat_map(& &1["from"])
        |> MapSet.new()

      targets = MapSet.new(redirects, & &1["to"])

      # No target should be a source (would indicate a loop)
      assert MapSet.disjoint?(sources, targets)
    end
  end

  describe "root path redirect rejection" do
    setup do
      # Copy fixtures to temp and add a page with "/" alias
      File.rm_rf!(@fixtures_temp)
      File.cp_r!(@fixtures_source, @fixtures_temp)

      test_file = Path.join([@fixtures_temp, "_pages", "root-test.md"])

      File.write!(test_file, """
      ---
      title: Root Test
      permalink: /root-test/
      redirects:
        aliases:
          - /
      ---
      Test
      """)

      Application.put_env(:tableau, Tableau.PageExtension,
        enabled: true,
        dir: [Path.join(@fixtures_temp, "_pages")],
        layout: Site.RootLayout
      )

      Application.put_env(:tableau, Tableau.PostExtension,
        enabled: true,
        future: false,
        dir: [Path.join(@fixtures_temp, "_posts")],
        layout: Site.RootLayout
      )

      Application.put_env(:tableau, TableauRedirectsExtension, enabled: true, redirects: %{})

      :ok
    end

    test "rejects root path redirect in content" do
      log =
        capture_log(fn ->
          TableauRedirectsExtension.FixtureBuilder.build(out_dir: @site_output_root)
        end)

      assert log =~ "Redirect ignored: site root redirect (/) not allowed"

      # Verify the redirect wasn't added to JSON
      json =
        "redirects.json"
        |> read_output_root()
        |> JSON.decode!()

      redirects = json["permanent_redirects"]

      refute Enum.any?(redirects, fn r -> "/" in r["from"] end)
    end
  end

  describe "base_path handling" do
    test "prepends base_path to internal redirect targets in HTML" do
      redirect = read_output_base("old/index.html")
      assert redirect =~ ~s(<meta http-equiv="refresh" content="0; url=/blogorama/test/">)
      assert redirect =~ ~s(<a href="/blogorama/test/">/blogorama/test/</a>)
    end

    test "JSON contains original paths without base_path" do
      json =
        "redirects.json"
        |> read_output_base()
        |> JSON.decode!()

      redirects = json["permanent_redirects"]

      # Find the /old/ -> /test/ redirect we configured
      redirect =
        Enum.find(redirects, fn r ->
          ["/old", "/old/", "/old/index.html"] == r["from"]
        end)

      assert redirect["to"] == "/test/"
      assert redirect["target_type"] == "internal"
    end
  end

  defp read_output(path) do
    @site_output
    |> Path.join(path)
    |> File.read!()
  end

  defp read_output_base(path) do
    @site_output_base
    |> Path.join(path)
    |> File.read!()
  end

  defp read_output_root(path) do
    @site_output_root
    |> Path.join(path)
    |> File.read!()
  end
end
