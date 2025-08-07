defmodule Tesla.Middleware.ApiKeyAuth do
  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, opts \\ []) do
    apiKey = Keyword.get(opts, :api_key, "")

    env
    |> Tesla.put_headers([{"api_key", "#{apiKey}"}])
    |> Tesla.run(next)
  end
end

defmodule ExTracker.Integrations.Arcadia.API do
  use Tesla

  plug Tesla.Middleware.BaseUrl, Application.get_env(:extracker_arcadia, :site_host)
  plug Tesla.Middleware.JSON
  plug Tesla.Middleware.Headers, [{"user-agent", "ExTracker/#{ExTracker.version()} Arcadia Integration"}]
  plug Tesla.Middleware.ApiKeyAuth, [api_key: Application.get_env(:extracker_arcadia, :site_api_key)]
  plug Tesla.Middleware.Timeout, timeout: Application.get_env(:extracker, :http_request_timeout)
  plug Tesla.Middleware.Retry,
    delay: 1_000,
    max_retries: 3,
    max_delay: 10_000,
    should_retry: fn
      {:ok, %{status: code}} -> code in [408, 500, 502, 503, 504]
      {:error, reason} ->
        case reason do
          :timeout -> true
          :nxdomain -> true
          :econnrefused -> true
          _ -> false
        end
    end

  # GET /api/registered-torrents
  # application/json
  # id: i64
  # created_at: local DateTime String
  # info_hash: String
  def get_registered_torrents do
    case get("/api/registered-torrents") do
      {:ok, %Tesla.Env{status: 200, body: torrents}} ->
        {:ok, torrents}

      {:ok, %Tesla.Env{status: 401}} ->
        {:error, :wrong_credentials}

      {:ok, %Tesla.Env{status: 404}} ->
        {:error, :not_found}

      {:ok, %Tesla.Env{status: code}} when code in [500, 502, 503] ->
        {:error, :server_error}

      {:error, :timeout} ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, {:connection_failed, reason}}
    end
  end
end
