defmodule Unicode.IDNA.Test do
  use ExUnit.Case

  doctest Unicode.IDNA
  doctest Unicode.IDNA.Punycode
  doctest Unicode.IDNA.Mapping
  doctest Unicode.IDNA.Bidi
  doctest Unicode.IDNA.Context

  describe "to_ascii/2" do
    test "ASCII labels are downcased and returned as-is" do
      assert Unicode.IDNA.to_ascii("ASCII") == {:ok, "ascii"}
      assert Unicode.IDNA.to_ascii("a-b-c") == {:ok, "a-b-c"}
    end

    test "non-ASCII labels are Punycode-encoded with the xn-- prefix" do
      assert Unicode.IDNA.to_ascii("bücher") == {:ok, "xn--bcher-kva"}
      assert Unicode.IDNA.to_ascii("München") == {:ok, "xn--mnchen-3ya"}
      assert Unicode.IDNA.to_ascii("日本") == {:ok, "xn--wgv71a"}
      assert Unicode.IDNA.to_ascii("☃") == {:ok, "xn--n3h"}
    end

    test "ACE-form labels are accepted and re-emitted unchanged" do
      assert Unicode.IDNA.to_ascii("xn--bcher-kva") == {:ok, "xn--bcher-kva"}
      assert Unicode.IDNA.to_ascii("XN--BCHER-KVA") == {:ok, "xn--bcher-kva"}
    end

    test "STD3-disallowed ASCII characters are rejected by default" do
      assert Unicode.IDNA.to_ascii("not_valid") == {:error, :disallowed}
      assert Unicode.IDNA.to_ascii("a&b") == {:error, :disallowed}
    end

    test "STD3 check can be relaxed" do
      assert Unicode.IDNA.to_ascii("not_valid", use_std3_ascii_rules: false) ==
               {:ok, "not_valid"}
    end

    test "leading and trailing hyphens are rejected by check_hyphens" do
      assert Unicode.IDNA.to_ascii("-leading") == {:error, :hyphen_violation}
      assert Unicode.IDNA.to_ascii("trailing-") == {:error, :hyphen_violation}
    end

    test "double hyphen at positions 3-4 is rejected by check_hyphens" do
      assert Unicode.IDNA.to_ascii("ab--cd") == {:error, :hyphen_violation}
    end

    test "check_hyphens can be disabled" do
      assert Unicode.IDNA.to_ascii("-leading", check_hyphens: false) == {:ok, "-leading"}
      assert Unicode.IDNA.to_ascii("ab--cd", check_hyphens: false) == {:ok, "ab--cd"}
    end

    test "empty label is an error" do
      assert Unicode.IDNA.to_ascii("") == {:error, :empty_label}
    end

    test "labels longer than 63 octets are rejected" do
      long = String.duplicate("a", 64)
      assert Unicode.IDNA.to_ascii(long) == {:error, :label_too_long}
    end

    test "ignored code points are dropped" do
      # U+00AD soft hyphen has status :ignored
      assert Unicode.IDNA.to_ascii("ab­c") == {:ok, "abc"}
    end

    test "deviation: ß becomes ss in transitional mode but is preserved in nontransitional" do
      assert Unicode.IDNA.to_ascii("faß", transitional: true) == {:ok, "fass"}
      assert Unicode.IDNA.to_ascii("faß") == {:ok, "xn--fa-hia"}
    end
  end

  describe "to_unicode/2" do
    test "decodes ACE labels back to Unicode" do
      assert Unicode.IDNA.to_unicode("xn--bcher-kva") == {:ok, "bücher"}
      assert Unicode.IDNA.to_unicode("xn--mnchen-3ya") == {:ok, "münchen"}
    end

    test "ACE prefix is matched case-insensitively" do
      assert Unicode.IDNA.to_unicode("XN--BCHER-KVA") == {:ok, "bücher"}
    end

    test "Unicode labels pass through (mapped + normalized)" do
      assert Unicode.IDNA.to_unicode("bücher") == {:ok, "bücher"}
      assert Unicode.IDNA.to_unicode("ASCII") == {:ok, "ascii"}
    end

    test "rejects malformed Punycode" do
      assert Unicode.IDNA.to_unicode("xn--!!") == {:error, :punycode_invalid}
    end
  end

  describe "valid_label?/2" do
    test "true for labels that ToASCII accepts" do
      assert Unicode.IDNA.valid_label?("bücher")
      assert Unicode.IDNA.valid_label?("ASCII")
      assert Unicode.IDNA.valid_label?("xn--bcher-kva")
    end

    test "false for labels that ToASCII rejects" do
      refute Unicode.IDNA.valid_label?("not_valid")
      refute Unicode.IDNA.valid_label?("-bad")
      refute Unicode.IDNA.valid_label?("")
    end
  end

  describe "round-trip" do
    test "ToASCII followed by ToUnicode returns the original label" do
      for label <- ["bücher", "münchen", "日本", "☃", "ascii"] do
        {:ok, ace} = Unicode.IDNA.to_ascii(label)
        assert {:ok, ^label} = Unicode.IDNA.to_unicode(ace)
      end
    end
  end

  describe "full-domain string input" do
    test "to_ascii/2 splits, processes each label, rejoins" do
      assert Unicode.IDNA.to_ascii("bücher.de") == {:ok, "xn--bcher-kva.de"}
      assert Unicode.IDNA.to_ascii("foo.bar.baz") == {:ok, "foo.bar.baz"}
      assert Unicode.IDNA.to_ascii("中文。中国") == {:ok, "xn--fiq228c.xn--fiqs8s"}
    end

    test "to_unicode/2 splits, processes each label, rejoins" do
      assert Unicode.IDNA.to_unicode("xn--bcher-kva.de") == {:ok, "bücher.de"}
      assert Unicode.IDNA.to_unicode("BÜCHER.DE") == {:ok, "bücher.de"}
    end

    test "alternate IDNA label separators are recognised" do
      # U+3002 (CJK), U+FF0E (fullwidth), U+FF61 (halfwidth) all separate labels.
      assert Unicode.IDNA.to_ascii("a。b．c｡d") == {:ok, "a.b.c.d"}
    end

    test "an empty interior label is rejected by VerifyDnsLength" do
      assert Unicode.IDNA.to_ascii("a..b") == {:error, :empty_label}
    end
  end

  describe "list-of-labels input" do
    test "to_ascii/2 returns a list when given a list" do
      assert Unicode.IDNA.to_ascii(["bücher", "de"]) == {:ok, ["xn--bcher-kva", "de"]}
      assert Unicode.IDNA.to_ascii(["foo", "bar", "baz"]) == {:ok, ["foo", "bar", "baz"]}
    end

    test "to_unicode/2 returns a list when given a list" do
      assert Unicode.IDNA.to_unicode(["xn--bcher-kva", "de"]) == {:ok, ["bücher", "de"]}
    end

    test "list and string forms produce equivalent results" do
      {:ok, ascii_string} = Unicode.IDNA.to_ascii("bücher.de")
      {:ok, ascii_list} = Unicode.IDNA.to_ascii(["bücher", "de"])
      assert ascii_string == Enum.join(ascii_list, ".")
    end

    test "errors propagate from any label" do
      assert Unicode.IDNA.to_ascii(["good", "not_valid"]) == {:error, :disallowed}
    end

    test "domain-level bidi check applies to lists too" do
      # Mixing an LTR label `0a` (digit-first) with an RTL label `א`
      # in a bidi domain triggers the RFC 5893 bidi rule (B1).
      assert Unicode.IDNA.to_ascii(["0a", "א"]) == {:error, :bidi}
    end
  end

  describe "Punycode RFC 3492 §7.1 vectors" do
    @rfc_3492_vectors [
      {"münchen", "mnchen-3ya"},
      {"bücher", "bcher-kva"},
      # (B) Chinese (simplified)
      {"他们为什么不说中文", "ihqwcrb4cv8a8dqg056pqjye"},
      # (C) Chinese (traditional)
      {"他們爲什麽不說中文", "ihqwctvzc91f659drss3x8bo0yb"},
      # (G) Japanese
      {"3年B組金八先生", "3B-ww4c5e180e575a65lsy2b"},
      # (J) Russian
      {"почемужеонинеговорятпорусски", "b1abfaaepdrnnbgefbadotcwatmq2g4l"}
    ]

    for {unicode, ace} <- @rfc_3492_vectors do
      test "encode: #{unicode}" do
        assert Unicode.IDNA.Punycode.encode(unquote(unicode)) == {:ok, unquote(ace)}
      end

      test "decode: #{ace}" do
        assert Unicode.IDNA.Punycode.decode(unquote(ace)) == {:ok, unquote(unicode)}
      end
    end
  end

  describe "bidi rule" do
    test "pure-LTR labels are not subject to the bidi rule" do
      assert Unicode.IDNA.Bidi.validate("hello") == :ok
    end

    test "mixed LTR with RTL is rejected" do
      # RTL label may not contain Latin letters (they are :l class).
      assert Unicode.IDNA.Bidi.validate("שabc") == {:error, :bidi}
    end

    test "well-formed RTL label is accepted" do
      assert Unicode.IDNA.Bidi.validate("שלום") == :ok
    end
  end

  describe "CONTEXTJ" do
    test "isolated ZWNJ is rejected" do
      assert Unicode.IDNA.Context.validate("a‌b") == {:error, :context}
    end

    test "isolated ZWJ is rejected" do
      assert Unicode.IDNA.Context.validate("a‍b") == {:error, :context}
    end

    test "label without join controls is accepted" do
      assert Unicode.IDNA.Context.validate("hello") == :ok
    end
  end
end
