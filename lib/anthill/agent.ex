defmodule Anthill.Agent do
  @type llm_client :: module()
  @type history :: [Anthill.Message.t()]

  @type t :: %__MODULE__{
    llm_client: llm_client(),
    history: history()
  }

  defstruct llm_client: nil, history: [] 
end
