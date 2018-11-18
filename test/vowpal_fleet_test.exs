defmodule VowpalFleetTest do
  use ExUnit.Case

  test "greets the world" do
    System.cmd("killall", ["-9", "vw"])

    VowpalFleet.start_worker(:abc, :a_1)
    VowpalFleet.start_worker(:abc, :a_2)
    VowpalFleet.train(:abc, 1, [{:abc, [1, 2, 3]}])

    IO.inspect(VowpalFleet.predict(:abc, [{:abc, [1, 2, 3]}]))
    IO.inspect(VowpalFleet.predict(:abc, [{:abc, [1, 2, 3]}]))
    IO.inspect(VowpalFleet.predict(:abc, [{:abc, [1, 2, 3]}]))
    query = [{:abc, [1, 2, 3]}]
    old = VowpalFleet.predict(:abc, query)

    VowpalFleet.start_worker(:abcd, :xyz)
    VowpalFleet.train(:abcd, -1, query)
    other_model = Enum.at(VowpalFleet.save(:abcd), 0)

    saved = VowpalFleet.save(:abc)
    assert length(saved) == 2
    model = Enum.random(saved)
    assert byte_size(model) > 0

    assert [:ok, :ok] = VowpalFleet.load(:abc, model)
    assert old == VowpalFleet.predict(:abc, query)
    assert [:ok, :ok] = VowpalFleet.load(:abc, other_model)
    assert old != VowpalFleet.predict(:abc, query)
    assert 0 != VowpalFleet.predict(:abc, query)
    assert old < VowpalFleet.predict(:abc, query)

    # for x <- Stream.cycle([1]) do
    #   VowpalFleet.train(:abc, 1, [{:abc, [1, 2, 3]}])
    #   IO.inspect(VowpalFleet.predict(:abc, [{:abc, [1, 2, 3]}]))
    # end

    IO.inspect(VowpalFleet.exit(:abc, :a_1))
    :timer.sleep(2000)

    IO.inspect(VowpalFleet.predict(:abc, [{:abc, [1, 2, 3]}]))
    IO.inspect(VowpalFleet.predict(:abc, [{:abc, [1, 2, 3]}]))
    IO.inspect(VowpalFleet.predict(:abc, [{:abc, [1, 2, 3]}]))
    IO.inspect(VowpalFleet.predict(:abc, [{:abc, [1, 2, 3]}]))

    IO.inspect(VowpalFleet.exit(:abc, :a_2))
    IO.inspect(VowpalFleet.exit(:abcd, :a_1))
  end
end
