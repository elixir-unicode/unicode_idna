# Changelog

## Unicode IDNA [v0.1.0] 2026-05-04

Initial release.

### Public API

* `Unicode.IDNA.to_ascii/2` and `Unicode.IDNA.to_unicode/2` — per-label UTS #46 ToASCII and ToUnicode.

* `Unicode.IDNA.domain_to_ascii/2` and `Unicode.IDNA.domain_to_unicode/2` — full-domain wrappers that split on the IDNA label separators (`.`, `U+3002`, `U+FF0E`, `U+FF61`), apply mapping/normalization, validate per §4.1, and re-join.

* `Unicode.IDNA.valid_label?/2` — predicate equivalent to a successful `to_ascii/2`.

* RFC 3492 Punycode primitives in `Unicode.IDNA.Punycode`: `encode/1` and `decode/1`.

* `Unicode.IDNA.Bidi.validate/1` and `validate_in_bidi_domain/1` for callers that want to apply the RFC 5893 bidi rule directly.

* `Unicode.IDNA.Context.validate/1` for the RFC 5892 Appendix A CONTEXTJ rules (ZWJ / ZWNJ).

### Options

`:transitional`, `:check_hyphens`, `:check_bidi`, `:check_joiners`, `:use_std3_ascii_rules`, `:verify_dns_length` — all default to modern-browser behaviour (non-transitional, all checks on).

### Conformance

Passes the full UTS #46 `IdnaTestV2.txt` conformance suite — 6,389 rows × 3 operations = 19,167 assertions, all green.

### Data sources

* `data/idna_mapping_table.txt` and `data/idna_test_v2.txt` are bundled at compile time; refresh with `mix unicode_idna.download`.

* `Bidi_Class` and `Joining_Type` are consumed from [`unicode ~> 1.22`](https://hex.pm/packages/unicode) via `Unicode.bidi_class/1` and `Unicode.joining_type/1`. Refresh those tables with `mix unicode.download` in that package.

* Built against [Unicode 17.0](https://www.unicode.org/versions/Unicode17.0.0/).
