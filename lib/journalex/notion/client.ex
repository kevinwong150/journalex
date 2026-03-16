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

      Logger.debug("[Notion] #{method |> Atom.to_string() |> String.upcase()} #{path}")

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
            {:ok, map} ->
              if status in 200..299 do
                Logger.debug("[Notion] #{status} OK #{path}")
              else
                notion_code = Map.get(map, "code", "unknown")
                notion_msg  = Map.get(map, "message", resp_body)
                Logger.warning("[Notion] #{status} #{path} — #{notion_code}: #{notion_msg}")
              end
              {:ok, status, map}

            {:error, decode_err} ->
              Logger.warning("[Notion] #{status} #{path} — failed to decode response: #{inspect(decode_err)}")
              {:ok, status, %{"raw" => resp_body}}
          end

        {:error, reason} ->
          Logger.error("[Notion] request failed #{path} — #{inspect(reason)}")
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
  Update a page by id with the provided payload.

  Typically payload is of the form `%{"properties" => %{...}}` matching Notion property formats.
  Returns `{:ok, map}` or `{:error, reason}`.
  """
  @spec update_page(binary(), map()) :: {:ok, map()} | {:error, term()}
  def update_page(page_id, payload) when is_binary(page_id) and is_map(payload) do
    case request(:patch, "/pages/#{page_id}", payload) do
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

  @doc """
  Retrieve the children blocks of a page or block.

  Uses `GET /v1/blocks/{block_id}/children` to fetch content blocks.
  Accepts an optional `page_size` (default 100) and `start_cursor` for pagination.

  Returns `{:ok, map}` (with `"results"` and pagination fields) or `{:error, reason}`.
  """
  @spec get_block_children(binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_block_children(block_id, opts \\ []) when is_binary(block_id) do
    page_size = Keyword.get(opts, :page_size, 100)
    query = "?page_size=#{page_size}"

    query =
      case Keyword.get(opts, :start_cursor) do
        nil -> query
        cursor -> query <> "&start_cursor=#{cursor}"
      end

    case request(:get, "/blocks/#{block_id}/children#{query}") do
      {:ok, status, map} when status in 200..299 -> {:ok, map}
      {:ok, status, map} -> {:error, {:http_error, status, map}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Append block children to a page or block.

  Uses `PATCH /v1/blocks/{block_id}/children` to add content blocks
  (paragraphs, toggles, etc.) to a Notion page.

  Returns `{:ok, map}` or `{:error, reason}`.
  """
  @spec append_block_children(binary(), list(map())) :: {:ok, map()} | {:error, term()}
  def append_block_children(block_id, children) when is_binary(block_id) and is_list(children) do
    case request(:patch, "/blocks/#{block_id}/children", %{"children" => children}) do
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
        Logger.error("[Notion] NOTION_API_TOKEN is not configured")
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
