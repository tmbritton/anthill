defmodule Anthill.Agent do
  @behaviour :gen_statem
  @max_retries 3
  @retry_multiplier 1000

  @type llm_client :: module()
  @type history :: [Anthill.Message.t()]
  @type retries :: integer()
  @type error_message :: String.t()

  @type t :: %__MODULE__{
          llm_client: llm_client(),
          history: history(),
          retries: retries(),
          error_message: error_message()
        }

  defstruct llm_client: nil,
            history: [],
            retries: 0,
            error_message: nil

  def callback_mode, do: :state_functions

  def init([client]),
    do:
      {:ok, :idle,
       %Anthill.Agent{
         llm_client: client,
         history: [],
         retries: 0,
         error_message: nil
       }}

  # state callbacks
  # --- State: Idle ---
  def idle({:new_message, content}, _from, data) do
    msg = %Anthill.Message{role: :user, content: content}
    new_data = %{data | history: [msg | data.history]}

    # Send request before transitioning to loading state
    send_next_llm_request(new_data)

    {:next_state, :loading, new_data}
  end

  # --- State: Loading ---
  # Clause 1: LLM returned text response, no tool calls
  def loading({:llm_response, %{tool_calls: [] = response}}, _from, data) do
    new_data = %{data | history: [response]}
    # Begin output stream
    {:next_state, :outputting, new_data, [:start_output]}
  end

  # Clause 2: LLM has tool calls
  def loading({:llm_response, %{tool_calls: tool_calls = response}}, _from, data) do
    new_data = %{data | history: [response]}
    # Do tool call
    {:keep_state, :loading, new_data}
  end

  # Clause 3: Postpone new messages
  def loading({:new_message, content}, _from, data) do
    {:keep_state, :loading, data, [{:new_message, content}]}
  end

  # Clause 4: Handle the :retry events
  def loading(:retry, _from, data) do
    # We've already called send_next_llm_request in handle_retries,
    # so we just stay in :loading and wait for the response.
    {:keep_state, :loading, data}
  end

  # Clause 5: Handle errors
  def loading({:llm_error, error}, _from, data) do
    {:next_state, :error, %{data | error_message: error}, [:check_retries]}
  end

  # --- State: Error ---
  def error(:check_retries, _from, data) do
    handle_retries(data)
  end

  # Clause 2: Postpone new messages
  def error({:new_message, content}, _from, data) do
    {:keep_state, :error, data, [{:new_message, content}]}
  end

  # --- State: Outputting ---
  # Output entry point
  def outputting(:start_output, _from, data) do
    if data.error_message do
      {:keep_state, :outputting, data, [:error]}
    else
      {:keep_state, :outputting, data, [:llm_response]}
    end
  end

  # Clause 1: Error message
  def outputting(:error, _from, data) do
    # Do error outputting logic
    new_data = %{data | error_message: nil}
    {:next_state, :idle, new_data}
  end

  # Clause 2: Output streaming message from LLM
  def outputting(:llm_response, _from, data) do
    # Stream response from LLM
    {:next_state, :idle, data}
  end

  # private functions
  @spec construct_context(history()) :: String.t()
  defp construct_context(history) do
    history
    |> Enum.reverse()
    |> Enum.map(fn msg ->
      %{
        "role" => Atom.to_string(msg.role),
        "content" => msg.content,
        "tool_call_id" => msg.tool_call_id,
        "tool_name" => msg.tool_name,
        "function_call" => msg.function_call
      }
      |> Anthill.Utils.compact()
    end)
    |> Jason.encode!()
  end

  defp send_next_llm_request(%{llm_client: client, history: history} = state) do
    context = construct_context(history)
    agent_pid = self()

    Task.start(fn ->
      case client.send_message(context) do
        {:ok, msg} -> send(agent_pid, {:llm_response, msg})
        {:error, reason} -> send(agent_pid, {:llm_error, reason})
      end
    end)

    state
  end

  defp handle_retries(data) when data.retries < @max_retries do
    new_data = %{data | retries: data.retries + 1}
    send_next_llm_request(new_data)
    {:next_state, :loading, new_data, [:retry]}
  end

  defp handle_retries(data) do
    {:next_state, :outputting, data, [:start_output]}
  end
end
