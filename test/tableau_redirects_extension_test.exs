defmodule TableauRedirectsExtensionTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias TableauRedirectsExtension, as: Extension

  describe "config/1" do
    test "returns default config when given empty map" do
      assert {:ok,
              %{
                enabled: false,
                html: %{enabled: true},
                json: %{enabled: true},
                redirects: redirects
              }} = Extension.config(%{})

      assert redirects == %{}
    end

    test "accepts keyword list" do
      assert {:ok, %{enabled: true, redirects: %{"/old/" => "/new/"}}} =
               Extension.config(enabled: true, redirects: %{"/old/" => "/new/"})
    end

    test "normalizes html: true to default html config" do
      assert {:ok,
              %{
                html: %{enabled: true, message: "Redirecting to {{ url }}…"}
              }} = Extension.config(html: true)
    end

    test "normalizes html: false to disabled html config" do
      assert {:ok, %{enabled: true, html: %{enabled: false}}} = Extension.config(enabled: true, html: false)
    end

    test "normalizes json: true to default json config" do
      assert {:ok, %{json: %{enabled: true}}} = Extension.config(json: true)
    end

    test "normalizes json: false to disabled json config" do
      assert {:ok, %{enabled: true, json: %{enabled: false}}} = Extension.config(enabled: true, json: false)
    end

    test "merges custom html config with defaults" do
      assert {:ok,
              %{
                html: %{enabled: false, message: "Redirecting to {{ url }}…"}
              }} = Extension.config(html: [enabled: false])
    end

    test "normalizes redirects from keyword list to map" do
      assert {:ok,
              %{
                redirects: %{"/old/" => "/new/", "/another/" => "/target/"}
              }} = Extension.config(redirects: ["/old/": "/new/", "/another/": "/target/"])
    end

    test "normalizes redirect paths with leading/trailing slashes" do
      assert {:ok,
              %{
                redirects: %{"/old/" => "/new/"}
              }} = Extension.config(redirects: %{"old" => "/new/"})
    end

    test "preserves external URLs without trailing slash" do
      assert {:ok, %{redirects: %{"/old/" => "https://example.com"}}} =
               Extension.config(redirects: %{"/old/" => "https://example.com"})
    end

    test "validates html.enabled is boolean" do
      assert {:ok, _} = Extension.config(html: [enabled: true])
      assert {:ok, _} = Extension.config(html: [enabled: false])
      assert {:error, "html.enabled must be a boolean"} = Extension.config(html: [enabled: "yes"])
    end

    test "validates json.enabled is boolean" do
      assert {:ok, _} = Extension.config(json: [enabled: true])
      assert {:ok, _} = Extension.config(json: [enabled: false])
      assert {:error, "json.enabled must be a boolean"} = Extension.config(json: [enabled: "yes"])
    end

    test "returns error for invalid html.message type " do
      assert {:error, "html.message must be a string"} = Extension.config(html: [message: 123])
    end

    test "returns error for invalid html.external_message type" do
      assert {:error, "html.external_message must be a string or nil"} =
               Extension.config(html: [message: "test", external_message: 123])
    end

    test "returns error for invalid html shortcut type" do
      assert {:error, "html configuration must be a map or boolean"} = Extension.config(html: "not a map")
    end

    test "returns error for invalid json shortcut type" do
      assert {:error, "json configuration must be a map or boolean"} = Extension.config(json: "not a map")
    end

    test "warns when extension enabled but both outputs disabled" do
      assert capture_log(fn ->
               assert {:ok, config} = Extension.config(enabled: true, html: [enabled: false], json: [enabled: false])
               assert config.enabled == false
             end) =~ "[TableauRedirectsExtension] Extension disabled: no outputs enabled"
    end

    test "normalizes directory paths with trailing slash" do
      assert {:ok, config} = Extension.config(redirects: %{"old" => "/new/"})
      assert config.redirects == %{"/old/" => "/new/"}
    end

    test "preserves file extensions without adding trailing slash" do
      assert {:ok, %{redirects: %{"/old.html" => "/new/"}}} = Extension.config(redirects: %{"/old.html" => "/new/"})
    end

    test "treats /index.html as directory path" do
      assert {:ok, %{redirects: %{"/old/" => "/new/"}}} = Extension.config(redirects: %{"/old/index.html" => "/new/"})
    end

    test "normalizes paths without extensions to directories" do
      assert {:ok, %{redirects: %{"/no-ext/" => "/new/"}}} = Extension.config(redirects: %{"no-ext" => "/new/"})
    end

    test "preserves various file extensions" do
      assert {:ok,
              %{
                redirects: %{
                  "/file.html" => "/new/",
                  "/file.htm" => "/new/",
                  "/file.php" => "/new/",
                  "/file.gif" => "/new/",
                  "/file.jpg" => "/new/"
                }
              }} =
               Extension.config(
                 redirects: %{
                   "/file.html" => "/new/",
                   "/file.htm" => "/new/",
                   "/file.php" => "/new/",
                   "/file.gif" => "/new/",
                   "/file.jpg" => "/new/"
                 }
               )
    end

    test "rejects root path redirect in global config" do
      assert {:error, "Redirect from root path (/) is not allowed"} =
               Extension.config(redirects: %{"/" => "/home/"})
    end

    test "allows custom redirect message" do
      assert {:ok, %{html: %{message: "Custom {{ url }}"}}} = Extension.config(html: [message: "Custom {{ url }}"])
    end

    test "allows custom external redirect message" do
      assert {:ok, %{html: %{external_message: "External {{ url }}"}}} =
               Extension.config(html: [external_message: "External {{ url }}"])
    end

    test "external_message can be nil to use message for all redirects" do
      assert {:ok, %{html: %{message: "Go to {{ url }}", external_message: nil}}} =
               Extension.config(html: [message: "Go to {{ url }}", external_message: nil])
    end
  end
end
