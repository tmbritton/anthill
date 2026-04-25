# GenStatem Implementation Guide for Anthill

This document serves as a technical reference and instruction set for implementing agent logic using the `:gen_statem` behaviour. It is designed to maintain architectural consistency across sessions.

## Overview
Anthill agents use `:gen_statem` as a formal Finite State Machine (FSM). This replaces the `GenServer` pattern of "flat" state management with a "mode-based" approach where logic is encapsulated in state-specific functions.

## Core Configuration
- **Behaviour**: `@behaviour :gen_statem`
- **Callback Mode**: `def callback_mode(), do: :state_functions`
  - This mode allows each state to be its own function (e.g., `idle/3`, `loading/3`).
  - The function signature is always `state_name(event_type, event_content, data)`.
- **API Calls**: Use the Erlang atom `:gen_statem` for API calls (e.g., `:gen_statem.start_link/3`, `:gen_statem.call/2`).

## The Init Function
`init/1` must return a triple:
`{:ok, initial_state, initial_data}`
- `initial_state`: An atom (e.g., `:idle`).
- `initial_data`: The state struct (e.g., `%Anthill.Agent{}`).

## Event Types
Incoming events are passed as a tuple `(event_type, event_content)`:
- `{:cast, msg}`: Asynchronous request.
- `{:call, from, msg}`: Synchronous request.
- `{:info, msg}`: Regular process message (e.g., from a Task or Timer).
- `{:timeout, content}`: An expired timer.
- `:internal`: An event inserted by the state machine itself.

## Transition Results
Every state function must return a transition tuple:

| Result | Description |
| :--- | :--- |
| `{:keep_state, data, actions}` | Stays in the current state, updates data. |
| `{:next_state, next_state, data, actions}` | Transitions to `next_state` and updates data. |
| `{:repeat_state, data, actions}` | Stays in current state, triggers a state-enter call. |
| `{:stop, reason, data}` | Terminates the state machine. |

*Note: `actions` is an optional list of transition actions.*

## Transition Actions
Actions are executed during the transition process:
- `{:reply, from, response}`: Mandatory for replying to a `{:call, from, ...}` event.
- `{:next_event, type, content}`: Inserts a new event at the front of the queue to be processed immediately.
- `{:timeout, time, content}`: Sets a timer to fire after `time` ms.
- `:postpone`: Postpones the current event. It will be retried immediately after a state change.

## GenServer $\to$ GenStatem Mapping

| GenServer Concept | GenStatem Equivalent |
| :--- | :--- |
| `handle_cast({tag, msg}, state)` | `state_name({:cast, {tag, msg}}, data)` |
| `handle_info({tag, msg}, state)` | `state_name({:info, {tag, msg}}, data)` |
| `handle_call(req, from, state)` | `state_name({:call, from}, req, data)` |
| `{:noreply, new_state}` | `{:keep_state, new_data}` or `{:next_state, next, new_data}` |
| Manual `message_queue` | Return `:postpone` to let OTP queue events until state change. |

## Implementation Guidelines for Anthill
1. **Prefer state-specific functions** over one giant `handle_event` function.
2. **Use `:postpone`** for events that cannot be handled in the current state but should be handled once the agent transitions (e.g., a user message arriving while the agent is `:loading`).
3. **Isolate data updates** from state transitions. Update the struct, then return the `{:next_state, ...}` tuple.
4. **Always handle the "Catch-all"**: Every state function should have a final clause `def state_name(_type, _content, data)` to avoid crashes on unexpected events.
