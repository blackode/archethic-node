defmodule ArchEthicWeb.API.TransactionController do
  @moduledoc false

  use ArchEthicWeb, :controller

  alias ArchEthic

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData

  alias ArchEthic.Mining
  alias ArchEthic.OracleChain

  alias ArchEthicWeb.API.TransactionPayload
  alias ArchEthicWeb.ErrorView

  require Logger

  def new(conn, params = %{}) do
    case TransactionPayload.changeset(params) do
      changeset = %{valid?: true} ->
        start = System.monotonic_time()

        res =
          changeset
          |> TransactionPayload.to_map()
          |> Transaction.from_map()
          |> ArchEthic.send_new_transaction()

        :telemetry.execute([:archethic, :transaction_end_to_end_validation], %{
          duration: System.monotonic_time() - start
        })

        case res do
          :ok ->
            conn
            |> put_status(201)
            |> json(%{status: "ok"})

          _ ->
            conn
            |> put_status(422)
            |> json(%{status: "error - transaction may be invalid"})
        end

      changeset ->
        Logger.debug(
          "Invalid transaction #{inspect(Ecto.Changeset.traverse_errors(changeset, &ArchEthicWeb.ErrorHelpers.translate_error/1))}"
        )

        conn
        |> put_status(400)
        |> put_view(ErrorView)
        |> render("400.json", changeset: changeset)
    end
  end

  def last_transaction_content(conn, params = %{"address" => address}) do
    with {:ok, address} <- Base.decode16(address, case: :mixed),
         {:ok, %Transaction{address: last_address, data: %TransactionData{content: content}}} <-
           ArchEthic.get_last_transaction(address) do
      mime_type = Map.get(params, "mime", "text/plain")

      etag = Base.encode16(last_address, case: :lower)

      cached? =
        case List.first(get_req_header(conn, "if-none-match")) do
          got_etag when got_etag == etag ->
            true

          _ ->
            false
        end

      conn =
        conn
        |> put_resp_content_type(mime_type, "utf-8")
        |> put_resp_header("content-encoding", "gzip")
        |> put_resp_header("cache-control", "public")
        |> put_resp_header("etag", etag)

      if cached? do
        send_resp(conn, 304, "")
      else
        send_resp(conn, 200, :zlib.gzip(content))
      end
    else
      _reason ->
        send_resp(conn, 404, "Not Found")
    end
  end

  def transaction_fee(conn, tx) do
    case TransactionPayload.changeset(tx) do
      changeset = %{valid?: true} ->
        uco_price = OracleChain.get_uco_price(DateTime.utc_now())
        uco_eur = uco_price |> Keyword.fetch!(:eur)
        uco_usd = uco_price |> Keyword.fetch!(:usd)

        fee =
          changeset
          |> TransactionPayload.to_map()
          |> Transaction.from_map()
          |> Mining.get_transaction_fee(uco_usd)

        conn
        |> put_status(:ok)
        |> json(%{
          "fee" => fee / 100_000_000,
          "rates" => %{
            "usd" => uco_usd,
            "eur" => uco_eur
          }
        })

      changeset ->
        conn
        |> put_status(:bad_request)
        |> put_view(ErrorView)
        |> render("400.json", changeset: changeset)
    end
  end
end
