defmodule VowpalFleetTest do
  use ExUnit.Case

  test "greets the world" do
    System.cmd("killall", ["-9", "vw"])
    VowpalFleet.start_worker(:test_abc, node())
    IO.inspect(VowpalFleet.exit(:test_abc, node()))
    VowpalFleet.start_worker(:test_abc, :a_1)

    VowpalFleet.start_worker(:test_abc, :a_2)
    VowpalFleet.train(:test_abc, 1, [{:test_abc, [1, 2, 3]}])

    IO.inspect(VowpalFleet.predict(:test_abc, [{:test_abc, [1, 2, 3]}]))
    IO.inspect(VowpalFleet.predict(:test_abc, [{:test_abc, [1, 2, 3]}]))
    IO.inspect(VowpalFleet.predict(:test_abc, [{:test_abc, [1, 2, 3]}]))
    query = [{:test_abc, [1, 2, 3]}]
    old = VowpalFleet.predict(:test_abc, query)

    VowpalFleet.start_worker(:test_abcd, :xyz)
    VowpalFleet.train(:test_abcd, -1, query)
    other_model = Enum.at(VowpalFleet.save(:test_abcd), 0)

    saved = VowpalFleet.save(:test_abc)
    assert length(saved) == 2
    model = Enum.random(saved)
    assert byte_size(model) > 0

    assert [:ok, :ok] = VowpalFleet.load(:test_abc, model)
    assert old == VowpalFleet.predict(:test_abc, query)
    assert [:ok, :ok] = VowpalFleet.load(:test_abc, other_model)
    assert old != VowpalFleet.predict(:test_abc, query)
    assert 0 != VowpalFleet.predict(:test_abc, query)

    # for x <- Stream.cycle([1]) do
    #   VowpalFleet.train(:test_abc, 1, [{:test_abc, [1, 2, 3]}])
    #   IO.inspect(VowpalFleet.predict(:test_abc, [{:test_abc, [1, 2, 3]}]))
    # end

    IO.inspect(VowpalFleet.exit(:test_abc, :a_1))
    :timer.sleep(2000)

    IO.inspect(VowpalFleet.predict(:test_abc, [{:test_abc, [1, 2, 3]}]))
    IO.inspect(VowpalFleet.predict(:test_abc, [{:test_abc, [1, 2, 3]}]))
    IO.inspect(VowpalFleet.predict(:test_abc, [{:test_abc, [1, 2, 3]}]))
    IO.inspect(VowpalFleet.predict(:test_abc, [{:test_abc, [1, 2, 3]}]))

    IO.inspect(VowpalFleet.exit(:test_abc, :a_2))
    IO.inspect(VowpalFleet.exit(:test_abcd, :a_1))
  end

  test "bandits" do
    VowpalFleet.start_worker(:test_abc_bandit, :a_1, %{
      :autosave => 300_000,
      :args => ["--random_seed", "123", "--cb_explore", "3"]
    })

    assert VowpalFleet.train(:test_abc_bandit, [{1, 100, 0.7}, {3, 70, 0.3}], [
             {:test_abc, [1, 2, 3]}
           ]) == :ok

    assert length(VowpalFleet.predict(:test_abc_bandit, [{:test_abc, [1, 2, 3]}])) == 3
    VowpalFleet.exit(:test_abc_bandit, :a_1)
  end
end
