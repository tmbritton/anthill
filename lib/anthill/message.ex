defmodule Anthill.Message do
  @type message_type :: :user | :agent | :system | :tool_result

  @type t :: %__MODULE__{
    type: message_type(),
    content: String.t()
  }

  defstruct type: nil, content: nil
end
