defmodule Sciencecritic.PaperQA do
  @moduledoc """
  Persistence and orchestration for grounded paper questions.
  """

  import Ecto.Query

  alias Sciencecritic.PaperQA.Question
  alias Sciencecritic.PaperQA.QuestionAnswerer
  alias Sciencecritic.PaperQA.Selection
  alias Sciencecritic.Repo

  def selection_attrs(attrs) do
    selected_text = attrs["selected_text"] || attrs[:selected_text] || ""

    %{
      paper_id: attrs["paper_id"] || attrs[:paper_id],
      section_id: attrs["section_id"] || attrs[:section_id] || "unknown section",
      block_id: attrs["block_id"] || attrs[:block_id] || "unknown block",
      selected_text: selected_text,
      text_hash: hash_text(selected_text)
    }
  end

  def get_or_create_selection(attrs) do
    attrs = selection_attrs(attrs)

    case Repo.one(selection_lookup_query(attrs)) do
      nil ->
        %Selection{}
        |> Selection.changeset(attrs)
        |> Repo.insert()

      selection ->
        {:ok, selection}
    end
  end

  def get_selection_by_attrs(attrs) do
    attrs = selection_attrs(attrs)

    attrs
    |> selection_lookup_query()
    |> Repo.one()
  end

  def create_question(selection_or_attrs, question_text, opts \\ [])

  def create_question(%Selection{} = selection, question_text, opts) do
    parent_question_id = Keyword.get(opts, :parent_question_id)
    previous_questions = previous_questions(selection.id, parent_question_id)
    question_text = String.trim(question_text)

    with nil <- get_existing_question(selection.id, parent_question_id, question_text),
         {:ok, question} <-
           %Question{}
           |> Question.changeset(%{
             paper_selection_id: selection.id,
             parent_question_id: parent_question_id,
             question: question_text,
             status: "pending"
           })
           |> Repo.insert() do
      case QuestionAnswerer.answer(selection, question_text, previous_questions) do
        {:ok, answer, prompt} ->
          update_question(question, %{
            answer: answer,
            prompt_payload: prompt,
            status: "answered",
            error: nil
          })

        {:error, reason, prompt} ->
          update_question(question, %{
            prompt_payload: prompt,
            status: "failed",
            error: reason
          })
      end
    else
      %Question{} = question -> {:ok, question}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def create_question(selection_attrs, question_text, opts) do
    with {:ok, selection} <- get_or_create_selection(selection_attrs) do
      create_question(selection, question_text, opts)
    end
  end

  def list_selection_questions(selection_id) do
    Question
    |> where([question], question.paper_selection_id == ^selection_id)
    |> order_by([question], asc: question.inserted_at, asc: question.id)
    |> Repo.all()
  end

  def list_paper_selections(paper_id) do
    Selection
    |> where([selection], selection.paper_id == ^paper_id)
    |> order_by([selection], desc: selection.updated_at, desc: selection.id)
    |> preload(questions: ^question_order_query())
    |> Repo.all()
  end

  def list_paper_question_selections(paper_id) do
    Selection
    |> where([selection], selection.paper_id == ^paper_id)
    |> join(:inner, [selection], question in assoc(selection, :questions))
    |> distinct(true)
    |> order_by([selection], asc: selection.inserted_at, asc: selection.id)
    |> preload(questions: ^question_order_query())
    |> Repo.all()
  end

  def get_selection_with_questions(selection_id) do
    Selection
    |> preload(questions: ^question_order_query())
    |> Repo.get(selection_id)
  end

  defp selection_lookup_query(attrs) do
    from selection in Selection,
      where:
        selection.paper_id == ^attrs.paper_id and
          selection.section_id == ^attrs.section_id and
          selection.block_id == ^attrs.block_id and
          selection.text_hash == ^attrs.text_hash,
      preload: [questions: ^question_order_query()]
  end

  defp question_order_query do
    from question in Question,
      order_by: [asc: question.inserted_at, asc: question.id]
  end

  defp update_question(%Question{} = question, attrs) do
    question
    |> Question.changeset(attrs)
    |> Repo.update()
  end

  defp get_existing_question(selection_id, nil, question_text) do
    Question
    |> where(
      [question],
      question.paper_selection_id == ^selection_id and
        is_nil(question.parent_question_id) and
        question.question == ^question_text
    )
    |> order_by([question], asc: question.id)
    |> limit(1)
    |> Repo.one()
  end

  defp get_existing_question(selection_id, parent_question_id, question_text) do
    Question
    |> where(
      [question],
      question.paper_selection_id == ^selection_id and
        question.parent_question_id == ^parent_question_id and
        question.question == ^question_text
    )
    |> order_by([question], asc: question.id)
    |> limit(1)
    |> Repo.one()
  end

  defp previous_questions(_selection_id, nil), do: []

  defp previous_questions(selection_id, parent_question_id) do
    questions = list_selection_questions(selection_id)
    parent_index = Enum.find_index(questions, &(&1.id == parent_question_id))

    if parent_index do
      Enum.take(questions, parent_index + 1)
    else
      []
    end
  end

  defp hash_text(text) do
    :crypto.hash(:sha256, text)
    |> Base.encode16(case: :lower)
  end
end
