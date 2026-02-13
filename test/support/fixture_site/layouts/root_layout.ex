defmodule Site.RootLayout do
  @moduledoc false
  use Tableau.Layout

  import Temple

  def template(assigns) do
    temple do
      "<!DOCTYPE html>"

      html lang: "en" do
        head do
          meta(charset: "utf-8")
          title(do: @page[:title] || "Test Site")
        end

        body do
          render(@inner_content)
        end
      end
    end
  end
end
