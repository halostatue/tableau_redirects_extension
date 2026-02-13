defmodule TableauRedirectsExtension.FixtureBuilder do
  @moduledoc false

  alias Tableau.Graph.Nodable

  def build(opts \\ []) do
    {:ok, config} = Tableau.Config.get()
    config = struct!(config, opts)

    Application.ensure_all_started(:tableau)

    token = %{site: %{config: config}, graph: Graph.new(), extensions: %{}}

    mods =
      Enum.reduce(:code.all_available(), [], fn {mod, _, _}, acc ->
        mod = to_string(mod)

        if String.starts_with?(mod, "Elixir.") do
          [Module.safe_concat([to_string(mod)]) | acc]
        else
          acc
        end
      end)

    token = run_extensions(mods, :pre_build, token)
    token = run_extensions(mods, :pre_render, token)

    graph = Tableau.Graph.insert(token.graph, mods)

    pages =
      for page <- Graph.vertices(graph), {:ok, :page} == Nodable.type(page) do
        {page, Map.new(Nodable.opts(page) || [])}
      end

    token = put_in(token.site[:pages], Enum.map(pages, fn {_mod, page} -> page end))

    pages =
      Enum.map(pages, fn {mod, page} ->
        content = Tableau.Document.render(graph, mod, token, page)
        permalink = Nodable.permalink(mod)
        Map.merge(page, %{body: content, permalink: permalink})
      end)

    token = put_in(token.site[:pages], pages)
    token = run_extensions(mods, :pre_write, token)

    out = config.out_dir
    File.mkdir_p!(out)

    for %{body: body, permalink: permalink} <- token.site[:pages] do
      file_path = build_file_path(out, permalink)
      File.mkdir_p!(Path.dirname(file_path))
      File.write!(file_path, body)
    end

    run_extensions(mods, :post_write, token)
  end

  defp build_file_path(out, permalink) do
    if Path.extname(permalink) in [".html"] do
      Path.join(out, permalink)
    else
      Path.join([out, permalink, "index.html"])
    end
  end

  defp run_extensions(modules, type, token) do
    extensions =
      modules
      |> Enum.filter(&(Code.ensure_loaded?(&1) and function_exported?(&1, type, 1)))
      |> Enum.sort_by(& &1.__tableau_extension_priority__())

    Enum.reduce(extensions, token, fn module, token ->
      mod_config = Application.get_env(:tableau, module, %{})

      raw_config =
        Map.merge(%{enabled: Tableau.Extension.enabled?(module)}, Map.new(mod_config))

      if raw_config[:enabled] do
        run_extension(module, type, raw_config, token)
      else
        token
      end
    end)
  end

  defp run_extension(module, type, raw_config, token) do
    {:ok, config} = validate_config(module, raw_config)
    {:ok, key} = Tableau.Extension.key(module)
    token = put_in(token.extensions[key], %{config: config})

    case apply(module, type, [token]) do
      {:ok, token} -> token
      :error -> token
    end
  end

  defp validate_config(module, raw_config) do
    if function_exported?(module, :config, 1) do
      module.config(raw_config)
    else
      {:ok, raw_config}
    end
  end
end
