defmodule UnirisChain.DefaultImpl.Store do
  @moduledoc false
  alias UnirisChain.Transaction

  @behaviour __MODULE__.Impl

  defdelegate child_spec(opts),
    to: Application.get_env(:uniris_chain, :store, __MODULE__.FileImpl)

  @spec get_transaction(binary()) ::
          {:ok, Transaction.validated()} | {:error, :transaction_not_exists}
  @impl true
  def get_transaction(address) do
    impl().get_transaction(address)
  end

  @spec get_transaction_chain(binary()) ::
          {:ok, list(Transaction.validated())} | {:error, :transaction_chain_not_exists}
  @impl true
  def get_transaction_chain(address) when is_binary(address) do
    impl().get_transaction_chain(address)
  end

  @spec get_unspent_output_transactions(binary()) ::
          {:ok, list(Transaction.validated())} | {:error, :unspent_outputs_not_exists}
  @impl true
  def get_unspent_output_transactions(address) do
    impl().get_unspent_output_transactions(address)
  end

  @spec get_last_node_shared_secrets_transaction() ::
          {:ok, Transaction.validated()} | {:error, :transaction_not_exists}
  @impl true
  def get_last_node_shared_secrets_transaction() do
    impl().get_last_node_shared_secrets_transaction()
  end

  @spec store_transaction_chain(list(Transaction.validated())) :: :ok
  @impl true
  def store_transaction_chain(txs) when is_list(txs) do
    impl().store_transaction_chain(txs)
  end

  @spec store_transaction(Transaction.t()) :: :ok
  @impl true
  def store_transaction(tx = %Transaction{}) do
    impl().store_transaction(tx)
  end

  @spec list_transactions() :: list(Transaction.validated())
  @impl true
  def list_transactions() do
    impl().list_transactions()
  end

  @impl true
  @spec node_transactions() :: list(Transaction.validated())
  def node_transactions() do
    impl().node_transactions()
  end

  defp impl() do
    Application.get_env(:uniris_chain, :store, __MODULE__.FileImpl)
  end
end
