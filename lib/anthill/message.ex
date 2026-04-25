defmodule Anthill.Message do
  @type message_role :: :user | :assistant | :system | :tool

  @type t :: %__MODULE__{
          role: message_role(),
          content: String.t() | list(),
          tool_call_id: String.t() | nil,
          tool_name: String.t() | nil,
          function_call: map() | nil
        }

  defstruct role: nil,
            content: nil,
            tool_call_id: nil,
            tool_name: nil,
            function_call: nil
end
