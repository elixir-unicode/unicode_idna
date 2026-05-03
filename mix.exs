defmodule Unicode.IDNA.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :unicode_idna,
      version: @version,
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      build_embedded: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      name: "Unicode IDNA",
      source_url: "https://github.com/elixir-unicode/unicode_idna",
      description: description(),
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        plt_add_apps: ~w(mix inets public_key)a,
        ignore_warnings: ".dialyzer_ignore_warnings"
      ]
    ]
  end

  defp description do
    """
    Pure-Elixir implementation of UTS #46 (IDNA 2008 Compatibility
    Processing) with Punycode (RFC 3492), bidi (RFC 5893) and
    CONTEXTJ joiner rules.
    """
  end

  defp package do
    [
      maintainers: ["Kip Cole"],
      licenses: ["Apache-2.0"],
      links: links(),
      files: [
        "lib",
        "data",
        "mix.exs",
        "README*",
        "CHANGELOG*",
        "LICENSE*"
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :public_key, :inets, :ssl]
    ]
  end

  defp deps do
    [
      {:unicode, "~> 1.22"},
      {:ex_doc, "~> 0.24", only: [:dev, :release], runtime: false, optional: true},
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false, optional: true}
    ]
  end

  def links do
    %{
      "GitHub" => "https://github.com/elixir-unicode/unicode_idna",
      "Readme" => "https://github.com/elixir-unicode/unicode_idna/blob/v#{@version}/README.md",
      "Changelog" =>
        "https://github.com/elixir-unicode/unicode_idna/blob/v#{@version}/CHANGELOG.md"
    }
  end

  def docs do
    [
      source_ref: "v#{@version}",
      main: "readme",
      extras: [
        "README.md",
        "LICENSE.md",
        "CHANGELOG.md"
      ],
      formatters: ["html"],
      skip_undefined_reference_warnings_on: ["changelog", "CHANGELOG.md"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "mix", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "mix"]
  defp elixirc_paths(_), do: ["lib"]
end
