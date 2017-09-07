defmodule Membrane.Element.Manager.State do
  @moduledoc false
  # Structure representing state of an Element.Manager. It is a part of the private API.
  # It does not represent state of elements you construct, it's a state used
  # internally in Membrane.

  use Membrane.Mixins.Log, tags: :core
  alias Membrane.Element
  alias Membrane.Element.Manager.PlaybackBuffer
  use Membrane.Helper
  alias __MODULE__

  @type t :: %State{
    internal_state: any,
    module: module,
    name: Element.name_t,
    playback_state: Membrane.Mixins.Playback.state_t,
    pads: %{optional(Element.Manager.pad_name_t) => pid},
    message_bus: pid,
  }

  defstruct \
    internal_state: nil,
    module: nil,
    name: nil,
    playback_state: :stopped,
    pads: %{},
    message_bus: nil,
    playback_buffer: nil


  @doc """
  Initializes new state.
  """
  @spec new(module, Element.name_t) :: t
  def new(module, name) do
    # Initialize source pads

    pads_data = Map.merge(
        handle_known_pads(:known_sink_pads, :sink, module),
        handle_known_pads(:known_source_pads, :source, module)
      )

    %State{
      module: module,
      name: name,
      pads: %{data: pads_data, names_by_pids: %{}, new: []},
      internal_state: nil,
      playback_buffer: PlaybackBuffer.new
    }
  end

  defp handle_known_pads(known_pads_fun, direction, module) do
    known_pads = cond do
      function_exported? module, known_pads_fun , 0 ->
        apply module, known_pads_fun, []
      true -> %{}
    end
    known_pads
      |> Enum.flat_map(fn params -> init_pad_data params, direction end)
      |> Enum.into(%{})
  end

  def add_pad(state, params, direction) do
    state = init_pad_data(params, direction)
      |> Enum.reduce(state, fn {name, data}, st -> st
        |> set_pad_data(direction, name, data)
        ~> ({:ok, st} ->
            Helper.Struct.update_in(st, [:pads, :new], & [{name, direction} | &1])
          )
        end)
    state
  end

  def clear_new_pads(state), do: state |> Helper.Struct.put_in([:pads, :new], [])

  defp init_pad_data({name, {:always, :push, caps}}, direction), do:
    do_init_pad_data(name, :push, caps, direction)

  defp init_pad_data({name, {:always, :pull, caps}}, :source), do:
    do_init_pad_data(name, :pull, caps, :source, %{other_demand_in: nil})

  defp init_pad_data({name, {:always, {:pull, demand_in: demand_in}, caps}}, :sink), do:
    do_init_pad_data(name, :pull, caps, :sink, %{demand_in: demand_in})

  defp init_pad_data({_name, {availability, _mode, _caps}}, _direction)
  when availability != :always do [] end

  defp init_pad_data(params, direction), do:
    raise "Invalid pad config: #{inspect params}, direction: #{inspect direction}"

  defp do_init_pad_data(name, mode, caps, direction, options \\ %{}) do
    data = %{
        name: name, pid: nil, mode: mode, direction: direction,
        caps: nil, accepted_caps: caps, options: options,
      }
    [{name, data}]
  end

  def get_pads_data(state, direction \\ :any)
  def get_pads_data(state, :any), do: state.pads.data
  def get_pads_data(state, direction), do: state.pads.data
    |> Enum.filter(fn {_, %{direction: ^direction}} -> true; _ -> false end)
    |> Enum.into(%{})

  def get_pad_data(state, pad_direction, pad_pid, keys \\ [])
  def get_pad_data(state, pad_direction, pad_pid, keys) when is_pid pad_pid do
    with {:ok, pad_name} <-
      state.pads.names_by_pids[pad_pid] |> Helper.wrap_nil(:unknown_pad)
    do get_pad_data(state, pad_direction, pad_name, keys)
    end
  end
  def get_pad_data(state, pad_direction, pad_name, []) do
    with %{direction: dir} = data when pad_direction in [:any, dir] <-
      state.pads.data |> Map.get(pad_name)
    do {:ok, data}
    else _ -> {:error, :unknown_pad}
    end
  end
  def get_pad_data(state, pad_direction, pad_name, keys) do
    with {:ok, pad_data} <- get_pad_data(state, pad_direction, pad_name)
    do {:ok, pad_data |> Helper.Map.get_in(keys)}
    end
  end

  def get_pad_data!(state, pad_direction, pad_name, keys \\ []), do:
    get_pad_data(state, pad_direction, pad_name, keys)
      ~> ({:ok, pad_data} -> pad_data)

  def set_pad_data(state, pad_direction, pad, keys \\ [], v) do
    pad_data = state
      |> get_pad_data(pad_direction, pad)
      ~> (
          {:ok, pad_data} -> pad_data
          {:error, :unknown_pad} -> %{}
        )
      |> Helper.Map.put_in(keys, v)

    {:ok, state |> do_update_pad_data(pad_data)}
  end

  def update_pad_data(state, pad_direction, pad, keys \\ [], f) do
    with \
      {:ok, pad_data} <- get_pad_data(state, pad_direction, pad),
      {:ok, pad_data} <- pad_data
        |> Helper.Map.get_and_update_in(keys, &case f.(&1) do
            {:ok, res} -> {:ok, res}
            {:error, reason} -> {{:error, reason}, nil}
          end)
    do
      {:ok, state |> do_update_pad_data(pad_data)}
    else
      {{:error, reason}, _pd} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_update_pad_data(state, pad_direction, pad, keys \\ [], f) do
    with \
      {:ok, pad_data} <- get_pad_data(state, pad_direction, pad),
      {{:ok, out}, pad_data} <- pad_data
        |> Helper.Map.get_and_update_in(keys, &case f.(&1) do
            {:ok, {out, res}} -> {{:ok, out}, res}
            {:error, reason} -> {{:error, reason}, nil}
          end)
    do {:ok, {out, state |> do_update_pad_data(pad_data)}}
    else
      {{:error, reason}, _pd} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_update_pad_data(state, pad_data) do
    state
      |> Helper.Struct.put_in([:pads, :names_by_pids, pad_data.pid], pad_data.name)
      |> Helper.Struct.put_in([:pads, :data, pad_data.name], pad_data)
  end

  def pop_pad_data(state, pad_direction, pad) do
    with {:ok, %{name: name, pid: pid} = pad_data} <- get_pad_data(state, pad_direction, pad),
    do: state
      |> Helper.Struct.pop_in([:pads, :names_by_pids, pid])
      ~> ({_, state} -> state)
      |> Helper.Struct.pop_in([:pads, :data, name])
      ~> ({_, state} -> {:ok, {pad_data, state}})
  end

  def remove_pad_data(state, pad_direction, pad) do
    with {:ok, {_out, state}} <- pop_pad_data(state, pad_direction, pad),
    do: {:ok, state}
  end

end
