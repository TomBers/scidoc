defmodule SciencecriticWeb.PageController do
  use SciencecriticWeb, :controller

  alias Sciencecritic.PaperPackage

  def home(conn, _params) do
    render(conn, :home)
  end

  def export_attention(conn, _params) do
    conn
    |> put_resp_content_type("application/zip")
    |> put_resp_header("content-disposition", ~s(attachment; filename="attention.scidoc.zip"))
    |> send_resp(200, PaperPackage.attention_archive())
  end
end
