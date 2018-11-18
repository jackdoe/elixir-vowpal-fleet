defmodule VowpalFleet.Type do
  @type feature() :: {integer(), float()} | {String.t(), float()} | String.t() | integer()
  @type namespace() :: {Strinb.t(), list(feature())}
end

defmodule VowpalFleet.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    VowpalFleet.Supervisor.start_link()
  end
end

defmodule VowpalFleet.Supervisor do
  @moduledoc false
  use Supervisor

  def start_link() do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    children = [
      worker(VowpalFleet.Worker, [], restart: :temporary)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end

  def register(worker_name) do
    {:ok, _pid} = Supervisor.start_child(__MODULE__, [worker_name])
  end
end

defmodule VowpalFleet.Worker do
  @moduledoc false
  require Logger
  use GenServer

  defp get_root() do
    r = Application.get_env(:vowpal_fleet, :root)

    case r do
      nil -> "/tmp/"
      _ -> r
    end
  end

  defp get_group_arguments(group) do
    r = Application.get_env(:vowpal_fleet, group)

    case r do
      nil -> %{:args => [], :autosave => 3600_000}
      _ -> r
    end
  end

  defp get_initial_regressor(name) do
    Path.join(get_root(), "vw.#{name}.model")
  end

  defp get_pid_file(name) do
    Path.join(get_root(), "vw.#{name}.pid")
  end

  defp get_port_file(name) do
    Path.join(get_root(), "vw.#{name}.port")
  end

  defp kill(pid) do
    Logger.debug("killing #{pid}")
    System.cmd("kill", ["-9", "#{pid}"])
  end

  defp spawn_vw(name, args \\ []) do
    port_file = get_port_file(name)
    pid_file = get_pid_file(name)
    initial_regressor = get_initial_regressor(name)

    if File.exists?(pid_file) do
      kill(File.read!(pid_file))
    end

    extra_args =
      case File.exists?(initial_regressor) do
        true -> ["--initial_regressor", initial_regressor]
        _ -> []
      end

    File.rm(port_file)
    File.rm(pid_file)

    spawn(fn ->
      System.cmd(
        System.find_executable("vw"),
        [
          "--daemon",
          "--num_children",
          "1",
          "--quiet",
          "--no_stdin",
          "--port",
          "0",
          "--pid_file",
          pid_file,
          "--port_file",
          port_file
        ] ++ args ++ extra_args,
        into: IO.stream(:stdio, :line)
      )
    end)

    waitToExist(port_file, 1000)
    waitToExist(pid_file, 1000)

    {port, _} = Integer.parse(File.read!(port_file))
    {pid, _} = Integer.parse(File.read!(pid_file))

    {:ok, socket} =
      :gen_tcp.connect(
        {127, 0, 0, 1},
        port,
        [:binary, packet: :line, active: false, reuseaddr: true]
      )

    {port, pid, socket}
  end

  def start_link({group, name}) do
    GenServer.start_link(__MODULE__, {group, name})
  end

  def init({group, name}) do
    real_name = String.to_atom("#{group}_#{name}")

    %{:args => args, :autosave => autosave} = get_group_arguments(group)
    {port, pid, socket} = spawn_vw(real_name, args)

    Logger.debug("starting group: #{group}, vw #{real_name} #{port} #{pid}")

    if autosave > 0 do
      Logger.debug("autosaving every #{autosave}")
      Process.send_after(self(), :save, autosave)
    end

    {:ok, {{real_name, port, pid, socket}, :rand.uniform(5_000)}, 0}
  end

  def handle_call({:predict, namespaces}, _from, state) do
    {{_, _, _, socket}, _} = state
    {:reply, predict(socket, namespaces), state}
  end

  def handle_call({:load, model}, _from, state) do
    {{name, _, _, _}, _} = state
    File.write!(get_initial_regressor(name), model, [])

    {{name, _, pid, socket}, delay} = state
    :gen_tcp.close(socket)
    kill(pid)

    {new_port, new_pid, new_socket} = spawn_vw(name)

    {:reply, :ok, {{name, new_port, new_pid, new_socket}, delay}}
  end

  def handle_cast({:exit}, state) do
    {:stop, :shutdown, state}
  end

  def handle_call({:save}, _from, state) do
    {{name, _, _, socket}, _} = state
    model = save(socket, name)
    {:reply, model, state}
  end

  def handle_info({:train, label, namespaces}, state) do
    {{_, _, _, socket}, _} = state
    train(socket, label, namespaces)
    {:noreply, state}
  end

  def handle_call({:swarm, :begin_handoff}, _from, state) do
    # before handoff save our current model
    {{name, _, _, socket}, _} = state
    model = save(socket, name)
    {:reply, {:resume, model}, state}
  end

  @doc """
  model saved from some other node, we just pick it up, write to dosk and restart vw
  """
  def handle_cast({:swarm, :end_handoff, model}, state) do
    {{name, _, _, _}, _} = state
    File.write!(get_initial_regressor(name), model, [])

    {{name, _, pid, socket}, delay} = state
    :gen_tcp.close(socket)
    kill(pid)

    {new_port, new_pid, new_socket} = spawn_vw(name)

    {:noreply, {{name, new_port, new_pid, new_socket}, delay}}
  end

  def handle_cast({:swarm, :resolve_conflict, _delay}, state) do
    {:noreply, state}
  end

  def handle_info(:timeout, state) do
    {:noreply, state}
  end

  def handle_info(:save, state) do
    {{name, _, _, socket}, _} = state
    spawn(fn -> save(socket, name) end)
    {:noreply, state}
  end

  def handle_info({:swarm, :die}, state) do
    {:stop, :shutdown, state}
  end

  def sendToVw(socket, line) do
    :ok = :gen_tcp.send(socket, line)
    {:ok, data} = :gen_tcp.recv(socket, 0)
    data
  end

  @spec train(:gen_tcp.socket(), integer, list(VowpalFleet.Type.namespace())) :: float()
  defp train(socket, label, namespaces) do
    sendToVw(socket, "#{label} #{toLine(namespaces)}\n")
  end

  @spec predict(:gen_tcp.socket(), list(VowpalFleet.Type.namespace())) :: float()
  defp predict(socket, namespaces) do
    {v, _} = Float.parse(sendToVw(socket, "#{toLine(namespaces)}\n"))
    v
  end

  def waitToExist(path, interval) do
    Logger.info("waiting for #{path}")

    if File.exists?(path) do
      true
    else
      :timer.sleep(interval)
      waitToExist(path, interval)
    end
  end

  @spec toLine(list(VowpalFleet.Type.namespace())) :: String.t()
  defp toLine(namespaces) do
    line =
      namespaces
      |> Enum.map(fn {name, features} ->
        f =
          features
          |> Enum.map(fn e ->
            case e do
              {name, value} ->
                "#{name}:#{value}"

              name ->
                "#{name}:1"
            end
          end)
          |> Enum.join(" ")

        "|#{name} #{f}"
      end)
      |> Enum.join(" ")

    line
  end

  def save(socket, name) do
    path = get_initial_regressor(name)
    :ok = :gen_tcp.send(socket, "save_#{path}\n")

    waitToExist(path, 1000)
    File.read!(path)
  end

  def terminate(_reason, state) do
    {{name, _, pid, socket}, _} = state

    save(socket, name)
    :gen_tcp.close(socket)
    kill(pid)

    Logger.info("stopping #{name}, #{pid}, #{inspect(self())} on #{Node.self()}")
    :ok
  end
end

defmodule VowpalFleet do
  @moduledoc """
  Vowpal Fleet - manage [Vowpal Wabbit](https://github.com/VowpalWabbit/vowpal_wabbit) instances usint `Swarm`

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

  def application do
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

  ## Configuration
      config :vowpal_fleet,
        root: "/tmp/vw",
        some_cluster_id: %{:autosave => 300_000, :args => ["--random_seed", "123"]}

  ## Handoff

  When the process has to be moved to a different node, the working model is saved, and then handed off to the starting process

  ## Links
  [issues](https://github.com/jackdoe/elixir-vowpal-fleet/issues) [fork](https://github.com/jackdoe/elixir-vowpal-fleet) [license - MIT](https://en.wikipedia.org/wiki/MIT_License)
  """
  require Logger

  defp global_name(group, name) do
    String.to_atom("#{group}_#{name}")
  end

  @doc """
  Start a Vowpal Wabbit instance, (running local `vw --port 0 --daemon ...`) and connect to it usint TCP, then publish the new node in the `Swarm` using `Swarm.register_name/5`

  ## Parameters
    - group: some kind of cluster id, for examle model_name (:linear_abc_something)
    - name: instance id (e.g. :xyz)

  ## Examples
      iex> VowpalFleet.start_worker(:some_cluster_id, :instance_1)
      11:42:38.973 [info]  [swarm on nonode@nohost] [tracker:cluster_wait] joining cluster..

      11:42:38.973 [info]  [swarm on nonode@nohost] [tracker:cluster_wait] no connected nodes, proceeding without sync

      11:42:38.984 [debug] [swarm on nonode@nohost] [tracker:handle_call] registering :some_cluster_id_instance_1 as process started by Elixir.VowpalFleet.Supervisor.register/1 with args [some_cluster_id: :instance_1]

      11:42:38.984 [debug] [swarm on nonode@nohost] [tracker:do_track] starting :some_cluster_id_instance_1 on nonode@nohost

      11:42:38.984 [debug] killing 75225

      11:42:38.991 [info]  waiting for /tmp/vw/vw.some_cluster_id_instance_1.port

      11:42:39.992 [info]  waiting for /tmp/vw/vw.some_cluster_id_instance_1.port

      11:42:39.993 [info]  waiting for /tmp/vw/vw.some_cluster_id_instance_1.pid

      11:42:39.997 [debug] starting group: some_cluster_id, vw some_cluster_id_instance_1 60895 75980

      11:42:39.997 [debug] autosaving every 3600000

      11:42:40.000 [debug] [swarm on nonode@nohost] [tracker:do_track] started :some_cluster_id_instance_1 on nonode@nohost

      11:42:40.002 [debug] [swarm on nonode@nohost] [tracker:handle_call] add_meta {:some_cluster_id, true} to #PID<0.218.0>
      :ok
      iex>

  """
  @spec start_worker(atom(), atom()) :: :ok
  def start_worker(group, name) do
    {:ok, pid} =
      Swarm.register_name(
        global_name(group, name),
        VowpalFleet.Supervisor,
        :register,
        [
          {group, name}
        ]
      )

    Swarm.join(group, pid)
  end

  @doc """
  Send `|namespace feature1 feature2:1\\n` ... to a random instance from the specified group of `Swarm.members/1`

  ## Parameters
    - group: some kind of cluster id, for examle model_name (:linear_abc_something)
    - namespaces: training features of that example, list of `VowpalFleet.Type.namespace/0` type

  ## Examples
      iex> VowpalFleet.start_worker(:some_cluster_id, :instance_1)
      :ok
      iex(3)> VowpalFleet.predict(:some_cluster_id, [{"features", [1, 2, 3]}])
      0.632031
  """

  @spec predict(atom(), list(VowpalFleet.Type.namespace())) :: float()
  def predict(group, namespaces) do
    members = Swarm.members(group)
    Logger.debug("picking member from #{length(members)}")
    who = Enum.random(members)
    GenServer.call(who, {:predict, namespaces})
  end

  @doc """
  shut it down, kill the pid and close the socket
  """
  @spec start_worker(atom(), atom()) :: :ok
  def exit(group, name) do
    GenServer.cast({:via, :swarm, global_name(group, name)}, {:exit})
  end

  @doc """
  Send `label |namespace feature1 feature2:1\\n` ... to vw in all the active instances using `Swarm.publish/2` for the selected cluster

  ## Parameters
    - group: some kind of cluster id, for examle model_name (:linear_abc_something)
    - label: the training label (for example -1 for click, 1 for convert)
    - namespaces: training features of that example, list of `VowpalFleet.Type.namespace/0` type

  ## Examples
      iex> VowpalFleet.start_worker(:some_cluster_id, :instance_1)
      :ok
      iex> VowpalFleet.train(:some_cluster_id, 1, [{"features", [1, 2, 3]}])
      :ok
  """
  @spec train(atom(), integer, list(VowpalFleet.Type.namespace())) :: :ok
  def train(group, label, namespaces) do
    Swarm.publish(group, {:train, label, namespaces})
  end

  @doc """
  load a binary model on all the nodes in a group

  ## Parameters
    - group: some kind of cluster id, for examle model_name (:linear_abc_something)
    - model: binary output of File.read! of vowpal's regressor, or `Enum.random(VowpalFleet.save(:some_cluster_id))`

  ## Examples
      iex> VowpalFleet.start_worker(:some_cluster_id, :instance_1)
      :ok
      iex> VowpalFleet.load(:some_cluster_id, Enum.random(VowpalFleet.save(:some_cluster_id)))
      [:ok]
      iex>
  """
  @spec load(atom(), binary()) :: list(:ok)
  def load(group, model) do
    Swarm.multi_call(group, {:load, model})
  end

  @doc """
  saves a binary model on all the nodes in a group, and returns a list of all the models, can be fed to `VowpalFleet.load/2`

  ## Parameters
    - group: some kind of cluster id, for examle model_name (:linear_abc_something)

  ## Examples
      iex> VowpalFleet.start_worker(:some_cluster_id, :instance_1)
      :ok
      iex> VowpalFleet.save(:some_cluster_id)

      15:04:10.402 [info]  waiting for /tmp/vw/vw.some_cluster_id_instance_1.model

      15:04:11.403 [info]  waiting for /tmp/vw/vw.some_cluster_id_instance_1.model
      [
        <<6, 0, 0, 0, 56, 46, 54, 46, 49, 0, 1, 0, 0, 0, 0, 109, 0, 0, 0, 0, 0, 0, 0,
          0, 18, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 31, 0, 0, 0, 32, 45, 45,
          104, 97, ...>>
      ]
      iex>
  """
  @spec save(atom()) :: list(binary())
  def save(group) do
    Swarm.multi_call(group, {:save})
  end
end
