defmodule VowpalFleet.MixProject do
  use Mix.Project

  def project do
    [
      app: :vowpal_fleet,
      version: "0.1.2",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      source_url: "https://github.com/jackdoe/elixir-vowpal-fleet",
      name: "vowpal_fleet",
      docs: [
        main: "VowpalFleet",
        logo: "./logo.png",
        extras: ["README.md"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {VowpalFleet.Application, []}
    ]
  end

  defp deps do
    [
      {:swarm, "~> 3.0"},
      {:earmark, "~> 1.2", only: :dev},
      {:ex_doc, "~> 0.19", only: :dev}
    ]
  end

  defp description() do
    "Distributed Vowpal Wabbit Fleet (manages model handoff, round robbin predict and mass train)"
  end

  defp package() do
    [
      name: "vowpal_fleet",
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*),
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/jackdoe/elixir-vowpal-fleet"}
    ]
  end
end
