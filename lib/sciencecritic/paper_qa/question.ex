defmodule Sciencecritic.PaperQA.Question do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sciencecritic.PaperQA.Selection

  @statuses ~w(pending answered failed)

  schema "paper_questions" do
    field :question, :string
    field :answer, :string
    field :status, :string, default: "pending"
    field :error, :string
    field :prompt_payload, :string

    belongs_to :selection, Selection, foreign_key: :paper_selection_id
    belongs_to :parent_question, __MODULE__
    has_many :follow_up_questions, __MODULE__, foreign_key: :parent_question_id

    timestamps(type: :utc_datetime)
  end

  def changeset(question, attrs) do
    question
    |> cast(attrs, [
      :paper_selection_id,
      :parent_question_id,
      :question,
      :answer,
      :status,
      :error,
      :prompt_payload
    ])
    |> validate_required([:paper_selection_id, :question, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:question, min: 1, max: 2_000)
    |> validate_length(:answer, max: 20_000)
    |> foreign_key_constraint(:paper_selection_id)
    |> foreign_key_constraint(:parent_question_id)
  end
end
