defmodule ExTracker.CLIReader do
  require Logger

  def read(args) do
    {opts, _rest, invalid} =
      OptionParser.parse(args,
        switches: [
          http_port: :integer,
          debug: :boolean
          ],
        aliases: [
          d: :debug
        ]
      )

    # show a warning for each unknown parameter in case someone misspelled something
    Enum.each(invalid, fn arg ->
      Logger.warning("unrecognized command line parameter '#{arg}'")
    end)

    # override the environment values with the new ones
    Enum.each(opts, fn {arg, value} ->
      Logger.info("overriding config from command line parameter '#{arg}': #{value}")
      Application.put_env(:extracker, arg, value)
    end)

    :ok
  end
end
