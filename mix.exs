defmodule Idx.MixProject do
  use Mix.Project

  @version "0.1.0"
  @github_url "https://github.com/mat-hek/idx"

  def project do
    [
      app: :idx,
      version: @version,
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # hex
      description: "An indexable data collection",
      package: package(),

      # docs
      name: "Idx",
      source_url: @github_url,
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      formatters: ["html"],
      source_ref: "v#{@version}",
      nest_modules_by_prefix: [Idx]
    ]
  end

  defp package do
    [
      maintainers: ["Mateusz Front"],
      licenses: ["MIT"],
      links: %{"GitHub" => @github_url}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.29"}
    ]
  end
end
