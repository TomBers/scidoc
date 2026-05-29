defmodule Sciencecritic.PaperQA.Selection do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sciencecritic.PaperQA.Question

  schema "paper_selections" do
    field :paper_id, :string
    field :section_id, :string
    field :block_id, :string
    field :selected_text, :string
    field :text_hash, :string

    has_many :questions, Question, foreign_key: :paper_selection_id

    timestamps(type: :utc_datetime)
  end

  def changeset(selection, attrs) do
    selection
    |> cast(attrs, [:paper_id, :section_id, :block_id, :selected_text, :text_hash])
    |> validate_required([:paper_id, :section_id, :block_id, :selected_text, :text_hash])
    |> validate_length(:selected_text, min: 1, max: 8_000)
    |> unique_constraint([:paper_id, :section_id, :block_id, :text_hash])
  end
end
