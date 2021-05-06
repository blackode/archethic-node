defmodule Uniris.Mining.StandaloneWorkflow do
  @moduledoc """
  Transaction validation is performed in a single node processing.
  This workflow should be executed only when the network is bootstrapping (only 1 validation node)

  The single node will auto validate the transaction
  """
  use Task

  alias Uniris.Crypto

  alias Uniris.Mining.PendingTransactionValidation
  alias Uniris.Mining.TransactionContext
  alias Uniris.Mining.ValidationContext

  alias Uniris.P2P
  alias Uniris.P2P.Message.ReplicateTransaction
  alias Uniris.P2P.Node

  alias Uniris.Replication

  alias Uniris.TransactionChain.Transaction

  require Logger

  def start_link(opts \\ []) do
    Task.start_link(__MODULE__, :run, [opts])
  end

  def run(opts) do
    tx = Keyword.get(opts, :transaction)
    Logger.info("Start mining", transaction: Base.encode16(tx.address))

    chain_storage_nodes = Replication.chain_storage_nodes_with_type(tx.address, tx.type)

    beacon_storage_nodes = Replication.beacon_storage_nodes(tx.address, DateTime.utc_now())

    {prev_tx, unspent_outputs, previous_storage_nodes, chain_storage_nodes_view,
     beacon_storage_nodes_view,
     validation_nodes_view} =
      TransactionContext.get(
        Transaction.previous_address(tx),
        Enum.map(chain_storage_nodes, & &1.last_public_key),
        Enum.map(beacon_storage_nodes, & &1.last_public_key),
        [Crypto.node_public_key()]
      )

    valid_pending_transaction? =
      case PendingTransactionValidation.validate(tx) do
        :ok ->
          true

        _ ->
          false
      end

    ValidationContext.new(
      transaction: tx,
      welcome_node: P2P.get_node_info(),
      validation_nodes: [P2P.get_node_info()],
      chain_storage_nodes: chain_storage_nodes,
      beacon_storage_nodes: beacon_storage_nodes
    )
    |> ValidationContext.set_pending_transaction_validation(valid_pending_transaction?)
    |> ValidationContext.put_transaction_context(
      prev_tx,
      unspent_outputs,
      previous_storage_nodes,
      chain_storage_nodes_view,
      beacon_storage_nodes_view,
      validation_nodes_view
    )
    |> validate()
    |> replicate()
  end

  defp validate(context = %ValidationContext{}) do
    context
    |> ValidationContext.create_validation_stamp()
    |> ValidationContext.cross_validate()
  end

  defp replicate(context) do
    validated_tx = ValidationContext.get_validated_transaction(context)

    storage_nodes = ValidationContext.get_storage_nodes(context)
 

    Logger.debug(
      "Send validated transaction to #{
        storage_nodes |> Enum.map(fn {node, roles} -> "#{Node.endpoint(node)} as #{Enum.join(roles, ",") }" end) |> Enum.join(",")
      }",
      transaction: "#{validated_tx.type}@#{Base.encode16(validated_tx.address)}"
    )


    Task.async_stream(storage_nodes, fn {node, roles} ->
        P2P.send_message(node, %ReplicateTransaction{
          transaction: validated_tx,
          roles: roles,
          ack_storage?: true
        })
      end,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Stream.run()
  end
end
