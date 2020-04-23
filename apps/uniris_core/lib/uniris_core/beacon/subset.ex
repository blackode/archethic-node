defmodule UnirisCore.BeaconSubset do
  @moduledoc false

  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.BeaconSubsetRegistry
  alias UnirisCore.BeaconSlot
  alias UnirisCore.BeaconSlot.TransactionInfo
  alias UnirisCore.BeaconSlot.NodeInfo
  alias UnirisCore.Storage
  alias UnirisCore.PubSub

  use GenServer

  require Logger

  def start_link(opts) do
    subset = Keyword.get(opts, :subset)
    slot_interval = Keyword.get(opts, :slot_interval)
    startup_date = DateTime.utc_now()

    GenServer.start_link(__MODULE__, [subset, slot_interval, startup_date],
      name: via_tuple(subset)
    )
  end

  def init([subset, slot_interval, startup_date]) do
    current_time = Time.utc_now().second * 1000
    last_interval = slot_interval * trunc(current_time / slot_interval)
    next_interval = last_interval + slot_interval
    offset = next_interval - current_time

    schedule_slot(offset)

    {:ok,
     %{
       subset: subset,
       current_slot: %BeaconSlot{},
       slots: %{},
       slot_time: startup_date,
       slot_interval: slot_interval
     }}
  end

  def handle_cast({:add_transaction_info, tx_info = %TransactionInfo{address: address}}, state) do
    Logger.debug(
      "Transaction #{inspect(tx_info)} added to the beacon chain (subset #{
        Base.encode16(state.subset)
      })"
    )

    PubSub.notify_new_transaction(address)
    {:noreply, Map.update!(state, :current_slot, &BeaconSlot.add_transaction_info(&1, tx_info))}
  end

  def handle_cast({:add_node_info, node_info = %NodeInfo{}}, state) do
    Logger.debug(
      "Node #{inspect(node_info)} info added to the beacon chain subset(#{
        Base.encode16(state.subset)
      })"
    )

    {:noreply, Map.update!(state, :current_slot, &BeaconSlot.add_node_info(&1, node_info))}
  end

  def handle_info(
        :create_slot,
        state = %{
          current_slot: %BeaconSlot{transactions: [], nodes: []},
          slot_time: slot_time,
          slot_interval: interval
        }
      ) do
    schedule_slot(interval)
    {:noreply, Map.put(state, :slot_time, DateTime.add(slot_time, interval))}
  end

  def handle_info(
        :create_slot,
        state = %{
          current_slot: current_slot,
          slot_time: slot_time,
          slot_interval: interval
        }
      ) do
    tx = Transaction.new(:beacon, %TransactionData{content: output_slot(current_slot)})
    Storage.write_transaction(tx)

    new_state =
      state
      |> Map.put(:current_slot, %BeaconSlot{})
      |> put_in([:slots, slot_time |> DateTime.to_unix()], tx)
      |> Map.put(:slot_time, DateTime.add(slot_time, interval))

    Logger.debug("Beacon slot created")

    schedule_slot(interval)
    {:noreply, new_state}
  end

  def handle_call({:previous_slots, last_sync_date}, _, state = %{slots: slots}) do
    previous_slots =
      slots
      |> Enum.filter(fn {time, _} -> time >= last_sync_date end)
      |> Enum.sort_by(fn {time, _} -> time end)
      |> Enum.map(fn {_, %Transaction{data: %{content: content}}} ->
        content
        |> String.split("\n")
        |> Enum.reduce(%BeaconSlot{}, fn line, slot ->
          case String.split(line, " - ") do
            ["T", type, timestamp, address] ->
              BeaconSlot.add_transaction_info(slot, %TransactionInfo{
                address: Base.decode16!(address),
                timestamp: timestamp |> String.to_integer() |> DateTime.from_unix(),
                type: Transaction.parse_type(String.to_integer(type))
              })

            ["N", public_key, "R"] ->
              BeaconSlot.add_node_info(slot, %NodeInfo{
                public_key: Base.decode16!(public_key),
                ready?: true
              })
          end
        end)
      end)

    {:reply, previous_slots, state}
  end

  defp schedule_slot(0), do: :ok

  defp schedule_slot(interval) do
    Process.send_after(self(), :create_slot, interval)
  end

  defp output_slot(%BeaconSlot{transactions: [], nodes: nodes}) do
    output_nodes(nodes)
  end

  defp output_slot(%BeaconSlot{transactions: transactions, nodes: []}) do
    output_transactions(transactions)
  end

  defp output_slot(%BeaconSlot{transactions: transactions, nodes: nodes}) do
    output_transactions(transactions) <> "\n" <> output_nodes(nodes)
  end

  defp output_transactions(transactions) do
    Enum.map(transactions, fn %TransactionInfo{
                                address: address,
                                timestamp: timestamp,
                                type: type
                              } ->
      "T - #{Transaction.serialize_type(type)} - #{DateTime.to_unix(timestamp)} - #{
        address |> Base.encode16()
      }"
    end)
    |> Enum.join("\n")
  end

  defp output_nodes(nodes) do
    Enum.map(nodes, fn %NodeInfo{public_key: public_key, ready?: ready?} ->
      infos = []

      infos =
        if ready? do
          infos ++ ["R"]
        end

      "N - #{Base.encode16(public_key)} - #{Enum.join(infos, " - ")}"
    end)
    |> Enum.join("\n")
  end

  @spec add_transaction_info(sbuset :: binary(), Transaction.info()) :: :ok
  def add_transaction_info(subset, tx_info = %TransactionInfo{}) do
    GenServer.cast(via_tuple(subset), {:add_transaction_info, tx_info})
  end

  @spec add_node_info(subset :: binary(), NodeInfo.t()) :: :ok
  def add_node_info(subset, node_info = %NodeInfo{}) do
    GenServer.cast(via_tuple(subset), {:add_node_info, node_info})
  end

  @spec previous_slots(binary(), integer()) :: BeaconSlot.t()
  def previous_slots(subset, last_sync_date) do
    subset
    |> via_tuple
    |> GenServer.call({:previous_slots, last_sync_date})
  end

  defp via_tuple(subset) do
    {:via, Registry, {BeaconSubsetRegistry, subset}}
  end
end
