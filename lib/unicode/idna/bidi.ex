defmodule Unicode.IDNA.Bidi do
  @moduledoc """
  RFC 5893 *Right-to-Left Scripts for Internationalized Domain
  Names* — the IDNA 2008 bidi rule.

  A label is *Bidi* if it contains any character whose `Bidi_Class`
  is `R`, `AL` or `AN`. The bidi rule applies only to bidi labels;
  pure-LTR labels are unaffected.

  """

  alias Unicode.BidiClass

  @doc """
  Returns `true` if the label contains a right-to-left character
  and therefore must satisfy the bidi rule.

  ### Examples

      iex> Unicode.IDNA.Bidi.bidi_label?("hello")
      false

      iex> Unicode.IDNA.Bidi.bidi_label?("שלום")
      true

  """
  @spec bidi_label?(String.t()) :: boolean
  def bidi_label?(label) when is_binary(label) do
    label
    |> String.to_charlist()
    |> Enum.any?(&rtl?/1)
  end

  defp rtl?(codepoint) do
    BidiClass.bidi_class(codepoint) in [:r, :al, :an]
  end

  @doc """
  Validates a label against the RFC 5893 bidi rule.

  ### Arguments

  * `label` is a `t:String.t/0` representing one already-mapped
    domain label.

  ### Returns

  * `:ok` if the label satisfies the bidi rule (or is not a bidi
    label).

  * `{:error, :bidi}` otherwise.

  ### Examples

      iex> Unicode.IDNA.Bidi.validate("hello")
      :ok

      iex> Unicode.IDNA.Bidi.validate("שלום")
      :ok

  """
  @spec validate(String.t()) :: :ok | {:error, :bidi}
  def validate(label) when is_binary(label) do
    codepoints = String.to_charlist(label)

    if Enum.any?(codepoints, &rtl?/1) do
      check_bidi(codepoints)
    else
      :ok
    end
  end

  @doc """
  Validates a label *as part of a bidi domain*.

  RFC 5893 §1.4 requires that, in a domain name containing at least
  one right-to-left label, every label — including LTR labels —
  satisfies the bidi rule. Use this function to enforce that
  whole-domain rule label-by-label; use `validate/1` for isolated
  labels that are not known to be part of a bidi domain.

  ### Examples

      iex> Unicode.IDNA.Bidi.validate_in_bidi_domain("hello")
      :ok

      iex> Unicode.IDNA.Bidi.validate_in_bidi_domain("0a")
      {:error, :bidi}

  """
  @spec validate_in_bidi_domain(String.t()) :: :ok | {:error, :bidi}
  def validate_in_bidi_domain(label) when is_binary(label) do
    if label == "" do
      :ok
    else
      check_bidi(String.to_charlist(label))
    end
  end

  defp check_bidi([]), do: {:error, :bidi}

  defp check_bidi([first | _] = codepoints) do
    classes = Enum.map(codepoints, &BidiClass.bidi_class/1)
    first_class = BidiClass.bidi_class(first)

    cond do
      first_class in [:r, :al] -> check_rtl(classes)
      first_class == :l -> check_ltr(classes)
      true -> {:error, :bidi}
    end
  end

  @rtl_allowed [:r, :al, :an, :en, :es, :cs, :et, :on, :bn, :nsm]
  @rtl_end [:r, :al, :en, :an]

  defp check_rtl(classes) do
    cond do
      not Enum.all?(classes, &(&1 in @rtl_allowed)) ->
        {:error, :bidi}

      true ->
        end_class = trailing_non_nsm(classes)
        has_en? = :en in classes
        has_an? = :an in classes

        cond do
          end_class not in @rtl_end -> {:error, :bidi}
          has_en? and has_an? -> {:error, :bidi}
          true -> :ok
        end
    end
  end

  @ltr_allowed [:l, :en, :es, :cs, :et, :on, :bn, :nsm]
  @ltr_end [:l, :en]

  defp check_ltr(classes) do
    cond do
      not Enum.all?(classes, &(&1 in @ltr_allowed)) ->
        {:error, :bidi}

      true ->
        end_class = trailing_non_nsm(classes)
        if end_class in @ltr_end, do: :ok, else: {:error, :bidi}
    end
  end

  defp trailing_non_nsm(classes) do
    classes
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 == :nsm))
    |> List.first()
  end
end
