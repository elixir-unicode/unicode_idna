defmodule Unicode.IDNA.ConformanceParser do
  @moduledoc false

  # Parses IdnaTestV2.txt into a list of test rows. Each row is a map
  # with the seven fields documented in the file's preamble:
  #
  #   :source, :to_unicode, :to_unicode_status,
  #   :to_ascii_n, :to_ascii_n_status,
  #   :to_ascii_t, :to_ascii_t_status
  #
  # Status fields are MapSets of atom codes (`:b5`, `:p1`, ...).
  # Output fields are unescaped UTF-8 strings.
  #
  # The column-inheritance rules described in the file's preamble are
  # resolved here: blank `to_unicode` inherits the source, blank
  # `to_ascii_n` inherits the (resolved) `to_unicode`, etc.

  @type row :: %{
          source: String.t(),
          to_unicode: String.t(),
          to_unicode_status: MapSet.t(atom()),
          to_ascii_n: String.t(),
          to_ascii_n_status: MapSet.t(atom()),
          to_ascii_t: String.t(),
          to_ascii_t_status: MapSet.t(atom()),
          line: pos_integer()
        }

  @spec parse(Path.t()) :: [row()]
  def parse(path) do
    path
    |> File.stream!()
    |> Stream.with_index(1)
    |> Stream.reject(fn {line, _no} -> blank_or_comment?(line) end)
    |> Stream.map(fn {line, no} -> {parse_row(line), no} end)
    |> Stream.reject(fn {row, _} -> Map.get(row, :ill_formed, false) end)
    |> Enum.map(fn {row, no} -> Map.put(row, :line, no) end)
  end

  defp blank_or_comment?(line) do
    trimmed = String.trim(line)
    trimmed == "" or String.starts_with?(trimmed, "#")
  end

  defp parse_row(line) do
    [body | _comment] = String.split(line, "#", parts: 2)

    fields =
      body
      |> String.split(";")
      |> Enum.map(&String.trim/1)

    [source, to_unicode, to_unicode_status, to_ascii_n, to_ascii_n_status, to_ascii_t,
     to_ascii_t_status] = fields ++ List.duplicate("", 7 - length(fields))

    fields_unescaped = [unescape(source), unescape(to_unicode), unescape(to_ascii_n), unescape(to_ascii_t)]

    if Enum.any?(fields_unescaped, &(&1 == :ill_formed)) do
      %{ill_formed: true}
    else
      [source, to_unicode, to_ascii_n, to_ascii_t] = fields_unescaped
      to_unicode = inherit(to_unicode, source)
      to_unicode_status = parse_status(to_unicode_status, MapSet.new())
      to_ascii_n = inherit(to_ascii_n, to_unicode)
      to_ascii_n_status = parse_status(to_ascii_n_status, to_unicode_status)
      to_ascii_t = inherit(to_ascii_t, to_ascii_n)
      to_ascii_t_status = parse_status(to_ascii_t_status, to_ascii_n_status)

      %{
        source: source,
        to_unicode: to_unicode,
        to_unicode_status: to_unicode_status,
        to_ascii_n: to_ascii_n,
        to_ascii_n_status: to_ascii_n_status,
        to_ascii_t: to_ascii_t,
        to_ascii_t_status: to_ascii_t_status
      }
    end
  end

  # A blank field inherits the previous column. An explicit empty
  # string is only ever written as `""` in the source file, which the
  # unescape step turns into `""`.
  defp inherit("", fallback), do: fallback
  defp inherit(value, _fallback), do: value

  # Status field: `[A1, B5]` → MapSet.new([:a1, :b5]); blank inherits
  # the supplied fallback; explicit `[]` means no errors (reset).
  defp parse_status("[]", _fallback), do: MapSet.new()

  defp parse_status("[" <> rest, _fallback) do
    rest
    |> String.trim_trailing("]")
    |> String.split(",")
    |> Enum.map(&(String.trim(&1) |> String.downcase() |> String.to_atom()))
    |> MapSet.new()
  end

  defp parse_status("", fallback), do: fallback

  # Replace `\uXXXX` and `\x{XXXX}` escapes with their literal UTF-8
  # bytes. The literal `""` two-character sequence is the test file's
  # explicit empty string marker — convert to "".
  #
  # Returns `{:ill_formed, raw}` when an escape resolves to a
  # surrogate code point (U+D800..U+DFFF) — those rows test
  # ill-formed input handling and are skipped by the runner.
  defp unescape("\"\""), do: ""

  defp unescape(string) do
    step1 =
      Regex.replace(~r/\\u([0-9A-Fa-f]{4})/, string, fn _, hex ->
        encode_codepoint!(String.to_integer(hex, 16))
      end)

    Regex.replace(~r/\\x\{([0-9A-Fa-f]+)\}/, step1, fn _, hex ->
      encode_codepoint!(String.to_integer(hex, 16))
    end)
  catch
    :ill_formed -> :ill_formed
  end

  defp encode_codepoint!(cp) when cp in 0xD800..0xDFFF, do: throw(:ill_formed)
  defp encode_codepoint!(cp), do: <<cp::utf8>>
end
