import Config

if config_env() == :test do
  config :tableau, Tableau.PageExtension,
    enabled: true,
    dir: ["test/fixtures/_pages"],
    layout: Site.RootLayout

  config :tableau, Tableau.PostExtension,
    enabled: true,
    future: false,
    dir: ["test/fixtures/_posts"],
    layout: Site.RootLayout

  config :tableau, :config,
    url: "https://example.com",
    out_dir: "tmp/test/_site",
    markdown: [
      mdex: [
        extension: [
          table: true,
          header_ids: "",
          tasklist: true,
          strikethrough: true
        ],
        render: [unsafe: true]
      ]
    ]

  config :temple,
    engine: EEx.SmartEngine,
    attributes: {Temple, :attributes}
end
