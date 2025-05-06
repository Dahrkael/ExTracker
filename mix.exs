defmodule ExTracker.MixProject do
  use Mix.Project

  def version() do
    "0.3.0"
  end

  def project do
    [
      app: :extracker,
      version: version(),
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [
        standard: [
          config_providers: [
            {ExTracker.JsonFileConfigProvider, [file: "config/extracker.json"]}
          ]
        ]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ExTracker.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      { :plug_cowboy, "~> 2.6" },
      #{ :json, "~> 1.4"},
      #{ :benx, "~> 0.1.2" }
      { :benx, github: "jschneider1207/benx", ref: "ab3ff74"},
      #{:wobserver_ng, "~> 1.14"}
    ]
  end
end
