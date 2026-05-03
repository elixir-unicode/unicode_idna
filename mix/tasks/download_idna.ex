defmodule Mix.Tasks.UnicodeIdna.Download do
  @moduledoc """
  Downloads the Unicode data files required to build `Unicode.IDNA`.

  The destination is `Unicode.IDNA.data_dir/0` and the files written
  are:

  * `idna_mapping_table.txt` — UTS #46 IDNA mapping table.

  * `idna_test_v2.txt` — UTS #46 conformance test vectors used by
    the test suite.

  The `Bidi_Class` and `Joining_Type` properties consumed by
  `Unicode.IDNA.Bidi` and `Unicode.IDNA.Context` come from the
  `unicode` package via `Unicode.bidi_class/1` and
  `Unicode.joining_type/1`; refresh them with `mix unicode.download`
  in that package.

  """

  use Mix.Task
  require Logger

  @shortdoc "Download Unicode IDNA data files"

  @unicode_full_release "17.0.0"

  @idna_root "https://www.unicode.org/Public/#{@unicode_full_release}/idna/"

  @unicode_unsafe_https "UNICODE_UNSAFE_HTTPS"
  @unicode_default_timeout "120000"
  @unicode_default_connection_timeout "60000"

  @doc false
  def run(_) do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    File.mkdir_p!(Unicode.IDNA.data_dir())

    Enum.each(required_files(), &download_file/1)
  end

  defp required_files do
    [
      {Path.join(@idna_root, "IdnaMappingTable.txt"), data_path("idna_mapping_table.txt")},
      {Path.join(@idna_root, "IdnaTestV2.txt"), data_path("idna_test_v2.txt")}
    ]
  end

  defp download_file({url, destination}) do
    case get(url) do
      {:ok, body} ->
        File.write!(destination, body)
        Logger.info("Downloaded #{inspect(url)} to #{inspect(destination)}")
        {:ok, destination}

      error ->
        Logger.error("Failed to download #{inspect(url)}: #{inspect(error)}")
        error
    end
  end

  @doc """
  Securely download HTTPS content from a URL.

  Uses the built-in `:httpc` client with peer verification enabled.

  ### Arguments

  * `url` is a binary URL.

  * `options` is a keyword list of options.

  ### Options

  * `:verify_peer` — boolean, default `true`. When `false`, peer
    certificate verification is skipped.

  * `:timeout` — request timeout in milliseconds. Defaults to
    `#{@unicode_default_timeout}`.

  * `:connection_timeout` — connection timeout in milliseconds.
    Defaults to `#{@unicode_default_connection_timeout}`.

  ### Returns

  * `{:ok, body}` on success.

  * `{:error, reason}` on failure. An error is also logged.

  """
  @spec get(String.t(), Keyword.t()) :: {:ok, binary} | {:error, any}
  def get(url, options \\ []) when is_binary(url) and is_list(options) do
    hostname = String.to_charlist(URI.parse(url).host)
    url = String.to_charlist(url)
    http_options = http_opts(hostname, options)

    case :httpc.request(:get, {url, []}, http_options, []) do
      {:ok, {{_version, 200, _}, _headers, body}} ->
        {:ok, :erlang.list_to_binary(body)}

      {:ok, {{_version, code, message}, _headers, _body}} ->
        Logger.error("HTTP #{code} #{inspect(message)} for #{inspect(url)}")
        {:error, code}

      {:error, {:failed_connect, [{_, {host, _port}}, {_, _, sys_message}]}} ->
        Logger.error("Failed to connect to #{inspect(host)}: #{inspect(sys_message)}")
        {:error, sys_message}

      {:error, reason} ->
        Logger.error("Download failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp data_path(filename) do
    Path.join(Unicode.IDNA.data_dir(), filename)
  end

  defp http_opts(hostname, options) do
    verify_peer? = Keyword.get(options, :verify_peer, true)
    timeout = Keyword.get(options, :timeout, default_timeout())
    connection_timeout = Keyword.get(options, :connection_timeout, default_connection_timeout())
    ssl_options = https_ssl_opts(hostname, verify_peer?)

    [timeout: timeout, connect_timeout: connection_timeout, ssl: ssl_options]
  end

  defp default_timeout do
    "UNICODE_HTTP_TIMEOUT"
    |> System.get_env(@unicode_default_timeout)
    |> String.to_integer()
  end

  defp default_connection_timeout do
    "UNICODE_HTTP_CONNECTION_TIMEOUT"
    |> System.get_env(@unicode_default_connection_timeout)
    |> String.to_integer()
  end

  defp https_ssl_opts(hostname, verify_peer?) do
    if secure_ssl?() and verify_peer? do
      [
        verify: :verify_peer,
        cacertfile: certificate_store(),
        depth: 4,
        versions: protocol_versions(),
        reuse_sessions: true,
        server_name_indication: hostname,
        secure_renegotiate: true,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    else
      [
        verify: :verify_none,
        server_name_indication: hostname,
        secure_renegotiate: true,
        reuse_sessions: true,
        versions: protocol_versions()
      ]
    end
  end

  defp protocol_versions do
    [:"tlsv1.2", :"tlsv1.3"]
  end

  defp secure_ssl? do
    case String.upcase(System.get_env(@unicode_unsafe_https, "TRUE")) do
      "FALSE" -> false
      "NIL" -> false
      _other -> true
    end
  end

  @static_certificate_locations [
    "/etc/ssl/certs/ca-certificates.crt",
    "/etc/pki/tls/certs/ca-bundle.crt",
    "/etc/ssl/ca-bundle.pem",
    "/etc/pki/tls/cacert.pem",
    "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem",
    "/usr/local/etc/openssl/cert.pem",
    "/etc/ssl/cert.pem"
  ]

  defp certificate_store do
    @static_certificate_locations
    |> Enum.find(&File.exists?/1)
    |> raise_if_no_cacertfile!()
    |> :erlang.binary_to_list()
  end

  defp raise_if_no_cacertfile!(nil) do
    raise RuntimeError, """
    No certificate trust store was found.
    Tried looking for: #{inspect(@static_certificate_locations)}.

    Set UNICODE_UNSAFE_HTTPS=true to skip peer verification (not recommended).
    """
  end

  defp raise_if_no_cacertfile!(file), do: file
end
