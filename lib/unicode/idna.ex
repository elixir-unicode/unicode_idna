defmodule Unicode.IDNA do
  @moduledoc """
  UTS #46 *Unicode IDNA Compatibility Processing*.

  This module implements the algorithms in [UTS #46](https://www.unicode.org/reports/tr46/) §4 (Processing), §4.1 (Validity Criteria) and §4.2 (ToASCII), with Punycode (RFC 3492), the CONTEXTJ rules of RFC 5892 Appendix A, and the RFC 5893 bidi rule.

  The two main entry points, `to_ascii/2` and `to_unicode/2`, accept either:

  * a `t:String.t/0` containing a full domain name (one or more labels separated by an IDNA label separator: `.`, `U+3002`, `U+FF0E`, or `U+FF61`), or

  * a list of `t:String.t/0` labels.

  The return value mirrors the input shape: a string in returns a string out (the labels are rejoined with `.`); a list in returns a list out.

  The default options track *non-transitional* UTS #46 processing with all checks enabled, which matches modern browsers (Chrome, Firefox, Safari).

  Punycode encoding and decoding are also exposed directly as `Unicode.IDNA.Punycode.encode/1` and `Unicode.IDNA.Punycode.decode/1` for callers needing the raw RFC 3492 primitives without the surrounding UTS #46 processing.

  """

  alias Unicode.BidiClass
  alias Unicode.IDNA.{Bidi, Context, Mapping, Punycode}

  @ace_prefix "xn--"
  @label_separators [".", "。", "．", "｡"]

  @typedoc "An error reason returned by `to_ascii/2` or `to_unicode/2`."
  @type error ::
          :empty_label
          | :disallowed
          | :hyphen_violation
          | :leading_combining_mark
          | :context
          | :bidi
          | :punycode_overflow
          | :punycode_invalid
          | :label_too_long
          | :domain_too_long

  @typedoc """
  Options controlling UTS #46 processing.

  * `:transitional` — default `false`. When `true`, deviation
    code points are mapped to their replacements (the original
    IDNA 2003 behaviour).

  * `:check_hyphens` — default `true`. When `true`, a U-label may
    not begin or end with `-`, nor have `-` in both the third and
    fourth positions. The check is suppressed for ACE labels after
    Punycode decoding.

  * `:check_bidi` — default `true`. When `true`, if the domain
    contains a right-to-left character, every label must satisfy
    the RFC 5893 bidi rule.

  * `:check_joiners` — default `true`. When `true`, labels
    containing ZWJ or ZWNJ must satisfy the CONTEXTJ rules of
    RFC 5892.

  * `:use_std3_ascii_rules` — default `true`. When `true`, ASCII
    characters in a label are restricted to letters, digits and
    hyphen.

  * `:verify_dns_length` — default `true`. When `true`, each label
    must be 1–63 octets and the full domain (less the trailing
    `.`, if any) must be 1–253 octets.
  """
  @type options :: [
          transitional: boolean,
          check_hyphens: boolean,
          check_bidi: boolean,
          check_joiners: boolean,
          use_std3_ascii_rules: boolean,
          verify_dns_length: boolean
        ]

  @default_options [
    transitional: false,
    check_hyphens: true,
    check_bidi: true,
    check_joiners: true,
    use_std3_ascii_rules: true,
    verify_dns_length: true
  ]

  @doc false
  @data_dir Path.join(__DIR__, "../../data") |> Path.expand()
  def data_dir do
    @data_dir
  end

  @doc """
  Applies UTS #46 ToASCII to a domain name.

  ### Arguments

  * `domain` is either a `t:String.t/0` containing one or more labels separated by an IDNA label separator (`.`, `U+3002`, `U+FF0E`, `U+FF61`), or a list of `t:String.t/0` labels. Each label may be in Unicode form or in ACE (`xn--…`) form.

  * `options` is a keyword list of UTS #46 options. See the type `t:options/0`.

  ### Returns

  * `{:ok, ascii_domain}` on success. The shape mirrors the input: a string in returns a string (labels rejoined with `.`); a list in returns the list of ASCII labels.

  * `{:error, reason}` — see the `t:error/0` type.

  ### Examples

      iex> Unicode.IDNA.to_ascii("bücher.de")
      {:ok, "xn--bcher-kva.de"}

      iex> Unicode.IDNA.to_ascii("中文。中国")
      {:ok, "xn--fiq228c.xn--fiqs8s"}

      iex> Unicode.IDNA.to_ascii(["bücher", "de"])
      {:ok, ["xn--bcher-kva", "de"]}

      iex> Unicode.IDNA.to_ascii("ASCII")
      {:ok, "ascii"}

      iex> Unicode.IDNA.to_ascii("xn--bcher-kva")
      {:ok, "xn--bcher-kva"}

      iex> Unicode.IDNA.to_ascii("not_valid")
      {:error, :disallowed}

      iex> Unicode.IDNA.to_ascii("not_valid", use_std3_ascii_rules: false)
      {:ok, "not_valid"}

  """
  @spec to_ascii(String.t() | [String.t()], options) ::
          {:ok, String.t() | [String.t()]} | {:error, error}
  def to_ascii(domain, options \\ [])

  def to_ascii(domain, options) when is_binary(domain) and is_list(options) do
    case to_ascii(String.split(domain, @label_separators), options) do
      {:ok, ascii_labels} -> {:ok, Enum.join(ascii_labels, ".")}
      {:error, _} = error -> error
    end
  end

  def to_ascii(labels, options) when is_list(labels) and is_list(options) do
    options = Keyword.merge(@default_options, options)

    with {:ok, normalized_labels} <- map_normalize_each(labels, options),
         {:ok, processed_labels} <- process_labels(normalized_labels, options),
         :ok <- check_domain_bidi(processed_labels, options),
         {:ok, ascii_labels} <- encode_labels(processed_labels),
         :ok <- verify_dns_length(ascii_labels, options) do
      {:ok, ascii_labels}
    end
  end

  @doc """
  Applies UTS #46 ToUnicode to a domain name.

  ### Arguments

  * `domain` is either a `t:String.t/0` or a list of label `t:String.t/0`s; see `to_ascii/2` for the shape semantics.

  * `options` is a keyword list. See `to_ascii/2`.

  ### Returns

  * `{:ok, unicode_domain}` on success — string in / string out, list in / list out.

  * `{:error, reason}` on failure.

  ### Examples

      iex> Unicode.IDNA.to_unicode("xn--bcher-kva.de")
      {:ok, "bücher.de"}

      iex> Unicode.IDNA.to_unicode("BÜCHER.DE")
      {:ok, "bücher.de"}

      iex> Unicode.IDNA.to_unicode(["xn--bcher-kva", "de"])
      {:ok, ["bücher", "de"]}

      iex> Unicode.IDNA.to_unicode("xn--bcher-kva")
      {:ok, "bücher"}

      iex> Unicode.IDNA.to_unicode("bücher")
      {:ok, "bücher"}

  """
  @spec to_unicode(String.t() | [String.t()], options) ::
          {:ok, String.t() | [String.t()]} | {:error, error}
  def to_unicode(domain, options \\ [])

  def to_unicode(domain, options) when is_binary(domain) and is_list(options) do
    case to_unicode(String.split(domain, @label_separators), options) do
      {:ok, unicode_labels} -> {:ok, Enum.join(unicode_labels, ".")}
      {:error, _} = error -> error
    end
  end

  def to_unicode(labels, options) when is_list(labels) and is_list(options) do
    options = Keyword.merge(@default_options, options)

    with {:ok, normalized_labels} <- map_normalize_each(labels, options),
         {:ok, processed_labels} <- process_labels(normalized_labels, options),
         :ok <- check_domain_bidi(processed_labels, options),
         :ok <- verify_unicode_length(processed_labels, options) do
      {:ok, Enum.map(processed_labels, & &1.text)}
    end
  end

  @doc """
  Returns `true` if `label` is a valid IDNA label under the given options, `false` otherwise.

  Operates on a single label only. Equivalent to `match?({:ok, _}, to_ascii(label, options))` for a binary input that does not contain a label separator.

  ### Arguments

  * `label` is a `t:String.t/0` containing one domain label.

  * `options` is a keyword list. See `to_ascii/2`.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> Unicode.IDNA.valid_label?("bücher")
      true

      iex> Unicode.IDNA.valid_label?("not_valid")
      false

      iex> Unicode.IDNA.valid_label?("not_valid", use_std3_ascii_rules: false)
      true

  """
  @spec valid_label?(String.t(), options) :: boolean
  def valid_label?(label, options \\ []) when is_binary(label) and is_list(options) do
    match?({:ok, _}, to_ascii([label], options))
  end

  ## Internal pipeline

  # UTS #46 §4 step 1 (Map) and step 2 (Normalize), applied per
  # label. Splitting on the four IDNA separators *before* mapping is
  # equivalent to mapping then splitting because the only code
  # points that map to U+002E are the three separators themselves
  # (U+3002, U+FF0E, U+FF61) — see the IDNA mapping table.
  defp map_normalize_each(labels, options) do
    Enum.reduce_while(labels, {:ok, []}, fn label, {:ok, acc} ->
      case map_codepoints(label, options) do
        {:ok, mapped} ->
          normalized = :unicode.characters_to_nfc_binary(mapped)
          {:cont, {:ok, [normalized | acc]}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp map_codepoints(domain, options) do
    transitional? = Keyword.fetch!(options, :transitional)

    domain
    |> String.to_charlist()
    |> Enum.reduce_while([], fn cp, acc ->
      case map_codepoint(cp, transitional?) do
        {:ok, replacement} -> {:cont, [replacement | acc]}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      :error -> {:error, :disallowed}
      reversed -> {:ok, reversed |> Enum.reverse() |> List.flatten() |> List.to_string()}
    end
  end

  defp map_codepoint(cp, transitional?) do
    case Mapping.lookup(cp) do
      {:valid, _} -> {:ok, [cp]}
      {:ignored, _} -> {:ok, []}
      {:mapped, target} -> {:ok, expand_deviations(target, transitional?)}
      {:deviation, target} when transitional? -> {:ok, target}
      {:deviation, _} -> {:ok, [cp]}
      {:disallowed, _} -> :error
    end
  end

  # Under transitional processing, a `mapped` target may itself
  # contain a deviation code point (e.g. U+1E9E ẞ → U+00DF ß → "ss"
  # under transitional). UTS #46's mapping is specified per source
  # code point but in practice implementations expand the chain so
  # that uppercase ẞ also becomes "ss" — match the IdnaTestV2 suite
  # by walking the target list once and re-mapping any deviations.
  defp expand_deviations(target, false), do: target

  defp expand_deviations(target, true) do
    Enum.flat_map(target, fn t ->
      case Mapping.lookup(t) do
        {:deviation, dev_target} -> dev_target
        _ -> [t]
      end
    end)
  end

  # UTS #46 §4 step 4 (Convert/Validate). For each label, if it
  # starts with `xn--`, attempt Punycode decode and use the U-label;
  # then run the §4.1 validity criteria.
  defp process_labels(labels, options) do
    labels
    |> Enum.reduce_while({:ok, []}, fn label, {:ok, acc} ->
      case process_one_label(label, options) do
        {:ok, processed} -> {:cont, {:ok, [processed | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  # A processed label record: original text after decode + ACE flag.
  # The ACE flag suppresses CheckHyphens and indicates the label
  # should be re-encoded with `xn--` on output.
  defp process_one_label("", _options), do: {:ok, %{text: "", from_ace?: false, ascii?: true}}

  defp process_one_label(label, options) do
    with {:ok, text, from_ace?} <- maybe_decode_ace(label),
         :ok <- validate_label(text, from_ace?, options) do
      {:ok, %{text: text, from_ace?: from_ace?, ascii?: ascii?(text)}}
    end
  end

  defp maybe_decode_ace(label) do
    case label do
      <<prefix::binary-size(4), rest::binary>> when rest != "" ->
        if String.downcase(prefix) == @ace_prefix do
          decode_ace_label(rest)
        else
          {:ok, label, false}
        end

      _ ->
        {:ok, label, false}
    end
  end

  # Decode the Punycode payload, verify the decoded form is already
  # in NFC (V1: a U-label that decodes to a non-NFC sequence is an
  # error, since the encoder would have normalized first), and
  # reject ACE labels that decode to a pure-ASCII string (P4) —
  # those are spurious uses of the `xn--` prefix that round-trip
  # differently.
  defp decode_ace_label(rest) do
    with {:ok, decoded} <- punycode_decode(rest),
         :ok <- check_nfc(decoded),
         :ok <- reject_pure_ascii(decoded) do
      {:ok, decoded, true}
    end
  end

  defp check_nfc(text) do
    if :unicode.characters_to_nfc_binary(text) == text do
      :ok
    else
      {:error, :punycode_invalid}
    end
  end

  defp punycode_decode(rest) do
    case Punycode.decode(rest) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, :overflow} -> {:error, :punycode_overflow}
      {:error, :invalid_input} -> {:error, :punycode_invalid}
    end
  end

  defp reject_pure_ascii(text) do
    if ascii?(text), do: {:error, :punycode_invalid}, else: :ok
  end

  # UTS #46 §4.1 Validity Criteria.
  defp validate_label("", _from_ace?, _options), do: :ok

  defp validate_label(label, from_ace?, options) do
    with :ok <- check_hyphens(label, from_ace?, options),
         :ok <- check_leading_combining_mark(label),
         :ok <- check_codepoint_status(label, options),
         :ok <- check_joiners(label, options) do
      :ok
    end
  end

  defp check_hyphens(label, _from_ace?, options) do
    if not Keyword.fetch!(options, :check_hyphens) do
      :ok
    else
      cond do
        String.starts_with?(label, "-") -> {:error, :hyphen_violation}
        String.ends_with?(label, "-") -> {:error, :hyphen_violation}
        double_hyphen_at_3_4?(label) -> {:error, :hyphen_violation}
        true -> :ok
      end
    end
  end

  defp double_hyphen_at_3_4?(label) do
    case String.to_charlist(label) do
      [_, _, ?-, ?- | _] -> true
      _ -> false
    end
  end

  defp check_leading_combining_mark(label) do
    [first | _] = String.to_charlist(label)
    category = Unicode.GeneralCategory.category(first)

    if category in [:Mc, :Me, :Mn] do
      {:error, :leading_combining_mark}
    else
      :ok
    end
  end

  # UTS #46 §4.1 step 6 (and step 4 of the validity criteria for
  # post-mapping content). Each code point in the label must be
  # `:valid` (or `:deviation` in non-transitional mode). With STD3
  # enforcement, ASCII characters not in `[a-zA-Z0-9-]` are rejected.
  # Deviation code points are always considered valid here. The
  # `:transitional` flag only governs how deviations are handled in
  # the *input mapping* phase: under transitional processing they
  # have already been replaced by their target in `map_codepoints/2`,
  # so any deviation that survives to this point can only have
  # arrived via Punycode decoding of an ACE label. UTS #46 §4.1 step
  # 6's stricter wording (transitional ⇒ only `:valid`) is
  # contradicted by the IdnaTestV2 conformance suite, which treats
  # post-decode deviations as valid in both modes.
  defp check_codepoint_status(label, options) do
    std3? = Keyword.fetch!(options, :use_std3_ascii_rules)

    label
    |> String.to_charlist()
    |> Enum.reduce_while(:ok, fn cp, _acc ->
      cond do
        cp < 0x80 ->
          if std3? and not std3_valid_ascii?(cp) do
            {:halt, {:error, :disallowed}}
          else
            {:cont, :ok}
          end

        true ->
          case Mapping.lookup(cp) do
            {:valid, _} -> {:cont, :ok}
            {:deviation, _} -> {:cont, :ok}
            _ -> {:halt, {:error, :disallowed}}
          end
      end
    end)
  end

  defp std3_valid_ascii?(cp) when cp in ?a..?z, do: true
  defp std3_valid_ascii?(cp) when cp in ?A..?Z, do: true
  defp std3_valid_ascii?(cp) when cp in ?0..?9, do: true
  defp std3_valid_ascii?(?-), do: true
  defp std3_valid_ascii?(_), do: false

  defp check_joiners(label, options) do
    if Keyword.fetch!(options, :check_joiners), do: Context.validate(label), else: :ok
  end

  # RFC 5893 §1.4: A domain name is *bidi* if any label contains an
  # R, AL or AN character. In a bidi domain, every label (including
  # LTR labels) must satisfy the RFC 5893 bidi rule.
  defp check_domain_bidi(labels, options) do
    if Keyword.fetch!(options, :check_bidi) and bidi_domain?(labels) do
      Enum.reduce_while(labels, :ok, fn %{text: text}, _acc ->
        case Bidi.validate_in_bidi_domain(text) do
          :ok -> {:cont, :ok}
          {:error, _} = e -> {:halt, e}
        end
      end)
    else
      :ok
    end
  end

  defp bidi_domain?(labels) do
    Enum.any?(labels, fn %{text: text} ->
      text
      |> String.to_charlist()
      |> Enum.any?(&(BidiClass.bidi_class(&1) in [:r, :al, :an]))
    end)
  end

  # Encode each U-label to ASCII (Punycode + `xn--` if any non-ASCII).
  defp encode_labels(labels) do
    labels
    |> Enum.reduce_while({:ok, []}, fn label, {:ok, acc} ->
      case encode_label(label) do
        {:ok, encoded} -> {:cont, {:ok, [encoded | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp encode_label(%{text: "", ascii?: true}), do: {:ok, ""}
  defp encode_label(%{text: text, ascii?: true}), do: {:ok, text}

  defp encode_label(%{text: text, ascii?: false}) do
    case Punycode.encode(text) do
      {:ok, encoded} -> {:ok, @ace_prefix <> encoded}
      {:error, :overflow} -> {:error, :punycode_overflow}
    end
  end

  defp ascii?(text), do: text |> :binary.bin_to_list() |> Enum.all?(&(&1 < 0x80))

  # RFC 1035 — DNS labels must be 1–63 octets, full domain ≤ 253
  # octets (excluding the optional trailing `.`).
  defp verify_dns_length(labels, options) when is_list(options) do
    if Keyword.fetch!(options, :verify_dns_length) do
      do_verify_dns_length(labels)
    else
      :ok
    end
  end

  defp do_verify_dns_length(labels) do
    cond do
      labels == [] or labels == [""] -> {:error, :empty_label}
      Enum.any?(labels, &(&1 == "")) -> {:error, :empty_label}
      Enum.any?(labels, &(byte_size(&1) > 63)) -> {:error, :label_too_long}
      byte_size(Enum.join(labels, ".")) > 253 -> {:error, :domain_too_long}
      true -> :ok
    end
  end

  # The Unicode-side equivalent of the DNS length check. UTS #46
  # X4_2 fires when an *interior* label is empty; the trailing root
  # label of an FQDN is permitted (this is the divergence from
  # `do_verify_dns_length/1`, which rejects trailing roots too in
  # accordance with the IdnaTestV2 conformance suite).
  defp verify_unicode_length(labels, options) do
    if Keyword.fetch!(options, :verify_dns_length) do
      texts = Enum.map(labels, & &1.text)
      interior = drop_trailing_root(texts)

      cond do
        interior == [] -> {:error, :empty_label}
        Enum.any?(interior, &(&1 == "")) -> {:error, :empty_label}
        true -> :ok
      end
    else
      :ok
    end
  end

  defp drop_trailing_root([]), do: []

  defp drop_trailing_root(labels) do
    case List.last(labels) do
      "" -> Enum.drop(labels, -1)
      _ -> labels
    end
  end
end
