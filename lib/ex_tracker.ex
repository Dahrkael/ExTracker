defmodule ExTracker do

  def hello() do
    :world
  end

  def version do
    "0.4.0"
  end

  def web_about do
    "<p>ExTracker #{ExTracker.version()}</p><a href=\"https://github.com/Dahrkael/ExTracker\">https://github.com/Dahrkael/ExTracker</a>"
  end

  def console_about() do
    "--------------------------------------\n" <>
    " ExTracker #{ExTracker.version()}\n" <>
    " https://github.com/Dahrkael/ExTracker\n" <>
    "--------------------------------------"
  end

  def debug_enabled() do
    Application.get_env(:extracker, :debug, false)
  end
end
