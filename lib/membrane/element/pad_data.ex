defmodule Membrane.Element.PadData do
  @moduledoc """
  Struct describing current pad state.

  The public fields are:
    - `:availability` - see `t:Membrane.Pad.availability/0`
    - `:stream_format` - the most recent `t:Membrane.StreamFormat.t/0` that have been sent (output) or received (input)
      on the pad. May be `nil` if not yet set.
    - `:demand` - current demand requested on the pad working in `:auto` or `:manual` flow control mode.
    - `:direction` - see `t:Membrane.Pad.direction/0`
    - `:end_of_stream?` - flag determining whether the stream processing via the pad has been finished
    - `:flow_control` - see `t:Membrane.Pad.flow_control/0`.
    - `:name` - see `t:Membrane.Pad.name/0`. Do not mistake with `:ref`
    - `:options` - options passed in `Membrane.ParentSpec` when linking pad
    - `:ref` - see `t:Membrane.Pad.ref/0`
    - `:start_of_stream?` - flag determining whether the stream processing via the pad has been started

  Other fields in the struct ARE NOT PART OF THE PUBLIC API and should not be
  accessed or relied on.
  """
  use Bunch.Access

  alias Membrane.{Pad, StreamFormat}

  @type private_field :: term()

  @type t :: %__MODULE__{
          availability: Pad.availability(),
          stream_format: StreamFormat.t() | nil,
          start_of_stream?: boolean(),
          end_of_stream?: boolean(),
          direction: Pad.direction(),
          flow_control: Pad.flow_control(),
          name: Pad.name(),
          ref: Pad.ref(),
          options: %{optional(atom) => any},
          stream_format_validation_params: private_field,
          pid: private_field,
          other_ref: private_field,
          input_queue: private_field,
          demand: integer() | nil,
          demand_unit: private_field,
          other_demand_unit: private_field,
          auto_demand_size: private_field,
          sticky_messages: private_field,
          toilet: private_field,
          associated_pads: private_field,
          sticky_events: private_field
        }

  @enforce_keys [
    :availability,
    :stream_format,
    :direction,
    :flow_control,
    :name,
    :ref,
    :options,
    :pid,
    :other_ref
  ]

  defstruct @enforce_keys ++
              [
                input_queue: nil,
                demand: nil,
                demand_unit: nil,
                start_of_stream?: false,
                end_of_stream?: false,
                auto_demand_size: nil,
                sticky_messages: [],
                toilet: nil,
                associated_pads: [],
                sticky_events: [],
                stream_format_validation_params: [],
                other_demand_unit: nil
              ]
end
