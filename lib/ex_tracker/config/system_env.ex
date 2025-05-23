defmodule Extracker.Config.SystemEnvironment do
  @moduledoc """
  Module to dynamically override the application configuration of :extracker
  using environment variables. For each configuration key defined,
  the corresponding environment variable is generated using the prefix
  "EXTRACKER_". For example, the key :http_port will be mapped to EXTRACKER_HTTP_PORT
  """

  @app :extracker
  @prefix "EXTRACKER_"

  @doc """
  Loads environment variables for the :extracker configuration and overrides
  its values if corresponding environment variables are defined.
  """
  def load() do
    Application.get_all_env(@app)
    |> Enum.each(fn {key, default} ->
      env_name = generate_env_var_name(key)

      case System.get_env(env_name) do
        nil -> :ok
        env_val -> Application.put_env(@app, key, convert_value(env_val, default))
      end
    end)

    :ok
  end

  defp generate_env_var_name(key) when is_atom(key) do
    @prefix <> (Atom.to_string(key) |> String.upcase())
  end

  defp convert_value(val, default) when is_boolean(default) do
    String.trim(String.downcase(val)) == "true"
  end

  defp convert_value(val, default) when is_integer(default) do
    case Integer.parse(String.trim(val)) do
      {int_val, _} -> int_val
      :error -> default
    end
  end

  defp convert_value(val, default) when is_float(default) do
    case Float.parse(String.trim(val)) do
      {float_val, _} -> float_val
      :error -> default
    end
  end

  defp convert_value(val, default) when is_tuple(default) do
    # Assume a tuple is used for an IP, e.g. "0.0.0.0"
    parts = String.split(String.trim(val), ".")
    if length(parts) == tuple_size(default) do
      parts
      |> Enum.map(&String.to_integer/1)
      |> List.to_tuple()
    else
      default
    end
  end

  defp convert_value(val, default) when is_binary(default), do: val
  defp convert_value(val, _default), do: val
end
