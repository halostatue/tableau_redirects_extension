defmodule Site.HomePage do
  @moduledoc false

  use Tableau.Page,
    layout: Site.RootLayout,
    permalink: "/"

  import Temple

  def template(_assigns) do
    temple do
      h1(do: "Home")
      p(do: "Welcome to the test site")
    end
  end
end
