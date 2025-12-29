class AddBaselinesCountToPages < ActiveRecord::Migration[8.1]
  def change
    add_column :pages, :baselines_count, :integer, default: 0, null: false

    reversible do |dir|
      dir.up do
        execute <<-SQL.squish
          UPDATE pages
          SET baselines_count = (
            SELECT COUNT(*)
            FROM baselines
            WHERE baselines.page_id = pages.id
          )
        SQL
      end
    end
  end
end
