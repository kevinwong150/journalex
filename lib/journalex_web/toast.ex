defmodule JournalexWeb.Toast do
  @moduledoc """
  Client-side-only toast notifications via `push_event/3`.

  Unlike `put_flash/3`, toasts never modify server assigns, so the
  auto-dismiss timer cannot trigger a re-render that resets client DOM
  state (form inputs, expanded detail rows, etc.).

  Import this module in your LiveView (it is auto-imported via
  `use JournalexWeb, :live_view`) and replace `put_flash/3` calls:

      socket |> put_toast(:info, "Saved!")
      put_toast(socket, :error, "Something went wrong")
  """

  import Phoenix.LiveView, only: [push_event: 3]

  @doc """
  Push a toast notification to the client.

  `kind` is `:info` or `:error`.  The message is rendered entirely on
  the client side and dismissed after a short delay without any server
  round-trip.
  """
  @spec put_toast(Phoenix.LiveView.Socket.t(), :info | :error, String.t()) ::
          Phoenix.LiveView.Socket.t()
  def put_toast(socket, kind, message) when kind in [:info, :error] and is_binary(message) do
    push_event(socket, "toast", %{kind: kind, message: message})
  end
end
