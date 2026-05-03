defmodule Unicode.IDNA.ConformanceTest do
  @moduledoc """
  Runs the official UTS #46 conformance suite from
  `data/idna_test_v2.txt`.

  Each test row has seven columns. The runner exercises three
  operations:

    * `domain_to_ascii/2` with `transitional: false`
      (column 4 / column 5 status).

    * `domain_to_ascii/2` with `transitional: true`
      (column 6 / column 7 status).

    * `domain_to_unicode/2` (column 2 / column 3 status).

  For each operation:

    * If the expected status set is empty, the result must be
      `{:ok, expected}` with `expected` matching the column's value.

    * If the expected status set is non-empty, the result must be
      an `{:error, _}` of any reason — the spec only requires that
      conforming implementations record *that* there is an error,
      not the exact code.

  Set `IDNA_CONFORMANCE_VERBOSE=true` to print the first 50 failure
  details.
  """

  use ExUnit.Case, async: true

  alias Unicode.IDNA
  alias Unicode.IDNA.ConformanceParser

  @moduletag :conformance
  @moduletag timeout: 120_000

  @data_path Path.expand("../data/idna_test_v2.txt", __DIR__)
  @external_resource @data_path

  @rows ConformanceParser.parse(@data_path)

  test "IdnaTestV2.txt" do
    {to_unicode_failures, to_ascii_n_failures, to_ascii_t_failures} =
      Enum.reduce(@rows, {[], [], []}, fn row, {tu, tn, tt} ->
        {
          maybe_record(tu, row, :to_unicode, &IDNA.to_unicode/2, []),
          maybe_record(tn, row, :to_ascii_n, &IDNA.to_ascii/2, transitional: false),
          maybe_record(tt, row, :to_ascii_t, &IDNA.to_ascii/2, transitional: true)
        }
      end)

    total = length(@rows)

    summary =
      Enum.map_join(
        [
          {"toUnicode", to_unicode_failures},
          {"toAsciiN", to_ascii_n_failures},
          {"toAsciiT", to_ascii_t_failures}
        ],
        "\n",
        fn {label, failures} ->
          "  #{label}: #{total - length(failures)}/#{total} pass (#{length(failures)} fail)"
        end
      )

    if System.get_env("IDNA_CONFORMANCE_VERBOSE") == "true" do
      print_failures("toUnicode", to_unicode_failures)
      print_failures("toAsciiN", to_ascii_n_failures)
      print_failures("toAsciiT", to_ascii_t_failures)
    end

    IO.puts("\nIdnaTestV2 conformance:\n" <> summary)

    failures =
      length(to_unicode_failures) + length(to_ascii_n_failures) + length(to_ascii_t_failures)

    assert failures == 0,
           "#{failures} conformance failures. Set IDNA_CONFORMANCE_VERBOSE=true for details."
  end

  defp maybe_record(failures, row, kind, fun, options) do
    expected = Map.fetch!(row, kind)
    expected_status = Map.fetch!(row, status_key(kind))
    actual = fun.(row.source, options)

    if conforms?(actual, expected, expected_status) do
      failures
    else
      [{row.line, row.source, kind, expected, expected_status, actual} | failures]
    end
  end

  defp status_key(:to_unicode), do: :to_unicode_status
  defp status_key(:to_ascii_n), do: :to_ascii_n_status
  defp status_key(:to_ascii_t), do: :to_ascii_t_status

  # Conformance: error expected ⇒ any error counts. No error expected
  # ⇒ result must be `{:ok, expected}`.
  defp conforms?({:error, _}, _expected, status) do
    MapSet.size(status) > 0
  end

  defp conforms?({:ok, actual}, expected, status) do
    MapSet.size(status) == 0 and actual == expected
  end

  defp print_failures(_label, []), do: :ok

  defp print_failures(label, failures) do
    IO.puts("\n=== #{label} failures (showing first 50) ===")

    failures
    |> Enum.reverse()
    |> Enum.take(50)
    |> Enum.each(fn {line, source, _kind, expected, status, actual} ->
      IO.puts(
        "  L#{line}  src=#{inspect(source)}  expected=#{inspect(expected)}  " <>
          "status=#{inspect(MapSet.to_list(status))}  actual=#{inspect(actual)}"
      )
    end)
  end
end
