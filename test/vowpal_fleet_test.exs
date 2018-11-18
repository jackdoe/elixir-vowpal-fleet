defmodule VowpalFleetTest do
  use ExUnit.Case

  test "greets the world" do
    System.cmd("killall", ["-9", "vw"])
    VowpalFleet.Supervisor.start_link()
    VowpalFleet.start_worker("abc", :a_1)
    VowpalFleet.start_worker("abc", :a_2)
    VowpalFleet.train("abc", 1, [{"abc", [1, 2, 3]}])

    IO.inspect(VowpalFleet.predict("abc", [{"abc", [1, 2, 3]}]))
    IO.inspect(VowpalFleet.predict("abc", [{"abc", [1, 2, 3]}]))
    IO.inspect(VowpalFleet.predict("abc", [{"abc", [1, 2, 3]}]))

    IO.inspect(VowpalFleet.exit("abc", :a_1))
    :timer.sleep(2000)

    IO.inspect(VowpalFleet.predict("abc", [{"abc", [1, 2, 3]}]))
    IO.inspect(VowpalFleet.predict("abc", [{"abc", [1, 2, 3]}]))
    IO.inspect(VowpalFleet.predict("abc", [{"abc", [1, 2, 3]}]))
    IO.inspect(VowpalFleet.predict("abc", [{"abc", [1, 2, 3]}]))

    IO.inspect(VowpalFleet.exit("abc", :a_2))
  end
end
