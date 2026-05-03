# Unicode IDNA

Pure-Elixir implementation of [UTS #46](https://www.unicode.org/reports/tr46/) *Unicode IDNA Compatibility Processing*, with [RFC 3492](https://www.rfc-editor.org/rfc/rfc3492) Punycode encoding/decoding, the [RFC 5893](https://www.rfc-editor.org/rfc/rfc5893) bidi rule, and CONTEXTJ joiner rules from [RFC 5892](https://www.rfc-editor.org/rfc/rfc5892).

The library converts domain names between their Unicode and ASCII (Punycode `xn--` prefixed) representations and validates that each label conforms to IDNA 2008 as relaxed by UTS #46. It passes the full [`IdnaTestV2.txt`](https://www.unicode.org/Public/17.0.0/idna/IdnaTestV2.txt) conformance suite — 6,389 rows × 3 operations = 19,167 assertions — for Unicode 17.0.

## Installation

```elixir
def deps do
  [
    {:unicode_idna, "~> 0.1"}
  ]
end
```

## Usage

`Unicode.IDNA.to_ascii/2` and `Unicode.IDNA.to_unicode/2` accept either a full domain name as a `String.t` or a list of labels. The return value mirrors the input shape: a string in returns a string out (labels are rejoined with `.`); a list in returns the list of processed labels.

```elixir
# String in / string out — full domain
iex> Unicode.IDNA.to_ascii("bücher.de")
{:ok, "xn--bcher-kva.de"}

iex> Unicode.IDNA.to_unicode("xn--bcher-kva.de")
{:ok, "bücher.de"}

# Alternate IDNA label separators are recognised
iex> Unicode.IDNA.to_ascii("中文。中国")
{:ok, "xn--fiq228c.xn--fiqs8s"}

# List in / list out — already-split labels
iex> Unicode.IDNA.to_ascii(["bücher", "de"])
{:ok, ["xn--bcher-kva", "de"]}

iex> Unicode.IDNA.to_unicode(["xn--bcher-kva", "de"])
{:ok, ["bücher", "de"]}

# Errors
iex> Unicode.IDNA.to_ascii("not_valid")
{:error, :disallowed}

iex> Unicode.IDNA.to_ascii("not_valid", use_std3_ascii_rules: false)
{:ok, "not_valid"}
```

## Public API

* `Unicode.IDNA.to_ascii/2` — UTS #46 ToASCII. Accepts a `t:String.t/0` or a list of label strings; returns the same shape.

* `Unicode.IDNA.to_unicode/2` — UTS #46 ToUnicode, with the same dual-shape semantics.

* `Unicode.IDNA.valid_label?/2` — predicate for a single label, equivalent to `match?({:ok, _}, to_ascii([label], options))`.

* `Unicode.IDNA.Punycode.encode/1` and `Unicode.IDNA.Punycode.decode/1` — RFC 3492 primitives.

* `Unicode.IDNA.Bidi.validate/1` and `validate_in_bidi_domain/1` — RFC 5893 bidi rule.

* `Unicode.IDNA.Context.validate/1` — RFC 5892 Appendix A CONTEXTJ rules for ZWJ / ZWNJ.

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `:transitional` | `false` | UTS #46 transitional vs. non-transitional processing. The default `false` matches modern browsers (Chrome, Firefox, Safari). |
| `:check_hyphens` | `true` | Reject leading/trailing hyphens and `--` at positions 3–4 (the latter is suppressed for labels that came from a Punycode-decoded ACE form). |
| `:check_bidi` | `true` | If any label contains a right-to-left character, every label in the domain must satisfy the RFC 5893 bidi rule. |
| `:check_joiners` | `true` | Labels containing ZWJ (U+200D) or ZWNJ (U+200C) must satisfy the CONTEXTJ rules of RFC 5892 Appendix A. |
| `:use_std3_ascii_rules` | `true` | Restrict ASCII characters in a label to letters, digits and hyphen. Set `false` to allow `_` and other STD3-disallowed ASCII (e.g. for Twitter-style permissive subdomain rules). |
| `:verify_dns_length` | `true` | Reject empty labels, labels longer than 63 octets, and full domains longer than 253 octets per RFC 1035. |

## Refreshing Unicode data

```bash
mix unicode_idna.download
```

This refreshes `data/idna_mapping_table.txt` and `data/idna_test_v2.txt` (the conformance vectors) from `unicode.org`. The bundled files are committed to source control; the task exists to make version bumps reproducible.
