defmodule ArchEthic.BeaconChain.SubsetTest do
  use ArchEthicCase, async: false
  alias ArchEthic.BeaconChain

  alias ArchEthic.BeaconChain.Slot
  alias ArchEthic.BeaconChain.Slot.EndOfNodeSync
  alias ArchEthic.BeaconChain.Slot.TransactionSummary
  alias ArchEthic.BeaconChain.SlotTimer
  alias ArchEthic.BeaconChain.SummaryTimer

  alias ArchEthic.BeaconChain.Subset

  alias ArchEthic.Crypto

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.NewBeaconTransaction
  alias ArchEthic.P2P.Message.Ok
  alias ArchEthic.P2P.Message.Ping
  alias ArchEthic.P2P.Node

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData

  import Mox

  setup do
    start_supervised!({SummaryTimer, interval: "0 0 * * * *"})
    start_supervised!({SlotTimer, interval: "0 * * * * *"})
    pid = start_supervised!({Subset, subset: <<0>>})
    {:ok, subset: <<0>>, pid: pid}
  end

  # test "add_transaction_summary/2 should publish a transaction into the next beacon block", %{
  #   subset: subset,
  #   pid: pid
  # } do
  #   tx_time = DateTime.utc_now()
  #   tx_address = :crypto.strong_rand_bytes(32)

  #   Subset.add_transaction_summary(subset, %TransactionSummary{
  #     address: tx_address,
  #     timestamp: tx_time,
  #     type: :node
  #   })

  #   assert %{
  #            current_slot: %Slot{
  #              transaction_summaries: [%TransactionSummary{address: ^tx_address}]
  #            }
  #          } = :sys.get_state(pid)
  # end

  test "add_end_of_node_sync/2 should insert end of node synchronization in the beacon slot", %{
    subset: subset,
    pid: pid
  } do
    public_key = :crypto.strong_rand_bytes(32)

    :ok = Subset.add_end_of_node_sync(subset, %EndOfNodeSync{public_key: public_key})

    assert %{
             current_slot: %Slot{
               end_of_node_synchronizations: [%EndOfNodeSync{public_key: ^public_key}]
             }
           } = :sys.get_state(pid)
  end

  describe "handle_info/1" do
    test "new transaction summary is added to the slot and include the storage node confirmation",
         %{pid: pid} do
      tx_time = DateTime.utc_now()
      tx_address = :crypto.strong_rand_bytes(32)

      tx_summary = %TransactionSummary{
        address: tx_address,
        timestamp: tx_time,
        type: :node
      }

      sig = Crypto.sign_with_last_node_key(TransactionSummary.serialize(tx_summary))
      node_public_key = Crypto.last_node_public_key()

      send(pid, {:new_transaction_summary, tx_summary, node_public_key, sig})

      assert %{
               current_slot: %Slot{
                 transaction_summaries: [
                   %TransactionSummary{
                     address: ^tx_address,
                     confirmations: [{^node_public_key, ^sig}]
                   }
                 ]
               }
             } = :sys.get_state(pid)
    end

    test "new transaction summary's confirmation added to the slot",
         %{pid: pid} do
      tx_time = DateTime.utc_now()
      tx_address = :crypto.strong_rand_bytes(32)

      tx_summary = %TransactionSummary{
        address: tx_address,
        timestamp: tx_time,
        type: :node
      }

      tx_summary_payload = TransactionSummary.serialize(tx_summary)

      sig1 = Crypto.sign_with_last_node_key(tx_summary_payload)
      node1_public_key = Crypto.last_node_public_key()

      {node2_public_key, node2_private_key} = Crypto.generate_deterministic_keypair("node2")
      sig2 = Crypto.sign(tx_summary_payload, node2_private_key)

      send(pid, {:new_transaction_summary, tx_summary, node1_public_key, sig1})
      send(pid, {:new_transaction_summary, tx_summary, node2_public_key, sig2})

      assert %{
               current_slot: %Slot{
                 transaction_summaries: [
                   %TransactionSummary{
                     address: ^tx_address,
                     confirmations: confirmations
                   }
                 ]
               }
             } = :sys.get_state(pid)

      confirmed_public_keys =
        Enum.map(
          confirmations,
          &elem(&1, 0)
        )

      assert Enum.all?(confirmed_public_keys, &(&1 in [node1_public_key, node2_public_key]))
    end

    test "new slot is created when receive a :create_slot message", %{pid: pid} do
      tx_time = DateTime.utc_now()
      tx_address = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        geo_patch: "AAA",
        network_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        last_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        geo_patch: "AAA",
        network_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      tx_summary = %TransactionSummary{
        address: tx_address,
        timestamp: tx_time,
        type: :keychain,
        movements_addresses: [
          <<0, 109, 2, 63, 124, 238, 101, 213, 214, 64, 58, 218, 10, 35, 62, 202, 12, 64, 11, 232,
            210, 105, 102, 193, 193, 24, 54, 42, 200, 226, 13, 38, 69>>,
          <<0, 8, 253, 201, 142, 182, 78, 169, 132, 29, 19, 74, 3, 142, 207, 219, 127, 147, 40,
            24, 44, 170, 214, 171, 224, 29, 177, 205, 226, 88, 62, 248, 84>>
        ]
      }

      tx_summary_payload = TransactionSummary.serialize(tx_summary)

      sig1 = Crypto.sign_with_last_node_key(tx_summary_payload)
      node1_public_key = Crypto.last_node_public_key()

      {node2_public_key, node2_private_key} = Crypto.generate_deterministic_keypair("node2")
      sig2 = Crypto.sign(tx_summary_payload, node2_private_key)

      send(pid, {:new_transaction_summary, tx_summary, node1_public_key, sig1})

      me = self()

      MockClient
      |> stub(:send_message, fn
        _, %NewBeaconTransaction{transaction: tx}, _ ->
          send(me, {:beacon_tx, tx})
          {:ok, %Ok{}}

        _, %Ping{}, _ ->
          Process.sleep(10)
          {:ok, %Ok{}}
      end)

      Process.sleep(200)

      send(pid, {:create_slot, DateTime.utc_now()})

      assert_receive {:beacon_tx,
                      %Transaction{type: :beacon, data: %TransactionData{content: content}}}

      assert {%Slot{
                transaction_summaries: [
                  %TransactionSummary{address: ^tx_address, confirmations: [{_, _}, {_, _}]}
                ]
              }, _} = Slot.deserialize(content)
    end

    # test "new summary is created when the slot time is the summary time", %{
    #   subset: subset,
    #   pid: pid
    # } do
    #   tx_time = DateTime.utc_now()
    #   tx_address = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

    #   P2P.add_and_connect_node(%Node{
    #     ip: {127, 0, 0, 1},
    #     port: 3000,
    #     first_public_key:
    #       <<0::8, 0::8, subset::binary-size(1), :crypto.strong_rand_bytes(31)::binary>>,
    #     last_public_key:
    #       <<0::8, 0::8, subset::binary-size(1), :crypto.strong_rand_bytes(31)::binary>>,
    #     geo_patch: "AAA",
    #     network_patch: "AAA",
    #     available?: true,
    #     authorized?: true,
    #     authorization_date: ~U[2020-09-01 00:00:00Z]
    #   })

    #   P2P.add_and_connect_node(%Node{
    #     ip: {127, 0, 0, 1},
    #     port: 3000,
    #     first_public_key:
    #       <<0::8, 0::8, subset::binary-size(1), :crypto.strong_rand_bytes(31)::binary>>,
    #     last_public_key:
    #       <<0::8, 0::8, subset::binary-size(1), :crypto.strong_rand_bytes(31)::binary>>,
    #     geo_patch: "AAA",
    #     network_patch: "AAA",
    #     available?: true,
    #     authorized?: true,
    #     authorization_date: ~U[2020-09-01 00:00:00Z]
    #   })

    #   tx_summary = %TransactionSummary{
    #     address: tx_address,
    #     timestamp: tx_time,
    #     type: :keychain,
    #     movements_addresses: [
    #       <<0, 109, 2, 63, 124, 238, 101, 213, 214, 64, 58, 218, 10, 35, 62, 202, 12, 64, 11, 232,
    #         210, 105, 102, 193, 193, 24, 54, 42, 200, 226, 13, 38, 69>>,
    #       <<0, 8, 253, 201, 142, 182, 78, 169, 132, 29, 19, 74, 3, 142, 207, 219, 127, 147, 40,
    #         24, 44, 170, 214, 171, 224, 29, 177, 205, 226, 88, 62, 248, 84>>
    #     ]
    #   }

    #   Subset.add_transaction_summary(subset, tx_summary)

    #   MockClient
    #   |> stub(:send_message, fn
    #     _, %NewBeaconTransaction{transaction: tx}, _ ->
    #       send(self(), {:beacon_tx, tx})
    #       {:ok, %Ok{}}

    #     _, %Ping{}, _ ->
    #       Process.sleep(10)
    #       {:ok, %Ok{}}
    #   end)

    #   MockDB
    #   |> stub(:write_transaction, fn %Transaction{
    #                                    type: :beacon,
    #                                    data: %TransactionData{content: content}
    #                                  },
    #                                  _ ->
    #     {%Slot{
    #        subset: ^subset,
    #        p2p_view: %{
    #          availabilities: <<1::1, 1::1>>,
    #          network_stats: [%{latency: 0}, %{latency: 0}]
    #        }
    #      }, _} = Slot.deserialize(content)

    #     :ok
    #   end)

    #   send(pid, {:create_slot, ~U[2020-10-01 00:00:00Z]})
    #   Process.sleep(500)
    # end
  end

  test "subscribed nodes are being getting subscribed & added to beacon pool directly via subset",
       %{
         subset: subset,
         pid: pid
       } do
    public_key1 = :crypto.strong_rand_bytes(32)
    Subset.subscribe_for_beacon_updates(subset, public_key1)

    assert %{subscribed_nodes: [^public_key1]} = :sys.get_state(pid)
    assert [^public_key1] = Map.get(:sys.get_state(pid), :subscribed_nodes)

    public_key2 = :crypto.strong_rand_bytes(32)
    Subset.subscribe_for_beacon_updates(subset, public_key2)

    assert %{subscribed_nodes: [^public_key2, ^public_key1]} = :sys.get_state(pid)
  end

  test "subscribed nodes are being getting subscribed & added to beacon pool via Beacon chain", %{
    subset: subset,
    pid: pid
  } do
    first_public_key = :crypto.strong_rand_bytes(32)

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: first_public_key,
      last_public_key:
        <<0::8, 0::8, subset::binary-size(1), :crypto.strong_rand_bytes(31)::binary>>,
      geo_patch: "AAA",
      network_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: ~U[2020-09-01 00:00:00Z]
    })

    BeaconChain.subscribe_for_beacon_updates(subset, first_public_key)

    assert [^first_public_key] = Map.get(:sys.get_state(pid), :subscribed_nodes)
  end
end
