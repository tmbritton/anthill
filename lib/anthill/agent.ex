defmodule Anthill.Agent do
  use GenServer
  @max_retries 3
  @retry_multiplier 1000

  defstruct llm_client: nil, history: [], state: :idle, retries: 0, error_message: nil, message_queue: [] 
  
  @type llm_client :: module()
  @type history :: [Anthill.Message.t()]
  @type agent_state :: :idle | :loading | :outputting | :error
  @type retries :: integer()
  @type error_message :: String.t()
  @type message_queue :: [Anthill.Message.t()]

  @type t :: %__MODULE__{
    llm_client: llm_client(),
    history: history(),
    state: agent_state(),
    retries: retries(),
    error_message: error_message(),
    message_queue: message_queue()
  }

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

  # This is what start_link calls.
  # It takes the args from start_link and returns the initial state.
  @impl true
  def init(args) do
    # We return {:ok, state}
    # 'args' would be things like your llm_client
    {:ok, %__MODULE__{llm_client: args[:llm_client]}}
  end

  # Idle state
  @impl true
  def handle_cast({:new_message, %Anthill.Message{} = msg}, %{state: :idle} = state) do
    # construct conversation history, add msg to the end, send request to LLM
    new_state = %{state | state: :loading, history: [msg | state.history]}
    {:noreply, new_state}
  end

  # Any states that aren't idle
  @impl true
  def handle_cast({:new_message, %Anthill.Message{} = msg}, %{state: current_state} = state) when current_state in [:loading, :error, :outputting] do
    new_state = %{state | message_queue: [msg | state.message_queue]}
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:tool_result, %Anthill.Message{role: :tool} = msg}, %{state: :loading} = state) do
    new_state = %{state | history: [msg | state.history]}
    send_next_llm_request(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:llm_response, %Anthill.Message{role: :assistant} = msg}, %{state: :loading} = state) do
    new_state = %{state | history: [msg | state.history], state: :outputting}
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:llm_error, reason}, %{state: :loading} = state) do
    new_state = attempt_retry(state, reason)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:retry_llm_request}, %{state: :loading} = state) do
    send_next_llm_request(state)
    {:noreply, state}
  end

  defp attempt_retry(%{retries: r} = state, reason) when r < @max_retries do
    new_state = %{state | retries: r + 1}
    delay = new_state.retries * @retry_multiplier
    Process.send_after(self(), {:retry_llm_request}, delay)
    new_state
  end

  defp attempt_retry(state, reason) do
    %{state | state: :error, error_message: "Max retries readed: #{reason}"}
  end

end
