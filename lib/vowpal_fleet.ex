defmodule VowpalFleet.Type do
  @type feature() :: {integer(), float()} | {String.t(), float()} | String.t() | integer()
  @type namespace() :: {Strinb.t(), list(feature())}
end

defmodule VowpalFleet.Application do
  use Application

  def start(_type, _args) do
    VowpalFleet.Supervisor.start_link()
  end
end

defmodule VowpalFleet.Supervisor do
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
  require Logger
  use GenServer

  defp get_root() do
    r = Application.get_env(:vowpal, :root)

    case r do
      nil -> "/tmp/"
      _ -> r
    end
  end

  defp get_group_arguments(group) do
    r = Application.get_env(:vowpal, group)

    case r do
      nil -> %{:args => [], :autosave => 3600_1000}
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

    Logger.debug("starting vw #{real_name} #{port} #{pid}")

    # XXX: get periodic save from the config
    if autosave > 0 do
      Process.send_after(self(), :save, autosave)
    end

    {:ok, {{real_name, port, pid, socket}, :rand.uniform(5_000)}, 0}
  end

  def handle_call({:predict, namespaces}, _from, state) do
    {{_, _, _, socket}, _} = state
    {:reply, predict(socket, namespaces), state}
  end

  def handle_cast({:exit}, state) do
    {:stop, :shutdown, state}
  end

  def handle_info({:train, label, namespaces}, state) do
    {{_, _, _, socket}, _} = state
    train(socket, label, namespaces)
    {:noreply, state}
  end

  def handle_cast({:save}, state) do
    {{name, _, _, socket}, _} = state
    save(socket, name)
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
    spawn(fn -> save(name, socket) end)
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
  require Logger

  defp global_name(group, name) do
    String.to_atom("#{group}_#{name}")
  end

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

  @spec predict(atom(), list(VowpalFleet.Type.namespace())) :: float()
  def predict(group, namespaces) do
    members = Swarm.members(group)
    Logger.debug("picking member from #{length(members)}")
    who = Enum.random(members)
    GenServer.call(who, {:predict, namespaces})
  end

  @spec start_worker(atom(), atom()) :: :ok
  def exit(group, name) do
    GenServer.cast({:via, :swarm, global_name(group, name)}, {:exit})
  end

  @spec train(atom(), integer, list(VowpalFleet.Type.namespace())) :: :ok
  def train(group, label, namespaces) do
    Swarm.publish(group, {:train, label, namespaces})
  end
end
