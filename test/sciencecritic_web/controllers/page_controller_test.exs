defmodule SciencecriticWeb.PageControllerTest do
  use SciencecriticWeb.ConnCase

  alias Sciencecritic.PaperQA

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ "Scientific papers should be semantic objects"
    assert html =~ "Problems exposed by one famous paper"
    assert html =~ "Accessibility is not optional metadata"
    assert html =~ "$50B–$200B+"
    assert html =~ "Export current demo package"
    assert html =~ "annotations/"
    assert html =~ "llm-questions.json"
  end

  test "GET /papers/attention/export downloads scidoc package with LLM questions", %{conn: conn} do
    {:ok, selection} =
      PaperQA.get_or_create_selection(%{
        "paper_id" => "attention-is-all-you-need",
        "section_id" => "attention",
        "block_id" => "compiled-block-42",
        "selected_text" => "multi-head attention"
      })

    {:ok, _question} = PaperQA.create_question(selection, "What does this mean here?")

    conn = get(conn, ~p"/papers/attention/export")
    archive = response(conn, 200)
    {:ok, entries} = :zip.extract(archive, [:memory])

    assert get_resp_header(conn, "content-disposition") == [
             ~s(attachment; filename="attention.scidoc.zip")
           ]

    assert get_resp_header(conn, "content-type") == ["application/zip; charset=utf-8"]

    files =
      Map.new(entries, fn {path, content} ->
        {List.to_string(path), content}
      end)

    assert Map.has_key?(files, "paper.scidoc/document.json")
    assert Map.has_key?(files, "paper.scidoc/render.html")
    assert Map.has_key?(files, "paper.scidoc/render.pdf")
    assert Map.has_key?(files, "paper.scidoc/assets/ms.css")
    assert Map.has_key?(files, "paper.scidoc/bibliography.json")
    assert Map.has_key?(files, "paper.scidoc/mappings/pdf-locations.json")
    assert Map.has_key?(files, "paper.scidoc/annotations/llm-questions.json")

    document = Jason.decode!(files["paper.scidoc/document.json"])
    annotations = Jason.decode!(files["paper.scidoc/annotations/llm-questions.json"])

    assert document["format"] == "sciencecritic.scidoc.package"
    assert document["version"] == 1
    assert "annotations/llm-questions.json" in document["manifest"]["files"]
    assert document["paper"]["id"] == "attention-is-all-you-need"
    assert document["semantic_graph"]["sections"] != []
    assert annotations["format"] == "sciencecritic.scidoc.llm_questions"

    [selection_export] = annotations["selections"]
    assert selection_export["selected_text"] == "multi-head attention"
    assert selection_export["section_id"] == "attention"

    [question_export] = selection_export["questions"]
    assert question_export["question"] == "What does this mean here?"
    assert question_export["answer"] =~ "Local fallback answer"
    assert question_export["status"] == "answered"
  end
end
