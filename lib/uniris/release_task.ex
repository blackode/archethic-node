defmodule Uniris.ReleaseTask do
  @moduledoc """
  Task using in the release to send initial funds to the addresses of the onchain
  version of the website
  """

  alias Uniris.Crypto

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Ledger
  alias Uniris.TransactionChain.TransactionData.UCOLedger
  alias Uniris.TransactionChain.TransactionData.UCOLedger.Transfer

  # TODO: to remove once the Client UI developed
  def transfer_to_website_addresses(amount \\ 1.0) do
    seed = Base.decode16!("6CBF75F092278AA0751096CE85FE1E1F033FF50312B146DB336FAF861C8C4E09")

    Transaction.new(
      :transfer,
      %TransactionData{
        ledger: %Ledger{
          uco: %UCOLedger{
            transfers:
              Enum.map(website_seeds(), fn destination_seed ->
                {pub, _} =
                  Crypto.derive_keypair(destination_seed, get_last_index(destination_seed))

                %Transfer{to: Crypto.hash(pub), amount: amount}
              end)
          }
        }
      },
      seed,
      get_last_index(seed)
    )
    |> Uniris.send_new_transaction()
  end

  defp get_last_index(seed) do
    address =
      seed
      |> Crypto.derive_keypair(0)
      |> elem(0)
      |> Crypto.hash()

    case Uniris.get_last_transaction(address) do
      {:ok, %Transaction{address: address}} ->
        Uniris.get_transaction_chain_length(address)

      _ ->
        0
    end
  end

  defp website_seeds do
    [
      Crypto.hash("animate_seed"),
      Crypto.hash("bicon_seed"),
      Crypto.hash("bootstrap_css_seed"),
      Crypto.hash("bootstrap_js_seed"),
      Crypto.hash("fontawesome_seed"),
      Crypto.hash("carousel_seed"),
      Crypto.hash("jquery_seed"),
      Crypto.hash("magnificpopup_css_seed"),
      Crypto.hash("uniris_css_seed"),
      Crypto.hash("owlcarousel_css_seed"),
      Crypto.hash("owlcarousel_js_seed"),
      Crypto.hash("popper_seed"),
      Crypto.hash("wow_seed"),
      Crypto.hash("jquerycountdown_seed"),
      Crypto.hash("magnificpopup_js_seed"),
      Crypto.hash("particles_seed"),
      Crypto.hash("uniris_js_seed"),
      Crypto.hash("d3_seed"),
      Crypto.hash("d3queue_seed"),
      Crypto.hash("d3topojson_seed"),
      Crypto.hash("uniris_biometricanim_seed"),
      Crypto.hash("uniris_blockchainanim_seed"),
      Crypto.hash("formvalidator_seed"),
      Crypto.hash("world-110_seed"),
      Crypto.hash("uniris_index_seed"),
      Crypto.hash("uniris_index_fr_seed"),
      Crypto.hash("uniris_index_ru_seed"),
      Crypto.hash("uniris_whitepaper_seed"),
      Crypto.hash("uniris_whitepaper_fr_seed"),
      Crypto.hash("uniris_yellowpaper_s1_seed"),
      Crypto.hash("uniris_yellowpaper_s1_fr_seed")
    ]
  end
end
