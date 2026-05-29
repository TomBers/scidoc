defmodule Sciencecritic.Repo.Migrations.CreatePaperQa do
  use Ecto.Migration

  def change do
    create table(:paper_selections) do
      add :paper_id, :string, null: false
      add :section_id, :string, null: false
      add :block_id, :string, null: false
      add :selected_text, :text, null: false
      add :text_hash, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:paper_selections, [:paper_id, :section_id, :block_id, :text_hash])

    create table(:paper_questions) do
      add :paper_selection_id, references(:paper_selections, on_delete: :delete_all), null: false
      add :parent_question_id, references(:paper_questions, on_delete: :nilify_all)
      add :question, :text, null: false
      add :answer, :text
      add :status, :string, null: false, default: "pending"
      add :error, :text
      add :prompt_payload, :text

      timestamps(type: :utc_datetime)
    end

    create index(:paper_questions, [:paper_selection_id])
    create index(:paper_questions, [:parent_question_id])
  end
end
