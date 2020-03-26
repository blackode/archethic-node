defmodule UnirisSync.SelfRepair do
  @moduledoc false

  use GenServer

  alias UnirisP2P, as: P2P
  alias UnirisElection, as: Election
  alias UnirisCrypto, as: Crypto
  alias UnirisChain, as: Chain
  alias UnirisBeacon, as: Beacon

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    repair_interval = Keyword.get(opts, :repair_interval)
    last_sync_date = Keyword.get(opts, :last_sync_date)

    schedule_sync(repair_interval)

    {:ok,
     %{
       repair_interval: repair_interval,
       last_sync_date: last_sync_date
     }}
  end

  def handle_info(
        :sync,
        state = %{
          repair_interval: interval,
          last_sync_date: last_sync_date
        }
      ) do
    Logger.info("Self-repair synchronization started")

    Beacon.get_pools(last_sync_date)
    |> addresses_to_sync(last_sync_date)
    |> download_transactions

    schedule_sync(interval)

    {:noreply, Map.put(state, :last_sync_date, DateTime.utc_now())}
  end

  defp schedule_sync(0), do: :ok

  defp schedule_sync(interval) do
    Process.send_after(self(), :sync, interval)
  end

  # defp store_last_sync_date(date) do
  #   data = DateTime.to_unix(date) |> Integer.to_string()
  #   File.write!(Application.app_dir(:uniris_sync, "priv/last_sync.txt"), data, [:write])
  # end

  # Request beacon pools the adresses in for a given time
  # and return only non existing transactions
  defp addresses_to_sync([], _), do: []

  defp addresses_to_sync(pools, last_sync_date) do
    Task.async_stream(pools, &query_beacon_addresses(last_sync_date, &1))
    |> Enum.into([], fn {:ok, res} -> res end)
    |> Enum.flat_map(& &1)
    |> Enum.filter(fn address ->
      case Chain.get_transaction(address) do
        {:ok, _} ->
          false

        {:error, :transaction_not_exists} ->
          true
      end
    end)
  end

  defp query_beacon_addresses(_, {_, []}), do: []

  defp query_beacon_addresses(last_sync_date, {subset, nodes}) do
    Task.async_stream(Enum.take(nodes, 5), fn node ->
      P2P.send_message(node, {:beacon_addresses, subset, DateTime.to_unix(last_sync_date)})
    end)
    |> Enum.into([], fn {:ok, res} -> res end)
    |> Enum.flat_map(& &1)
    |> Enum.uniq()
  end

  # Download a list of transaction from their addresses and store them
  defp download_transactions([]), do: :ok

  defp download_transactions(addresses) do
    Task.async_stream(addresses, fn address ->
      Election.storage_nodes(address)
      |> Enum.reject(&(Crypto.node_public_key() == &1.last_public_key))
      |> P2P.nearest_nodes()
      |> download_transaction(address)
    end)
    |> Stream.run()
  end

  defp download_transaction([node | rest], address) do
    case P2P.send_message(node, {:get_transaction, address}) do
      {:ok, tx} ->
        Chain.store_transaction(tx)

      {:error, :transaction_not_exists} ->
        download_transaction(rest, address)
    end
  end

  defp download_transaction([], _), do: {:error, :network_issue}
end
