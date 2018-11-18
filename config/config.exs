use Mix.Config

config :vowpal_fleet,
  root: "/tmp/vw",
  abc: %{:autosave => 300_000, :args => ["--random_seed", "123"]}
