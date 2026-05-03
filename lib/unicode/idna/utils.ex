defmodule Unicode.IDNA.Utils do
  @moduledoc false

  @doc """
  Parses the UTS #46 IDNA mapping table.

  Returns a list of `{first_codepoint, last_codepoint, status,
  mapping}` tuples where:

    * `status` is one of `:valid`, `:ignored`, `:mapped`,
      `:deviation` or `:disallowed`.

    * `mapping` is a list of target code points (possibly empty)
      for `:mapped` and `:deviation`, and `nil` for the other
      statuses.

  The list is sorted by `first_codepoint`.
  """
  @idna_mapping_path Path.join(Unicode.IDNA.data_dir(), "idna_mapping_table.txt")
  @external_resource @idna_mapping_path
  def idna_mapping do
    @idna_mapping_path
    |> File.stream!()
    |> Stream.map(&strip_comment/1)
    |> Stream.reject(&blank?/1)
    |> Stream.map(&parse_mapping_row/1)
    |> Enum.to_list()
    |> Enum.sort_by(fn {first, _, _, _} -> first end)
  end

  @doc """
  Parses a Unicode `extracted/Derived*.txt`-style file.

  Returns a list of `{first_codepoint, last_codepoint, value}`
  tuples where `value` is the second semicolon-separated field as
  an atom (downcased, whitespace removed).
  """
  def derived_property(path) do
    path
    |> File.stream!()
    |> Stream.map(&strip_comment/1)
    |> Stream.reject(&blank?/1)
    |> Stream.map(&parse_derived_row/1)
    |> Enum.to_list()
    |> Enum.sort_by(fn {first, _, _} -> first end)
  end

  defp strip_comment(line) do
    line
    |> String.split("#", parts: 2)
    |> hd()
    |> String.trim()
  end

  defp blank?(""), do: true
  defp blank?(_), do: false

  defp parse_mapping_row(line) do
    fields = line |> String.split(";") |> Enum.map(&String.trim/1)
    {first, last} = parse_range(Enum.at(fields, 0))
    status_atom = fields |> Enum.at(1) |> String.to_atom()
    target_field = Enum.at(fields, 2, "")

    mapping =
      case {status_atom, target_field} do
        {status, _} when status in [:mapped, :deviation] ->
          parse_codepoint_list(target_field)

        _ ->
          nil
      end

    {first, last, status_atom, mapping}
  end

  defp parse_derived_row(line) do
    [range_field, value | _] = line |> String.split(";") |> Enum.map(&String.trim/1)
    {first, last} = parse_range(range_field)
    {first, last, value |> String.downcase() |> String.to_atom()}
  end

  defp parse_range(field) do
    case String.split(field, "..") do
      [single] ->
        cp = String.to_integer(single, 16)
        {cp, cp}

      [first, last] ->
        {String.to_integer(first, 16), String.to_integer(last, 16)}
    end
  end

  defp parse_codepoint_list(""), do: []

  defp parse_codepoint_list(field) do
    field
    |> String.split(" ", trim: true)
    |> Enum.map(&String.to_integer(&1, 16))
  end
end
