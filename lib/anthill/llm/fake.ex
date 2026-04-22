defmodule Anthill.LLM.Fake do
  @behaviour Anthill.LLM.Client

  def send_message(msg) do
    {:ok, "I am a fake LLM"}
  end

end
