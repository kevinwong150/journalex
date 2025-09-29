defmodule Journalex.Notion.Client do
  @moduledoc """
  Minimal Notion API client using Finch.

  Configure via runtime.exs (env variables suggested):

    * NOTION_API_TOKEN - the internal integration token
    * NOTION_VERSION   - Notion API version header (default: "2025-09-03")

  Example:

      {:ok, %{"results" => results}} =
        Journalex.Notion.Client.query_database(database_id, %{page_size: 1})

      {:ok, page} =
        Journalex.Notion.Client.create_page(%{
          parent: %{database_id: database_id},
          properties: %{
            "Name" => %{
              "title" => [%{"text" => %{"content" => "Hello from Journalex"}}]
            }
          }
        })
  """

  require Logger

  @type method :: :get | :post | :patch | :put | :delete
  @type headers :: [{binary(), binary()}]

  @base_url "https://api.notion.com/v1"

  @doc """
  Perform a raw request to the Notion API.

  Returns `{:ok, status, body_map}` on success, or `{:error, reason}`.
  """
  @spec request(method(), binary(), map() | nil, headers()) ::
          {:ok, non_neg_integer(), map()} | {:error, term()}
  def request(method, path, body \\ nil, headers \\ []) do
    with {:ok, token, version} <- fetch_config() do
      url = build_url(path)
      json_body = if body, do: Jason.encode!(body), else: nil

      headers =
        [
          {"Authorization", "Bearer " <> token},
          {"Notion-Version", version},
          {"Content-Type", "application/json"}
        ] ++ headers

      req =
        Finch.build(method, url, headers, json_body)

      case Finch.request(req, Journalex.Finch) do
        {:ok, %Finch.Response{status: status, body: resp_body}} ->
          case safe_decode_json(resp_body) do
            {:ok, map} -> {:ok, status, map}
            {:error, _} -> {:ok, status, %{"raw" => resp_body}}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Query a Notion database by id.

  `body` follows Notion's query payload. Example: `%{filter: %{...}, page_size: 100}`

  Returns `{:ok, map}` or `{:error, reason}`.
  """
  @spec query_database(binary(), map()) :: {:ok, map()} | {:error, term()}
  def query_database(database_id, body \\ %{}) do
    case request(
           :post,
           "/data_sources/#{database_id}/query",
           body
         ) do
      {:ok, status, map} when status in 200..299 -> {:ok, map}
      {:ok, status, map} -> {:error, {:http_error, status, map}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Retrieve a database by id.
  """
  @spec retrieve_database(binary()) :: {:ok, map()} | {:error, term()}
  def retrieve_database(database_id) do
    case request(:get, "/data_sources/#{database_id}") do
      {:ok, status, map} when status in 200..299 -> {:ok, map}
      {:ok, status, map} -> {:error, {:http_error, status, map}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Create a page (e.g., in a database) with the provided payload.

  Payload should include `parent` and `properties` per Notion API.
  Returns `{:ok, map}` or `{:error, reason}`.
  """
  @spec create_page(map()) :: {:ok, map()} | {:error, term()}
  def create_page(payload) when is_map(payload) do
    case request(:post, "/pages", payload) do
      {:ok, status, map} when status in 200..299 -> {:ok, map}
      {:ok, status, map} -> {:error, {:http_error, status, map}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Retrieve a page by id.
  """
  @spec retrieve_page(binary()) :: {:ok, map()} | {:error, term()}
  def retrieve_page(page_id) do
    case request(:get, "/pages/#{page_id}") do
      {:ok, status, map} when status in 200..299 -> {:ok, map}
      {:ok, status, map} -> {:error, {:http_error, status, map}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetch the current integration user (handy to test the token).
  """
  @spec me() :: {:ok, map()} | {:error, term()}
  def me do
    case request(:get, "/users/me") do
      {:ok, status, map} when status in 200..299 -> {:ok, map}
      {:ok, status, map} -> {:error, {:http_error, status, map}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  defp build_url(path) do
    @base_url <> path
  end

  @doc false
  defp fetch_config do
    conf = Application.get_env(:journalex, __MODULE__, [])
    token = conf[:token] || System.get_env("NOTION_API_TOKEN")
    version = conf[:version] || System.get_env("NOTION_VERSION") || "2025-09-03"

    cond do
      is_nil(token) or token == "" ->
        {:error, :missing_notion_api_token}

      true ->
        {:ok, token, version}
    end
  end

  @doc false
  defp safe_decode_json(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, map} when is_map(map) -> {:ok, map}
      other -> other
    end
  end
end
