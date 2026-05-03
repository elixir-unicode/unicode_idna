defmodule Unicode.IDNA.Context do
  @moduledoc """
  RFC 5892 Appendix A *CONTEXTJ* rules for the join-control
  characters Zero Width Non-Joiner (U+200C) and Zero Width Joiner
  (U+200D).

  These rules govern when a join control may appear in a label
  based on the surrounding code points' `Joining_Type` and
  `Canonical_Combining_Class` properties.

  """

  alias Unicode.JoiningType

  @zwnj 0x200C
  @zwj 0x200D
  @virama 9

  @doc """
  Validates a label against the CONTEXTJ rules for ZWJ and ZWNJ.

  ### Arguments

  * `label` is a `t:String.t/0` representing one already-mapped
    domain label.

  ### Returns

  * `:ok` if every join control in the label is in a permitted
    context (or if the label contains no join controls).

  * `{:error, :context}` otherwise.

  ### Examples

      iex> Unicode.IDNA.Context.validate("hello")
      :ok

      iex> Unicode.IDNA.Context.validate("hello\\u200Cworld")
      {:error, :context}

  """
  @spec validate(String.t()) :: :ok | {:error, :context}
  def validate(label) when is_binary(label) do
    codepoints = String.to_charlist(label)
    walk(codepoints, [])
  end

  defp walk([], _before), do: :ok

  defp walk([@zwnj | after_cps], before_reversed) do
    if zwnj_allowed?(before_reversed, after_cps) do
      walk(after_cps, [@zwnj | before_reversed])
    else
      {:error, :context}
    end
  end

  defp walk([@zwj | after_cps], before_reversed) do
    if zwj_allowed?(before_reversed) do
      walk(after_cps, [@zwj | before_reversed])
    else
      {:error, :context}
    end
  end

  defp walk([cp | after_cps], before_reversed) do
    walk(after_cps, [cp | before_reversed])
  end

  # RFC 5892 A.1 — ZWNJ allowed if:
  #   * Canonical_Combining_Class(Before(cp)) == Virama, OR
  #   * label matches (L|D) T* ZWNJ T* (R|D) around the join control.
  defp zwnj_allowed?(before_reversed, after_cps) do
    previous_is_virama?(before_reversed) or zwnj_joiner_context?(before_reversed, after_cps)
  end

  defp previous_is_virama?([]), do: false

  defp previous_is_virama?([prev | _]) do
    Unicode.CanonicalCombiningClass.combining_class(prev) == @virama
  end

  defp zwnj_joiner_context?(before_reversed, after_cps) do
    has_left_joiner?(before_reversed) and has_right_joiner?(after_cps)
  end

  defp has_left_joiner?(before_reversed) do
    case Enum.drop_while(before_reversed, &(JoiningType.joining_type(&1) == :t)) do
      [cp | _] -> JoiningType.joining_type(cp) in [:l, :d]
      [] -> false
    end
  end

  defp has_right_joiner?(after_cps) do
    case Enum.drop_while(after_cps, &(JoiningType.joining_type(&1) == :t)) do
      [cp | _] -> JoiningType.joining_type(cp) in [:r, :d]
      [] -> false
    end
  end

  # RFC 5892 A.2 — ZWJ allowed only if Canonical_Combining_Class(Before(cp)) == Virama.
  defp zwj_allowed?(before_reversed) do
    previous_is_virama?(before_reversed)
  end
end
