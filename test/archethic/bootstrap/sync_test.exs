defmodule ArchEthic.Bootstrap.SyncTest do
  use ArchEthicCase, async: false

  alias ArchEthic.Account

  alias ArchEthic.BeaconChain
  alias ArchEthic.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias ArchEthic.BeaconChain.Subset, as: BeaconSubset

  alias ArchEthic.Bootstrap.Sync

  alias ArchEthic.Crypto

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.EncryptedStorageNonce
  alias ArchEthic.P2P.Message.GetLastTransactionAddress
  alias ArchEthic.P2P.Message.GetStorageNonce
  alias ArchEthic.P2P.Message.GetTransactionChain
  alias ArchEthic.P2P.Message.GetUnspentOutputs
  alias ArchEthic.P2P.Message.LastTransactionAddress
  alias ArchEthic.P2P.Message.ListNodes
  alias ArchEthic.P2P.Message.NodeList
  alias ArchEthic.P2P.Message.NotifyEndOfNodeSync
  alias ArchEthic.P2P.Message.Ok
  alias ArchEthic.P2P.Message.TransactionList
  alias ArchEthic.P2P.Message.UnspentOutputList
  alias ArchEthic.P2P.Node

  alias ArchEthic.SharedSecrets.NodeRenewalScheduler

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.CrossValidationStamp
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Keys

  doctest Sync

  @moduletag :capture_log

  import Mox

  setup do
    MockClient
    |> stub(:send_message, fn
      _, %GetLastTransactionAddress{address: address} ->
        %LastTransactionAddress{address: address}

      _, %GetUnspentOutputs{} ->
        {:ok, %UnspentOutputList{unspent_outputs: []}}

      _, %GetTransactionChain{} ->
        {:ok, %TransactionList{transactions: []}}
    end)

    :ok
  end

  describe "should_initialize_network?/1" do
    test "should return true when the network has not been deployed and it's the first bootstrapping seed" do
      assert true == Sync.should_initialize_network?([])
    end

    test "should return false when the network has been initialized" do
      tx = Transaction.new(:node_shared_secrets, %TransactionData{})

      stamp = %ValidationStamp{
        timestamp: DateTime.utc_now(),
        proof_of_work: "",
        proof_of_integrity: "",
        ledger_operations: %LedgerOperations{},
        signature: ""
      }

      cross_stamp = %CrossValidationStamp{}

      :ok =
        TransactionChain.write_transaction(%{
          tx
          | validation_stamp: stamp,
            cross_validation_stamps: [cross_stamp]
        })

      assert false ==
               Sync.should_initialize_network?([
                 %Node{first_public_key: "key1"},
                 %Node{first_public_key: "key1"}
               ])
    end
  end

  describe "require_update?/4" do
    test "should return false when only a node is involved in the network" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        transport: :tcp
      })

      assert false == Sync.require_update?({193, 101, 10, 202}, 3000, :tcp, DateTime.utc_now())
    end

    test "should return true when the node ip change" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        transport: :tcp
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3050,
        first_public_key: "other_node_key",
        last_public_key: "other_node_key",
        transport: :tcp
      })

      assert Sync.require_update?({193, 101, 10, 202}, 3000, :tcp, DateTime.utc_now())
    end

    test "should return true when the node port change" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        transport: :tcp
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3050,
        first_public_key: "other_node_key",
        last_public_key: "other_node_key",
        transport: :tcp
      })

      assert Sync.require_update?({127, 0, 0, 1}, 3010, :tcp, DateTime.utc_now())
    end

    test "should return true when the last date of sync diff is greater than 3 seconds" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        transport: :tcp
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3050,
        first_public_key: "other_node_key",
        last_public_key: "other_node_key",
        transport: :tcp
      })

      assert Sync.require_update?(
               {127, 0, 0, 1},
               3000,
               :tcp,
               DateTime.utc_now()
               |> DateTime.add(-10)
             )
    end

    test "should return true when the transport change" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        transport: :tcp
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3050,
        first_public_key: "other_node_key",
        last_public_key: "other_node_key",
        transport: :tcp
      })

      assert true == Sync.require_update?({193, 101, 10, 202}, 3000, :sctp, DateTime.utc_now())
    end
  end

  describe "initialize_network/2" do
    setup do
      start_supervised!({BeaconSlotTimer, interval: "0 * * * * * *"})
      Enum.each(BeaconChain.list_subsets(), &BeaconSubset.start_link(subset: &1))
      start_supervised!({NodeRenewalScheduler, interval: "0 * * * * *"})

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        transport: MockTransport,
        geo_patch: "AAA",
        network_patch: "AAA"
      })

      :ok
    end

    test "should initiate storage nonce, first node transaction, node shared secrets and genesis wallets" do
      {:ok, daily_nonce_key} =
        Agent.start_link(fn ->
          Application.get_env(:archethic, ArchEthic.Bootstrap.NetworkInit)
          |> Keyword.fetch!(:genesis_daily_nonce_seed)
          |> Crypto.generate_deterministic_keypair()
          |> elem(1)
        end)

      MockDB
      |> stub(:chain_size, fn _ -> 1 end)
      |> stub(:write_transaction_chain, fn
        [
          %Transaction{
            type: :node_shared_secrets,
            data: %TransactionData{keys: %Keys{authorized_keys: [keys], secrets: [secret]}}
          }
        ] ->
          encrypted_key = Map.get(keys, Crypto.last_node_public_key())
          aes_key = Crypto.ec_decrypt_with_last_node_key!(encrypted_key)
          <<encrypted_daily_nonce_seed::binary-size(60), _::binary>> = secret
          daily_nonce_seed = Crypto.aes_decrypt!(encrypted_daily_nonce_seed, aes_key)

          Agent.update(daily_nonce_key, fn _ ->
            daily_nonce_seed |> Crypto.generate_deterministic_keypair() |> elem(1)
          end)

        _ ->
          :ok
      end)

      MockCrypto
      |> stub(:sign_with_daily_nonce_key, fn data, _ ->
        Crypto.sign(data, Agent.get(daily_nonce_key, & &1))
      end)

      node_tx =
        Transaction.new(:node, %TransactionData{
          content:
            <<127, 0, 0, 1, 3000::16, 1, 0, :crypto.strong_rand_bytes(32)::binary, 64::16,
              :crypto.strong_rand_bytes(64)::binary>>
        })

      :ok = Sync.initialize_network(node_tx)

      assert :persistent_term.get(:storage_nonce) != nil

      assert %Node{authorized?: true} = P2P.get_node_info()
      assert 1 == Crypto.number_of_node_shared_secrets_keys()

      Application.get_env(:archethic, ArchEthic.Bootstrap.NetworkInit)[:genesis_pools]
      |> Enum.each(fn %{address: address, amount: amount} ->
        assert %{uco: amount, nft: %{}} == Account.get_balance(address)
      end)
    end
  end

  test "load_node_list/1 should request node list from the closest nodes" do
    node = %Node{
      ip: {80, 10, 101, 202},
      port: 4390,
      first_public_key: "key1",
      last_public_key: "key1"
    }

    :ok = P2P.add_and_connect_node(node)

    MockClient
    |> stub(:send_message, fn
      _, %ListNodes{} ->
        {:ok,
         %NodeList{
           nodes: [
             %Node{
               ip: {127, 0, 0, 1},
               port: 3000,
               first_public_key: "key2",
               last_public_key: "key2"
             }
           ]
         }}
    end)

    assert :ok = Sync.load_node_list([node])

    assert [
             node,
             %Node{
               ip: {127, 0, 0, 1},
               port: 3000,
               first_public_key: "key2",
               last_public_key: "key2"
             }
           ] == P2P.list_nodes()
  end

  test "load_storage_nonce/1 should fetch the storage nonce, decrypt it with the node key" do
    node = %Node{
      ip: {80, 10, 101, 202},
      port: 4390,
      first_public_key: "key1",
      last_public_key: "key1"
    }

    :ok = P2P.add_and_connect_node(node)

    MockClient
    |> expect(:send_message, fn _, %GetStorageNonce{public_key: public_key} ->
      encrypted_nonce = Crypto.ec_encrypt("fake_storage_nonce", public_key)
      {:ok, %EncryptedStorageNonce{digest: encrypted_nonce}}
    end)

    assert :ok = Sync.load_storage_nonce([node])
    assert "fake_storage_nonce" = :persistent_term.get(:storage_nonce)
  end

  test "publish_end_of_sync/0 should notify the network the node have finished its synchronization" do
    BeaconSlotTimer.start_link(interval: "0 * * * * *")

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: :crypto.strong_rand_bytes(32),
      last_public_key: :crypto.strong_rand_bytes(32),
      available?: true,
      geo_patch: "AAA",
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    me = self()

    MockClient
    |> stub(:send_message, fn _, %NotifyEndOfNodeSync{} ->
      send(me, :end_of_sync)
      {:ok, %Ok{}}
    end)

    assert :ok = Sync.publish_end_of_sync()
    assert_receive :end_of_sync
  end
end
