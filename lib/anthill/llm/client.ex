defmodule Anthill.LLM.Client do
  @moduledoc """
  Behavior for interacting with LLMs.
  """

  @callback send_message(msg :: String.t()) :: {:ok, String.t()} | {:error, term()}
end
