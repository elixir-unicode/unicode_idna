defmodule Unicode.IDNA.Mapping do
  @moduledoc """
  UTS #46 IDNA mapping table lookup.

  The mapping table classifies every Unicode code point into one of
  five statuses (`:valid`, `:ignored`, `:mapped`, `:deviation` or
  `:disallowed`) and, for `:mapped` and `:deviation`, supplies the
  list of target code points to substitute.

  This module compiles the table from `data/idna_mapping_table.txt`
  at compile time and exposes a single fast-path lookup function.

  """

  alias Unicode.IDNA.Utils

  @typedoc "An IDNA mapping table status."
  @type status :: :valid | :ignored | :mapped | :deviation | :disallowed

  @typedoc """
  A mapping result. The second element is `nil` for `:valid`, `:ignored`
  and `:disallowed`, and a (possibly empty) list of target code points
  for `:mapped` and `:deviation`.
  """
  @type result :: {status, [non_neg_integer] | nil}

  @doc """
  Returns the IDNA mapping table status (and replacement, if any) for
  a single Unicode code point.

  ### Arguments

  * `codepoint` is a non-negative integer in the range `0..0x10FFFF`.

  ### Returns

  * `{status, replacement}` where `status` is one of `:valid`,
    `:ignored`, `:mapped`, `:deviation` or `:disallowed`, and
    `replacement` is a (possibly empty) list of target code points
    for `:mapped` and `:deviation`, or `nil` for the other statuses.

  ### Examples

      iex> Unicode.IDNA.Mapping.lookup(?A)
      {:mapped, [?a]}

      iex> Unicode.IDNA.Mapping.lookup(?a)
      {:valid, nil}

      iex> Unicode.IDNA.Mapping.lookup(0x0080)
      {:disallowed, nil}

      iex> Unicode.IDNA.Mapping.lookup(0x00DF)
      {:deviation, [?s, ?s]}

      iex> Unicode.IDNA.Mapping.lookup(0x00AD)
      {:ignored, nil}

  """
  @spec lookup(non_neg_integer) :: result
  for {first, last, status, mapping} <- Utils.idna_mapping() do
    cond do
      first == last ->
        def lookup(unquote(first)), do: {unquote(status), unquote(mapping)}

      true ->
        def lookup(codepoint) when codepoint in unquote(first)..unquote(last),
          do: {unquote(status), unquote(mapping)}
    end
  end
end
