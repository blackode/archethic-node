defmodule UnirisNetwork.Node do
  @moduledoc """
  Represent a node in the Uniris P2P network.
  Each node has it own process to enable fast update and retrieval.
  It also provide a fresh availability of the node:
  - when a node is started, a P2P connection is opened and monitored to follow any disconnection or error
  - when a node is the emitter source for a request, he can be identified as available
  - if the connection is down, a new connection will be start

  """

  use GenServer

  alias UnirisNetwork.P2P.Connection
  alias UnirisNetwork.NodeRegistry

  @enforce_keys [
    :first_public_key,
    :last_public_key,
    :ip,
    :port
  ]
  defstruct [
    :first_public_key,
    :last_public_key,
    :ip,
    :port,
    :geo_patch,
    :network_patch,
    availability: 0,
    average_availability: 0
  ]

  @type t() :: %__MODULE__{
          first_public_key: binary(),
          last_public_key: binary(),
          ip: :inet.ip_address(),
          port: :inet.port_number(),
          geo_patch: binary(),
          network_patch: binary(),
          availability: boolean(),
          average_availability: float()
        }

  def start_link(
        first_public_key: first_public_key,
        last_public_key: last_public_key,
        ip: ip,
        port: port
      ) do
    GenServer.start_link(__MODULE__, [first_public_key, last_public_key, ip, port],
      name: via_tuple(first_public_key)
    )
  end

  def init([first_public_key, last_public_key, ip, port]) do
    Registry.register(UnirisNetwork.NodeRegistry, last_public_key, [])
    Registry.register(UnirisNetwork.NodeRegistry, ip, [])

    data = %__MODULE__{
      first_public_key: first_public_key,
      last_public_key: last_public_key,
      ip: ip,
      port: port,
      geo_patch: UnirisNetwork.GeoPatch.from_ip(ip),
      average_availability: 0,
      availability: 0
    }

    {:ok, data}
  end

  def handle_cast(:available, state) do
    {:noreply, Map.put(state, :availability, 1)}
  end

  def handle_cast(:unavailable, state) do
    {:noreply, Map.put(state, :availability, 0)}
  end

  def handle_cast({:update_basics, last_public_key, ip, port}, state) do
    new_state =
      state
      |> Map.put(:last_public_key, last_public_key)
      |> Map.put(:ip, ip)
      |> Map.put(:port, port)

    {:noreply, new_state}
  end

  def handle_cast({:update_network_patch, network_patch}, state) do
    {:noreply, Map.put(state, :network_patch, network_patch)}
  end

  def handle_cast({:update_average_availability, avg_availability}, state) do
    {:noreply, Map.put(state, :average_availability, avg_availability)}
  end

  def handle_call({:send_message, msg}, _from, state = %{first_public_key: public_key}) do
    response = Connection.send_message(public_key, msg)
    {:reply, response, state}
  end

  def handle_call(:details, _from, state) do
    {:reply, state, state}
  end

  @doc """
  Mark the node as available
  """
  @spec available(binary()) :: :ok
  def available(node_public_key) when is_binary(node_public_key) do
    GenServer.cast(via_tuple(node_public_key), :available)
  end

  @doc """
  Mark the node as unavailable
  """
  @spec unavailable(binary()) :: :ok
  def unavailable(node_public_key) do
    GenServer.cast(via_tuple(node_public_key), :unavailable)
  end

  @doc """
  Get the details of a node
  """
  @spec details(binary()) :: __MODULE__.t()
  def details(node_public_key) when is_binary(node_public_key) do
    GenServer.call(via_tuple(node_public_key), :details)
  end

  @spec details(pid()) :: __MODULE__.t()
  def details(pid) when is_pid(pid) do
    GenServer.call(pid, :details)
  end

  @doc """
  Update the basic information of the node including: last public key, ip, port.

  A geo IP lookup will be perform to change the GeoPatch
  """
  @spec update_basics(binary(), binary(), :inet.ip_address(), :inet.port_number()) :: :ok
  def update_basics(first_public_key, last_public_key, ip, port) do
    GenServer.cast(via_tuple(first_public_key), {:update_basics, last_public_key, ip, port})
  end

  @doc """
  Update the network patch for a given node
  """
  @spec update_network_patch(binary(), binary()) :: :ok
  def update_network_patch(public_key, network_patch) do
    [{pid, _}] = Registry.lookup(UnirisNetwork.NodeRegistry, public_key)
    GenServer.cast(pid, {:update_network_patch, network_patch})
  end

  @doc """
  Update the average availability of the node
  """
  @spec update_average_availability(binary(), float()) :: :ok
  def update_average_availability(public_key, avg_availability)
      when is_float(avg_availability) and avg_availability >= 0 and
             avg_availability <= 1 do
    [{pid, _}] = Registry.lookup(UnirisNetwork.NodeRegistry, public_key)
    GenServer.cast(pid, {:update_average_availability, avg_availability})
  end

  @doc """
  Send a message to a node for the given public key
  """
  @spec send_message(__MODULE__.t(), term()) :: :ok
  def send_message(%__MODULE__{first_public_key: public_key}, message) do
    send_message(public_key, message)
  end

  @spec send_message(public_key :: binary(), message :: term()) :: :ok
  def send_message(public_key, msg) do
    GenServer.call(via_tuple(public_key), {:send_message, msg})
  end

  defp via_tuple(public_key) do
    {:via, Registry, {NodeRegistry, public_key}}
  end
end
