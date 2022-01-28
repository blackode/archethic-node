defmodule ArchEthic.Bootstrap.TransactionHandler do
  @moduledoc false

  alias ArchEthic.Crypto

  alias ArchEthic.Election

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.GetTransactionSummary
  alias ArchEthic.P2P.Message.NewTransaction
  alias ArchEthic.P2P.Message.NotFound
  alias ArchEthic.P2P.Message.Ok
  alias ArchEthic.P2P.Node

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionSummary

  require Logger

  @doc """
  Send a transaction to the network towards a welcome node
  """
  @spec send_transaction(Transaction.t(), list(Node.t())) :: :ok | {:error, :network_issue}
  def send_transaction(tx = %Transaction{address: address}, nodes) do
    Logger.info("Send node transaction...",
      transaction_address: Base.encode16(address),
      transaction_type: "node"
    )

    do_send_transaction(nodes, tx)
  end

  defp do_send_transaction([node | rest], tx) do
    case P2P.send_message(node, %NewTransaction{transaction: tx}) do
      {:ok, %Ok{}} ->
        Logger.info("Waiting transaction validation",
          transaction_address: Base.encode16(tx.address),
          transaction_type: "node"
        )

        storage_nodes =
          Election.chain_storage_nodes_with_type(tx.address, tx.type, P2P.available_nodes())

        await_confirmation(tx.address, storage_nodes)

        :ok

      {:error, _} = e ->
        Logger.error("Cannot send node transaction - #{inspect(e)}",
          node: Base.encode16(node.first_public_key)
        )

        do_send_transaction(rest, tx)
    end
  end

  defp do_send_transaction([], _), do: {:error, :network_issue}

  defp await_confirmation(tx_address, [node | rest]) do
    case P2P.send_message(node, %GetTransactionSummary{address: tx_address}) do
      {:ok, %TransactionSummary{address: ^tx_address}} ->
        :ok

      {:ok, %NotFound{}} ->
        Process.sleep(200)
        await_confirmation(tx_address, [node | rest])

      {:error, e} ->
        Logger.error("Cannot get transaction summary - #{inspect(e)}",
          node: Base.encode16(node.first_public_key)
        )

        await_confirmation(tx_address, rest)
    end
  end

  @doc """
  Create a new node transaction
  """
  @spec create_node_transaction(
          :inet.ip_address(),
          :inet.port_number(),
          P2P.supported_transport(),
          Crypto.versioned_hash()
        ) ::
          Transaction.t()
  def create_node_transaction(ip = {_, _, _, _}, port, transport, reward_address)
      when is_number(port) and port >= 0 and is_binary(reward_address) do
    key_certificate = Crypto.get_key_certificate(Crypto.last_node_public_key())

    Transaction.new(:node, %TransactionData{
      content:
        Node.encode_transaction_content(ip, port, transport, reward_address, key_certificate)
    })
  end
end
