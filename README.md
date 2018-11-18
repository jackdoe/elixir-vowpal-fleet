# VowpalFleet

![](https://github.com/jackdoe/elixir-vowpal-fleet/raw/master/logo.png)

Vowpal Fleet - manage [Vowpal Wabbit](https://github.com/VowpalWabbit/vowpal_wabbit) instances usint `Swarm`

## Info

* create one cluster per model using `VowpalFleet.start_worker/2`
* `VowpalFleet.train/3` goes to all living instance
* `VowpalFleet.predict/2` picks random instance to do the prediction
* configure auto save interval, root directory and vw options with mix config `:vowpal_fleet` in `config.exs`

## Installation

* Make sure you have [Vowpal Wabbit](https://github.com/VowpalWabbit/vowpal_wabbit) installed and it is findable in `$PATH`
* add the dependency to your mix.exs

```elixir
def deps do
  [
    {:vowpal_fleet, "~> 0.1.0"}
  ]
end
ef application do
  [
    extra_applications: [:vowpal_fleet]
  ]
end
```

* configure the parameters, edit `config/config.exs`

```
config :vowpal_fleet,
  root: "/tmp/vw",
  some_cluster_id: %{:autosave => 300_000, :args => ["--random_seed", "123"]}
```

## Work In Progress
More testing is needed to ensure that the failure scenarios are covered, at the moment the code just works but.. well take it with grain of salt

## Examples
    iex> VowpalFleet.start_worker(:some_cluster_id, :instance_1)
    ...
    :ok
    iex> VowpalFleet.start_worker(:some_cluster_id, :instance_2)
    ...
    :ok
    iex> VowpalFleet.train(:some_cluster_id, 1, [{"features", [1, 2, 3]}])
    :ok
    iex> VowpalFleet.predict(:some_cluster_id, [{"features", [1, 2, 3]}])
    1.0

## Handoff

  When the process has to be moved to a different node, the working model is saved, and then handed off to the starting process

## Links
[issues](https://github.com/jackdoe/elixir-vowpal-fleet/issues) [fork](https://github.com/jackdoe/elixir-vowpal-fleet) [license - MIT](https://en.wikipedia.org/wiki/MIT_License)

## credit
Icons made by [Freepik](https://www.freepik.com) from [Flaticon](https://www.flaticon.com/) is licensed by [CC 3.0 BY](http://creativecommons.org/licenses/by/3.0/)