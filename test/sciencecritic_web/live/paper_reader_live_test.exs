defmodule SciencecriticWeb.PaperReaderLiveTest do
  use SciencecriticWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Sciencecritic.PaperQA

  test "renders the semantic science paper demonstration", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/papers/attention")

    assert has_element?(view, "#paper-reader[phx-hook='PaperReader']")
    assert has_element?(view, ".paper-document[data-paper-id='attention-is-all-you-need']")

    assert has_element?(
             view,
             "#paper-compiled-root[data-paper-compiled-root][phx-update='ignore']"
           )

    assert has_element?(view, "#paper-workspace-ai[data-paper-workspace-panel]")
    assert has_element?(view, "[data-paper-workspace-panel]", "Q&A")
    assert has_element?(view, "a.paper-package-export-link[href='/papers/attention/export']")
    assert has_element?(view, "[data-paper-style-kind='theme']")
    assert has_element?(view, "[data-paper-style-kind='font']")
    assert has_element?(view, "[data-paper-style-kind='spacing']")
    assert has_element?(view, ".paper-workspace-intro.semantic-paper-header")
    assert has_element?(view, ".paper-ai-history-panel")
    refute has_element?(view, ".paper-document-header")
    assert has_element?(view, "#paper-section-navigator details")
    assert has_element?(view, "[data-paper-nav-target='introduction']")
    assert has_element?(view, "[data-paper-selection-text]")

    html = render(view)
    assert html =~ "Attention Is All You Need"
    assert html =~ "Q&amp;A"
    assert html =~ "Ask about this selection"
    assert html =~ "/generated_papers/attention/ms.html"
    refute html =~ "LaTeX.js renderer"
    refute html =~ "document-scene"
  end

  test "stores a selected passage question and follow-up", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/papers/attention")

    selection_attrs = %{
      "selected_text" => "self-attention",
      "section_id" => "attention",
      "block_id" => "compiled-block-42"
    }

    render_hook(view, "paper_selection_captured", selection_attrs)

    assert has_element?(view, "#paper-selection-question-form")

    view
    |> form("#paper-selection-question-form", qa: %{question: "What does this mean here?"})
    |> render_submit()

    view
    |> form("#paper-selection-question-form", qa: %{question: "What does this mean here?"})
    |> render_submit()

    {:ok, selection} =
      PaperQA.get_or_create_selection(
        Map.put(selection_attrs, "paper_id", "attention-is-all-you-need")
      )

    questions = PaperQA.list_selection_questions(selection.id)
    assert length(questions) == 1

    assert has_element?(view, ".paper-question-thread article")
    html = render(view)
    assert html =~ "Local fallback answer"
    [_, question_id] = Regex.run(~r/id="paper-follow-up-form-(\d+)"/, html)

    view
    |> form("#paper-follow-up-form-#{question_id}",
      follow_up: %{parent_question_id: question_id, question: "Why is it important?"}
    )
    |> render_submit()

    html = render(view)
    assert html =~ "Why is it important?"
    assert html =~ "previous question"
  end

  test "browses saved questions on page load", %{conn: conn} do
    {:ok, selection} =
      PaperQA.get_or_create_selection(%{
        "paper_id" => "attention-is-all-you-need",
        "section_id" => "scaled-dot-product-attention",
        "block_id" => "compiled-block-123",
        "selected_text" => "Scaled Dot-Product Attention"
      })

    {:ok, _question} =
      PaperQA.create_question(
        selection,
        "What does Scaled Dot-Product Attention mean in this paper?"
      )

    {:ok, view, _html} = live(conn, ~p"/papers/attention")

    assert has_element?(view, ".paper-saved-questions")
    assert has_element?(view, "[data-paper-saved-selection-link]")

    html = render(view)
    assert html =~ "Scaled Dot-Product Attention"
    assert html =~ "1 shared"

    view
    |> element("[data-paper-saved-selection-link]")
    |> render_click()

    assert has_element?(view, "#paper-selection-question-form")
    assert render(view) =~ "What does Scaled Dot-Product Attention mean in this paper?"
  end
end
