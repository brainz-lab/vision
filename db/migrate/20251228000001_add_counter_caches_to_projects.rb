class AddCounterCachesToProjects < ActiveRecord::Migration[8.1]
  def change
    # Add counter cache columns for efficient counting
    add_column :projects, :pages_count, :integer, default: 0, null: false
    add_column :projects, :test_runs_count, :integer, default: 0, null: false

    # Add index on created_at for ORDER BY optimization
    add_index :projects, :created_at

    # Populate counter caches with existing data
    reversible do |dir|
      dir.up do
        execute <<-SQL.squish
          UPDATE projects
          SET pages_count = (SELECT COUNT(*) FROM pages WHERE pages.project_id = projects.id),
              test_runs_count = (SELECT COUNT(*) FROM test_runs WHERE test_runs.project_id = projects.id)
        SQL
      end
    end
  end
end
