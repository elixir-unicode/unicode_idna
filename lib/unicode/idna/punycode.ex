defmodule Unicode.IDNA.Punycode do
  @moduledoc """
  RFC 3492 Punycode encoding and decoding.

  Punycode is a uniquely-decodable bootstring encoding that represents
  arbitrary Unicode code points using only the ASCII letters,
  digits and hyphen. It is the encoding used by IDNA to represent
  internationalized domain labels in their ASCII form (the `xn--`
  prefix).

  These functions operate on a single label (without the `xn--`
  prefix) and are the building block for `Unicode.IDNA.to_ascii/2`
  and `Unicode.IDNA.to_unicode/2`. Most callers should use those
  higher-level functions; this module is exposed so that callers
  needing the raw RFC 3492 primitives do not have to re-implement
  them.

  """

  # RFC 3492 §5 bootstring parameter values for Punycode.
  @base 36
  @tmin 1
  @tmax 26
  @skew 38
  @damp 700
  @initial_bias 72
  @initial_n 128

  @maxint 0x7FFFFFFF

  @doc """
  Encodes a string of Unicode code points as a Punycode label.

  ### Arguments

  * `string` is any `t:String.t/0`.

  ### Returns

  * `{:ok, encoded}` where `encoded` is a binary containing only
    ASCII letters, digits and hyphen.

  * `{:error, :overflow}` if encoding would overflow the RFC 3492
    32-bit integer arithmetic. This can only occur for pathological
    inputs.

  ### Examples

      iex> Unicode.IDNA.Punycode.encode("bücher")
      {:ok, "bcher-kva"}

      iex> Unicode.IDNA.Punycode.encode("münchen")
      {:ok, "mnchen-3ya"}

      iex> Unicode.IDNA.Punycode.encode("abc")
      {:ok, "abc-"}

  """
  @spec encode(String.t()) :: {:ok, binary} | {:error, :overflow}
  def encode(string) when is_binary(string) do
    codepoints = String.to_charlist(string)
    {basic, non_basic} = Enum.split_with(codepoints, &basic?/1)
    output = Enum.map(basic, fn cp -> cp end)
    h = b = length(basic)

    output =
      case b do
        0 -> output
        _ -> output ++ [?-]
      end

    case encode_non_basic(non_basic, codepoints, output, @initial_n, 0, @initial_bias, h, b) do
      {:ok, list} -> {:ok, List.to_string(list)}
      {:error, _} = error -> error
    end
  end

  defp basic?(cp), do: cp < 0x80

  defp encode_non_basic(_remaining, codepoints, output, _n, _delta, _bias, h, _b)
       when h == length(codepoints) do
    {:ok, output}
  end

  defp encode_non_basic(remaining, codepoints, output, n, delta, bias, h, b) do
    m = remaining |> Enum.filter(&(&1 >= n)) |> Enum.min()

    new_delta = delta + (m - n) * (h + 1)

    if new_delta > @maxint do
      {:error, :overflow}
    else
      n2 = m

      case process_codepoints(codepoints, output, n2, new_delta, bias, h, b) do
        {:ok, output2, delta2, bias2, h2} ->
          encode_non_basic(remaining, codepoints, output2, n2 + 1, delta2 + 1, bias2, h2, b)

        {:error, _} = error ->
          error
      end
    end
  end

  defp process_codepoints(codepoints, output, n, delta, bias, h, b) do
    Enum.reduce_while(codepoints, {:ok, output, delta, bias, h}, fn c,
                                                                    {:ok, out, d, bias_acc, h_acc} ->
      cond do
        c < n ->
          new_d = d + 1

          if new_d > @maxint do
            {:halt, {:error, :overflow}}
          else
            {:cont, {:ok, out, new_d, bias_acc, h_acc}}
          end

        c == n ->
          {new_out, new_bias} = emit_delta(out, d, bias_acc, h_acc, b)
          {:cont, {:ok, new_out, 0, new_bias, h_acc + 1}}

        true ->
          {:cont, {:ok, out, d, bias_acc, h_acc}}
      end
    end)
  end

  defp emit_delta(output, delta, bias, h, b) do
    output = emit_delta_loop(output, delta, @base, bias)
    new_bias = adapt(delta, h + 1, h == b)
    {output, new_bias}
  end

  defp emit_delta_loop(output, q, k, bias) do
    t =
      cond do
        k <= bias + @tmin -> @tmin
        k >= bias + @tmax -> @tmax
        true -> k - bias
      end

    if q < t do
      output ++ [digit_to_basic(q)]
    else
      digit = t + rem(q - t, @base - t)
      output = output ++ [digit_to_basic(digit)]
      emit_delta_loop(output, div(q - t, @base - t), k + @base, bias)
    end
  end

  # RFC 3492 §6.1 bias adaptation function.
  defp adapt(delta, num_points, first_time?) do
    delta = if first_time?, do: div(delta, @damp), else: div(delta, 2)
    delta = delta + div(delta, num_points)
    adapt_loop(delta, 0)
  end

  defp adapt_loop(delta, k) when delta > div((@base - @tmin) * @tmax, 2) do
    adapt_loop(div(delta, @base - @tmin), k + @base)
  end

  defp adapt_loop(delta, k) do
    k + div((@base - @tmin + 1) * delta, delta + @skew)
  end

  # Map a numeric digit (0-35) to its ASCII character: 0-25 -> a-z, 26-35 -> 0-9.
  defp digit_to_basic(d) when d < 26, do: d + ?a
  defp digit_to_basic(d) when d < 36, do: d - 26 + ?0

  @doc """
  Decodes a Punycode label back to its original Unicode form.

  ### Arguments

  * `string` is a binary containing only ASCII letters, digits and
    hyphen.

  ### Returns

  * `{:ok, decoded}` on success.

  * `{:error, :invalid_input}` if the input contains characters
    outside the Punycode alphabet.

  * `{:error, :overflow}` if decoding would overflow the RFC 3492
    integer arithmetic.

  ### Examples

      iex> Unicode.IDNA.Punycode.decode("bcher-kva")
      {:ok, "bücher"}

      iex> Unicode.IDNA.Punycode.decode("mnchen-3ya")
      {:ok, "münchen"}

      iex> Unicode.IDNA.Punycode.decode("abc-")
      {:ok, "abc"}

  """
  @spec decode(String.t()) :: {:ok, String.t()} | {:error, :invalid_input | :overflow}
  def decode(string) when is_binary(string) do
    chars = String.to_charlist(string)

    {basic, extended} =
      case split_at_last_hyphen(chars) do
        {basic, [?- | extended]} -> {basic, extended}
        {[], chars} -> {[], chars}
      end

    if Enum.any?(basic, &(&1 >= 0x80)) do
      {:error, :invalid_input}
    else
      decode_extended(extended, basic, 0, @initial_n, @initial_bias)
    end
  end

  # Split charlist at last `-`. Returns `{prefix, [hyphen | suffix]}` or
  # `{[], chars}` if no hyphen present.
  defp split_at_last_hyphen(chars) do
    case Enum.find_index(Enum.reverse(chars), &(&1 == ?-)) do
      nil ->
        {[], chars}

      reverse_index ->
        index = length(chars) - 1 - reverse_index
        {Enum.take(chars, index), Enum.drop(chars, index)}
    end
  end

  defp decode_extended([], output, _i, _n, _bias) do
    {:ok, List.to_string(output)}
  end

  defp decode_extended(extended, output, i, n, bias) do
    case decode_one(extended, i, bias, 1, @base) do
      {:ok, new_i, rest} ->
        out_len = length(output) + 1
        n_delta = div(new_i, out_len)
        new_n = n + n_delta

        if new_n > 0x10FFFF do
          {:error, :overflow}
        else
          pos = rem(new_i, out_len)
          new_output = List.insert_at(output, pos, new_n)
          new_bias = adapt(new_i - i, out_len, i == 0)
          decode_extended(rest, new_output, pos + 1, new_n, new_bias)
        end

      {:error, _} = error ->
        error
    end
  end

  defp decode_one([], _i, _bias, _w, _k), do: {:error, :invalid_input}

  defp decode_one([c | rest], i, bias, w, k) do
    case basic_to_digit(c) do
      :error ->
        {:error, :invalid_input}

      digit ->
        new_i = i + digit * w

        if new_i > @maxint do
          {:error, :overflow}
        else
          t =
            cond do
              k <= bias + @tmin -> @tmin
              k >= bias + @tmax -> @tmax
              true -> k - bias
            end

          if digit < t do
            {:ok, new_i, rest}
          else
            new_w = w * (@base - t)

            if new_w > @maxint do
              {:error, :overflow}
            else
              decode_one(rest, new_i, bias, new_w, k + @base)
            end
          end
        end
    end
  end

  defp basic_to_digit(c) when c in ?A..?Z, do: c - ?A
  defp basic_to_digit(c) when c in ?a..?z, do: c - ?a
  defp basic_to_digit(c) when c in ?0..?9, do: c - ?0 + 26
  defp basic_to_digit(_), do: :error
end
