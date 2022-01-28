defmodule ArchEthic.BeaconChain.Slot do
  @moduledoc """
  Represent a beacon chain slot generated after each synchronization interval
  with the transaction stored and nodes updates
  """
  alias ArchEthic.BeaconChain.ReplicationAttestation
  alias __MODULE__.EndOfNodeSync

  alias ArchEthic.BeaconChain.Subset.P2PSampling

  alias ArchEthic.BeaconChain.SummaryTimer

  alias ArchEthic.Election

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node

  alias ArchEthic.TransactionChain.TransactionSummary

  @type net_stats :: list(%{latency: non_neg_integer()})

  defstruct [
    :subset,
    :slot_time,
    transaction_attestations: [],
    end_of_node_synchronizations: [],
    p2p_view: %{
      availabilities: <<>>,
      network_stats: []
    },
    involved_nodes: <<>>
  ]

  @type t :: %__MODULE__{
          subset: binary(),
          slot_time: DateTime.t(),
          transaction_attestations: list(ReplicationAttestation.t()),
          end_of_node_synchronizations: list(EndOfNodeSync.t()),
          p2p_view: %{
            availabilities: bitstring(),
            network_stats: net_stats()
          },
          involved_nodes: bitstring()
        }

  @doc """
  Add a transaction attestation confirmation to the slot

  If the the transaction summary doesn't exist it will be added to the list of summaries with the first confirmation.

  If the transaction summary already exists, it will append the confirmation node with the node public key and its signature.

  ## Examples

    Add the first confirmation

      iex> %Slot{}
      ...> |> Slot.add_transaction_attestation(%ReplicationAttestation{
      ...>     transaction_summary: %TransactionSummary{
      ...>       address:  <<0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
      ...>         168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247>>,
      ...>       timestamp: ~U[2020-06-25 15:11:53Z],
      ...>       type: :transfer,
      ...>       movements_addresses: [
      ...>           <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...>           99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>
      ...>       ],
      ...>     },
      ...>     confirmations: [{0, <<185, 37, 172, 79, 189, 197, 94, 202, 41, 160, 222, 127, 227, 180, 133, 62, 76,
      ...>      29, 230, 10, 100, 79, 47, 49, 139, 117, 0, 64, 89, 229, 228, 214, 6, 49, 119,
      ...>      32, 180, 47, 189, 143, 239, 156, 56, 234, 236, 128, 17, 79, 236, 211, 124,
      ...>      158, 142, 23, 151, 43, 50, 153, 52, 195, 144, 226, 247, 65>>}],
      ...>     node_public_key: <<0, 0, 248, 179, 223, 134, 135, 41, 111, 47, 239, 24, 25, 70, 58, 34, 214, 46,
      ...>       40, 244, 92, 112, 195, 129, 234, 199, 155, 94, 159, 232, 208, 246, 71, 68>>,
      ...>     signature: <<185, 37, 172, 79, 189, 197, 94, 202, 41, 160, 222, 127, 227, 180, 133, 62, 76,
      ...>       29, 230, 10, 100, 79, 47, 49, 139, 117, 0, 64, 89, 229, 228, 214, 6, 49, 119,
      ...>       32, 180, 47, 189, 143, 239, 156, 56, 234, 236, 128, 17, 79, 236, 211, 124,
      ...>       158, 142, 23, 151, 43, 50, 153, 52, 195, 144, 226, 247, 65>>
      ...> })
      %Slot{
        transaction_attestations: [
          %ReplicationAttestation{
            transaction_summary: %TransactionSummary{
              address:  <<0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
                 168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247>>,
              timestamp: ~U[2020-06-25 15:11:53Z],
              type: :transfer,
              movements_addresses: [
                  <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
                  99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>
              ]
            },
            confirmations: [
              {
                0,
                <<185, 37, 172, 79, 189, 197, 94, 202, 41, 160, 222, 127, 227, 180, 133, 62, 76,
                  29, 230, 10, 100, 79, 47, 49, 139, 117, 0, 64, 89, 229, 228, 214, 6, 49, 119,
                  32, 180, 47, 189, 143, 239, 156, 56, 234, 236, 128, 17, 79, 236, 211, 124,
                  158, 142, 23, 151, 43, 50, 153, 52, 195, 144, 226, 247, 65>>
              }
            ]
          }
        ]
      }

    Append confirmation

      # iex> %Slot{transaction_attestations: [
      # ...>   %ReplicationAttestation{
      # ...>    transaction_summary: %TransactionSummary{
      # ...>      address:  <<0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
      # ...>         168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247>>,
      # ...>      timestamp: ~U[2020-06-25 15:11:53Z],
      # ...>      type: :transfer,
      # ...>      movements_addresses: [
      # ...>          <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      # ...>          99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>
      # ...>      ]
      # ...>    },
      # ...>    node_public_key: <<0, 0, 248, 179, 223, 134, 135, 41, 111, 47, 239, 24, 25, 70, 58, 34, 214, 46,
      # ...>      0, 244, 92, 112, 195, 129, 234, 199, 155, 94, 159, 232, 208, 246, 71, 68>>,
      # ...>    signature: <<185, 37, 172, 79, 189, 197, 94, 202, 41, 160, 222, 127, 227, 180, 133, 62, 76,
      # ...>      29, 230, 10, 100, 79, 47, 49, 139, 117, 0, 64, 89, 229, 228, 214, 6, 49, 119,
      # ...>      32, 180, 47, 189, 143, 239, 156, 56, 234, 236, 128, 17, 79, 236, 211, 124,
      # ...>      158, 142, 23, 151, 43, 50, 153, 52, 195, 144, 226, 247, 65>>,
      # ...>    confirmations: [{0, <<185, 37, 172, 79, 189, 197, 94, 202, 41, 160, 222, 127, 227, 180, 133, 62, 76,
      # ...>      29, 230, 10, 100, 79, 47, 49, 139, 117, 0, 64, 89, 229, 228, 214, 6, 49, 119,
      # ...>      32, 180, 47, 189, 143, 239, 156, 56, 234, 236, 128, 17, 79, 236, 211, 124,
      # ...>      158, 142, 23, 151, 43, 50, 153, 52, 195, 144, 226, 247, 65>>
      # ...>    }]
      # ...>  }
      # ...> ]}
      # ...> |> Slot.add_transaction_attestation(%ReplicationAttestation{
      # ...>   transaction_summary: %TransactionSummary{
      # ...>      address:  <<0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
      # ...>     168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247>>,
      # ...>      timestamp: ~U[2020-06-25 15:11:53Z],
      # ...>      type: :transfer,
      # ...>      movements_addresses: [
      # ...>          <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      # ...>          99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>
      # ...>      ],
      # ...>    },
      # ...>    confirmations: [{1, <<89, 98, 246, 6, 202, 116, 247, 88, 69, 148, 188, 173, 34, 0, 194, 108, 169,
      # ...>      155, 63, 197, 200, 6, 31, 148, 57, 152, 195, 154, 181, 14, 77, 9, 161, 38,
      # ...>      239, 151, 241, 35, 93, 254, 65, 201, 152, 57, 187, 225, 86, 235, 56, 206, 134,
      # ...>      141, 174, 141, 29, 28, 173, 17, 4, 78, 129, 33, 68, 4>>}],
      # ...>    node_public_key: <<0, 0, 59, 221, 196, 126, 81, 247, 229, 226, 54, 95, 242, 18, 93, 235, 210, 80,
      # ...>      165, 121, 185, 196, 147, 248, 166, 246, 16, 15, 117, 252, 208, 182, 250, 194>>,
      # ...>    signature: <<89, 98, 246, 6, 202, 116, 247, 88, 69, 148, 188, 173, 34, 0, 194, 108, 169,
      # ...>      155, 63, 197, 200, 6, 31, 148, 57, 152, 195, 154, 181, 14, 77, 9, 161, 38,
      # ...>      239, 151, 241, 35, 93, 254, 65, 201, 152, 57, 187, 225, 86, 235, 56, 206, 134,
      # ...>      141, 174, 141, 29, 28, 173, 17, 4, 78, 129, 33, 68, 4>>
      # ...> })
      # %Slot{
      #   transaction_attestations: [
      #     %ReplicationAttestation{
      #       transaction_summary: %TransactionSummary{
      #         address:  <<0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
      #            168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247>>,
      #         timestamp: ~U[2020-06-25 15:11:53Z],
      #         type: :transfer,
      #         movements_addresses: [
      #             <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      #             99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>
      #         ]
      #       },
      #       confirmations: [
      #         {
      #           1,
      #           <<89, 98, 246, 6, 202, 116, 247, 88, 69, 148, 188, 173, 34, 0, 194, 108, 169,
      #             155, 63, 197, 200, 6, 31, 148, 57, 152, 195, 154, 181, 14, 77, 9, 161, 38,
      #             239, 151, 241, 35, 93, 254, 65, 201, 152, 57, 187, 225, 86, 235, 56, 206, 134,
      #             141, 174, 141, 29, 28, 173, 17, 4, 78, 129, 33, 68, 4>>
      #         },
      #         {
      #           0,
      #           <<185, 37, 172, 79, 189, 197, 94, 202, 41, 160, 222, 127, 227, 180, 133, 62, 76,
      #             29, 230, 10, 100, 79, 47, 49, 139, 117, 0, 64, 89, 229, 228, 214, 6, 49, 119,
      #             32, 180, 47, 189, 143, 239, 156, 56, 234, 236, 128, 17, 79, 236, 211, 124,
      #             158, 142, 23, 151, 43, 50, 153, 52, 195, 144, 226, 247, 65>>
      #         }
      #       ]
      #     }
      #   ]
      # }
  """
  @spec add_transaction_attestation(
          __MODULE__.t(),
          ReplicationAttestation.t()
        ) ::
          __MODULE__.t()
  def add_transaction_attestation(
        slot = %__MODULE__{transaction_attestations: transaction_attestations},
        attestation = %ReplicationAttestation{
          transaction_summary: %TransactionSummary{address: tx_address},
          confirmations: confirmations
        }
      ) do
    case Enum.find_index(
           transaction_attestations,
           &(&1.transaction_summary.address == tx_address)
         ) do
      nil ->
        %{slot | transaction_attestations: [attestation]}

      index ->
        add_transaction_attestation_confirmations(slot, index, confirmations)
    end
  end

  defp add_transaction_attestation_confirmations(slot, index, confirmations) do
    Map.update!(slot, :transaction_attestations, fn attestations ->
      List.update_at(attestations, index, fn attestation ->
        Map.update!(attestation, :confirmations, &(&1 ++ confirmations))
      end)
    end)
  end

  @doc """
  Add an end of node synchronization to the slot

  ## Examples

      iex> %Slot{}
      ...> |> Slot.add_end_of_node_sync(%EndOfNodeSync{
      ...>   public_key:  <<0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
      ...>     168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247>>,
      ...>   timestamp: ~U[2020-06-25 15:11:53Z]
      ...> })
      %Slot{
        end_of_node_synchronizations: [
          %EndOfNodeSync{
            public_key:  <<0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
               168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247>>,
            timestamp: ~U[2020-06-25 15:11:53Z]
          }
        ]
      }
  """
  def add_end_of_node_sync(slot = %__MODULE__{}, end_of_sync = %EndOfNodeSync{}) do
    Map.update!(
      slot,
      :end_of_node_synchronizations,
      &(&1 ++ [end_of_sync])
    )
  end

  @doc """
  Add the p2p views to the beacon slot

  ## Examples

      iex> %Slot{
      ...>    p2p_view: %{ availabilities: <<0::1, 0::1, 0::1>>, network_stats: [] }
      ...>  }
      ...> |> Slot.add_p2p_view([{true, 10 }, {false, 0 }, {true, 50 }])
      %Slot{
        p2p_view: %{
          availabilities: <<1::1, 0::1, 1::1>>,
          network_stats: [
            %{ latency: 10 },
            %{ latency: 0},
            %{ latency: 50}
          ]
        }
      }
  """
  @spec add_p2p_view(t(), list(P2PSampling.p2p_view())) :: t()
  def add_p2p_view(slot = %__MODULE__{}, p2p_views) do
    %{availabilities: availabilities, network_stats: network_stats} =
      p2p_views
      |> Enum.reduce(%{availabilities: [], network_stats: []}, fn
        {true, latency}, acc ->
          acc
          |> Map.update!(:availabilities, &(&1 ++ [<<1::1>>]))
          |> Map.update!(:network_stats, &(&1 ++ [%{latency: latency}]))

        {false, _}, acc ->
          acc
          |> Map.update!(:availabilities, &(&1 ++ [<<0::1>>]))
          |> Map.update!(:network_stats, &(&1 ++ [%{latency: 0}]))
      end)

    %{
      slot
      | p2p_view: %{
          availabilities: :erlang.list_to_bitstring(availabilities),
          network_stats: network_stats
        }
    }
  end

  @doc """
  Serialize a BeaconSlot into a binary format

    ## Examples

        iex> %Slot{
        ...>    subset: <<0>>,
        ...>    slot_time: ~U[2021-01-20 10:10:00Z],
        ...>    transaction_attestations: [
        ...>      %ReplicationAttestation {
        ...>        transaction_summary: %TransactionSummary{
        ...>          address: <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
        ...>            99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
        ...>          timestamp: ~U[2020-06-25 15:11:53Z],
        ...>          type: :transfer,
        ...>          movements_addresses: []
        ...>        },
        ...>        node_public_key: <<0, 0, 14, 145, 193, 67, 99, 230, 176, 186, 71, 162, 165, 13, 80, 16, 23, 82,
        ...>          231, 17, 187, 90, 119, 102, 221, 95, 52, 111, 122, 128, 129, 33, 102, 143>>,
        ...>        signature: <<193, 87, 217, 142, 28, 6, 40, 1, 229, 40, 225, 83, 164, 92, 41, 222, 226, 3,
        ...>          32, 177, 234, 96, 211, 164, 224, 40, 236, 234, 252, 150, 89, 82, 12, 234, 121,
        ...>          59, 120, 109, 78, 152, 41, 241, 204, 15, 11, 18, 83, 34, 198, 253, 43, 243,
        ...>          28, 109, 140, 237, 169, 255, 42, 77, 244, 0, 90, 224>>,
        ...>        confirmations: [{0, <<129, 204, 107, 81, 235, 88, 234, 207, 125, 1, 208, 227, 239, 175, 78, 217,
        ...>          100, 172, 67, 228, 131, 42, 177, 200, 54, 225, 34, 241, 35, 226, 108, 138,
        ...>          201, 2, 32, 75, 92, 49, 194, 42, 113, 154, 20, 43, 216, 176, 11, 159, 188,
        ...>          119, 6, 8, 48, 201, 244, 138, 99, 52, 22, 1, 97, 123, 140, 195>>}]
        ...>      }
        ...>    ],
        ...>    end_of_node_synchronizations: [ %EndOfNodeSync{
        ...>      public_key: <<0, 0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
        ...>      100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241>>,
        ...>      timestamp: ~U[2020-06-25 15:11:53Z]
        ...>    }],
        ...>    p2p_view: %{
        ...>      availabilities: <<1::1, 0::1>>,
        ...>      network_stats: [
        ...>         %{ latency: 10},
        ...>         %{ latency: 0}
        ...>      ]
        ...>    },
        ...>    involved_nodes: <<0::1, 1::1, 0::1, 0::1>>
        ...>  } |> Slot.serialize()
        <<
        # Subset
        0,
        # Slot time
        96, 8, 1, 120,
        # Nb transaction attestations
        0, 0, 0, 1,
        # Attestation version
        1,
        # Address
        0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
        99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12,
        # Timestamp
        0, 0, 1, 114, 236, 9, 2, 168,
        # Type (transfer)
        253,
        # Nb movements addresses
        0, 0,
        # Validator node public key
        0, 0, 14, 145, 193, 67, 99, 230, 176, 186, 71, 162, 165, 13, 80, 16, 23, 82,
        231, 17, 187, 90, 119, 102, 221, 95, 52, 111, 122, 128, 129, 33, 102, 143,
        # Signature size
        64,
        # Signature
        193, 87, 217, 142, 28, 6, 40, 1, 229, 40, 225, 83, 164, 92, 41, 222, 226, 3,
        32, 177, 234, 96, 211, 164, 224, 40, 236, 234, 252, 150, 89, 82, 12, 234, 121,
        59, 120, 109, 78, 152, 41, 241, 204, 15, 11, 18, 83, 34, 198, 253, 43, 243,
        28, 109, 140, 237, 169, 255, 42, 77, 244, 0, 90, 224,
        # Nb confirmations
        1,
        # Replication node position
        0,
        # Signature size
        64,
        # Replication node signature
        129, 204, 107, 81, 235, 88, 234, 207, 125, 1, 208, 227, 239, 175, 78, 217,
        100, 172, 67, 228, 131, 42, 177, 200, 54, 225, 34, 241, 35, 226, 108, 138,
        201, 2, 32, 75, 92, 49, 194, 42, 113, 154, 20, 43, 216, 176, 11, 159, 188,
        119, 6, 8, 48, 201, 244, 138, 99, 52, 22, 1, 97, 123, 140, 195,
        # Nb of node synchronizations
        0, 1,
        # Node public key
        0, 0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
        100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241,
        # Node readyness timestamp
        94, 244, 190, 185,
        # P2P view bitstring size
        0, 2,
        # P2P view availabilies
        1::1, 0::1,
        # P2P view network stats (1st node)
        10,
        # P2P view network stats (2nd node)
        0,
        # Size involved nodes bitstring
        4,
        # Involved nodes bitstring
        0::1, 1::1, 0::1, 0::1
        >>
  """
  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{
        subset: subset,
        slot_time: slot_time,
        transaction_attestations: transaction_attestations,
        end_of_node_synchronizations: end_of_node_synchronizations,
        p2p_view: %{
          availabilities: availabilities,
          network_stats: network_stats
        },
        involved_nodes: involved_nodes
      }) do
    transaction_attestations_bin =
      transaction_attestations
      |> Enum.map(&ReplicationAttestation.serialize/1)
      |> :erlang.list_to_binary()

    end_of_node_synchronizations_bin =
      end_of_node_synchronizations
      |> Enum.map(&EndOfNodeSync.serialize/1)
      |> :erlang.list_to_binary()

    net_stats_bin =
      network_stats
      |> Enum.map(fn %{latency: latency} -> <<latency::8>> end)
      |> :erlang.list_to_binary()

    <<subset::binary, DateTime.to_unix(slot_time)::32, length(transaction_attestations)::32,
      transaction_attestations_bin::binary, length(end_of_node_synchronizations)::16,
      end_of_node_synchronizations_bin::binary, bit_size(availabilities)::16,
      availabilities::bitstring, net_stats_bin::binary, bit_size(involved_nodes)::8,
      involved_nodes::bitstring>>
  end

  @doc """
  Deserialize an encoded BeaconSlot

  ## Examples

      iex> <<0, 96, 8, 1, 120, 0, 0, 0, 1,
      ...>  1, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...>  99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12,
      ...>  0, 0, 1, 114, 236, 9, 2, 168, 253, 0, 0,
      ...>  0, 0, 14, 145, 193, 67, 99, 230, 176, 186, 71, 162, 165, 13, 80, 16, 23, 82,
      ...>  231, 17, 187, 90, 119, 102, 221, 95, 52, 111, 122, 128, 129, 33, 102, 143,
      ...>  64, 193, 87, 217, 142, 28, 6, 40, 1, 229, 40, 225, 83, 164, 92, 41, 222, 226, 3,
      ...>  32, 177, 234, 96, 211, 164, 224, 40, 236, 234, 252, 150, 89, 82, 12, 234, 121,
      ...>  59, 120, 109, 78, 152, 41, 241, 204, 15, 11, 18, 83, 34, 198, 253, 43, 243,
      ...>  28, 109, 140, 237, 169, 255, 42, 77, 244, 0, 90, 224,
      ...>  1, 0, 64, 129, 204, 107, 81, 235, 88, 234, 207, 125, 1, 208, 227, 239, 175, 78, 217,
      ...>  100, 172, 67, 228, 131, 42, 177, 200, 54, 225, 34, 241, 35, 226, 108, 138,
      ...>  201, 2, 32, 75, 92, 49, 194, 42, 113, 154, 20, 43, 216, 176, 11, 159, 188,
      ...>  119, 6, 8, 48, 201, 244, 138, 99, 52, 22, 1, 97, 123, 140, 195,
      ...>  0, 1, 0, 0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
      ...>  100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241, 94, 244, 190, 185,
      ...>  0, 2, 1::1, 0::1, 10,
      ...>  0, 4, 0::1, 1::1, 0::1, 0::1>>
      ...> |> Slot.deserialize()
      {
        %Slot{
          subset: <<0>>,
          slot_time: ~U[2021-01-20 10:10:00Z],
          transaction_attestations: [
            %ReplicationAttestation{
              transaction_summary:  %TransactionSummary{
                address: <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
                  99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
                timestamp: ~U[2020-06-25 15:11:53.000Z],
                type: :transfer,
                movements_addresses: []
              },
              confirmations: [{0, <<129, 204, 107, 81, 235, 88, 234, 207, 125, 1, 208, 227, 239, 175, 78, 217,
                100, 172, 67, 228, 131, 42, 177, 200, 54, 225, 34, 241, 35, 226, 108, 138,
                201, 2, 32, 75, 92, 49, 194, 42, 113, 154, 20, 43, 216, 176, 11, 159, 188,
                119, 6, 8, 48, 201, 244, 138, 99, 52, 22, 1, 97, 123, 140, 195>>}],
              node_public_key: <<0, 0, 14, 145, 193, 67, 99, 230, 176, 186, 71, 162, 165, 13, 80, 16, 23, 82,
                231, 17, 187, 90, 119, 102, 221, 95, 52, 111, 122, 128, 129, 33, 102, 143>>,
              signature: <<193, 87, 217, 142, 28, 6, 40, 1, 229, 40, 225, 83, 164, 92, 41, 222, 226, 3,
                32, 177, 234, 96, 211, 164, 224, 40, 236, 234, 252, 150, 89, 82, 12, 234, 121,
                59, 120, 109, 78, 152, 41, 241, 204, 15, 11, 18, 83, 34, 198, 253, 43, 243,
                28, 109, 140, 237, 169, 255, 42, 77, 244, 0, 90, 224>>
            }
          ],
          end_of_node_synchronizations: [ %EndOfNodeSync{
            public_key: <<0, 0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
            100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241>>,
            timestamp: ~U[2020-06-25 15:11:53Z]
          }],
          p2p_view: %{
            availabilities: <<1::1, 0::1>>,
            network_stats: [
              %{ latency: 10},
              %{ latency: 0}
            ]
          },
          involved_nodes: <<0::1, 1::1, 0::1, 0::1>>
        },
        ""
      }
  """
  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(
        <<subset::8, slot_timestamp::32, nb_transaction_attestations::32, rest::bitstring>>
      ) do
    {tx_attestations, rest} = deserialize_tx_attestations(rest, nb_transaction_attestations, [])
    <<nb_end_of_sync::16, rest::bitstring>> = rest

    {end_of_node_synchronizations, rest} =
      deserialize_end_of_node_synchronizations(rest, nb_end_of_sync, [])

    <<p2p_view_size::16, availabilities::bitstring-size(p2p_view_size), rest::bitstring>> = rest

    {network_stats, rest} = deserialize_network_stats(rest, p2p_view_size, [])

    <<involved_nodes_size::8, involved_nodes::bitstring-size(involved_nodes_size),
      rest::bitstring>> = rest

    {
      %__MODULE__{
        subset: <<subset>>,
        slot_time: DateTime.from_unix!(slot_timestamp),
        transaction_attestations: tx_attestations,
        end_of_node_synchronizations: end_of_node_synchronizations,
        p2p_view: %{
          availabilities: availabilities,
          network_stats: network_stats
        },
        involved_nodes: involved_nodes
      },
      rest
    }
  end

  defp deserialize_tx_attestations(rest, 0, _acc), do: {[], rest}

  defp deserialize_tx_attestations(rest, nb_tx_attestations, acc)
       when length(acc) == nb_tx_attestations do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_tx_attestations(rest, nb_tx_attestations, acc) do
    {tx_attestation, rest} = ReplicationAttestation.deserialize(rest)
    deserialize_tx_attestations(rest, nb_tx_attestations, [tx_attestation | acc])
  end

  defp deserialize_end_of_node_synchronizations(rest, 0, _acc), do: {[], rest}

  defp deserialize_end_of_node_synchronizations(rest, nb_end_of_node_synchronizations, acc)
       when length(acc) == nb_end_of_node_synchronizations do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_end_of_node_synchronizations(rest, nb_end_of_node_synchronizations, acc) do
    {end_of_sync, rest} = EndOfNodeSync.deserialize(rest)

    deserialize_end_of_node_synchronizations(rest, nb_end_of_node_synchronizations, [
      end_of_sync | acc
    ])
  end

  defp deserialize_network_stats(rest, 0, _), do: {[], rest}

  defp deserialize_network_stats(rest, nb_nodes, acc) when nb_nodes == length(acc) do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_network_stats(<<latency::8, rest::bitstring>>, nb_nodes, acc) do
    deserialize_network_stats(rest, nb_nodes, [%{latency: latency} | acc])
  end

  @doc """
  Retrieve the nodes responsible to manage the slot processing
  """
  @spec involved_nodes(t()) :: list(Node.t())
  def involved_nodes(%__MODULE__{subset: subset, slot_time: slot_time}) do
    node_list =
      Enum.filter(
        P2P.authorized_nodes(),
        &(DateTime.compare(&1.authorization_date, slot_time) == :lt)
      )

    Election.beacon_storage_nodes(
      subset,
      slot_time,
      node_list,
      Election.get_storage_constraints()
    )
  end

  @doc """
  Retrieve the nodes responsible to manage the summary holding of the given slot
  """
  @spec summary_storage_nodes(t()) :: list(Node.t())
  def summary_storage_nodes(%__MODULE__{subset: subset, slot_time: slot_time}) do
    node_list =
      Enum.filter(
        P2P.authorized_nodes(),
        &(DateTime.compare(&1.authorization_date, slot_time) == :lt)
      )

    Election.beacon_storage_nodes(
      subset,
      SummaryTimer.next_summary(slot_time),
      node_list,
      Election.get_storage_constraints()
    )
  end

  @doc """
  Determines if the Slot is empty
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{
        transaction_attestations: [],
        end_of_node_synchronizations: [],
        p2p_view: %{availabilities: <<>>, network_stats: []}
      }),
      do: true

  def empty?(%__MODULE__{}), do: false
end
