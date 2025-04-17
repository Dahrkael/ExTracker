defmodule ExTracker.MixProject do
  use Mix.Project

  def project do
    [
      app: :extracker,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      { :plug_cowboy, "~> 2.0" },
      { :benx, "~> 0.1.2" }
    ]
  end
end
