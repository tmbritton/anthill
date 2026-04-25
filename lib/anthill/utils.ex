defmodule Anthill.Utils do
  @moduledoc """
  General purpose utility functions.
  """

  @doc """
  Removes all keys from a map where the value is nil.
  """
  @spec compact(map()) :: map()
  def compact(map) when is_map(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end


end
