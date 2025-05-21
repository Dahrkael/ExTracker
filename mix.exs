defmodule ExTracker.MixProject do
  use Mix.Project

  def version() do
    "0.5.0"
  end

  def project do
    [
      app: :extracker,
      version: version(),
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [
        extracker: [
          include_executables_for: [:unix],
          version: {:from_app, :extracker}
        ],
        extrackerw: [
          include_executables_for: [:windows],
          version: {:from_app, :extracker}
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
      {:bento, "~> 1.0"},
      {:locus, "~> 2.3"}
    ]
  end
end
