require 'sequel'
Sequel.extension :migration
require 'yaml'

class Definition
  class << self
    attr_accessor :table_name

    def table
      DB[table_name]
    end

    def ensure_table_exists
      DB.create_table? table_name do
        primary_key :id
        column :sequence, :text, :null => false
        column :create_sql, :text, :null => false
        column :drop_sql, :text, :null => false
      end
    end

    def load_existing
      table.order(:id).all.map do |row|
        new row[:id], row[:sequence], row[:create_sql], row[:drop_sql]
      end.group_by { |d| d.sequence }
    end
  end

  attr_reader :id
  attr_reader :sequence
  attr_reader :create_sql
  attr_reader :drop_sql

  def initialize(id, sequence, create_sql, drop_sql)
    @id = id
    @sequence = sequence
    @create_sql = create_sql
    @drop_sql = drop_sql
  end

  def create
    DB.run create_sql
    table.insert :sequence => sequence, :create_sql => create_sql, :drop_sql => drop_sql
  end

  def drop
    DB.run drop_sql
    table.filter(:id => id).delete
  end

  def table
    self.class.table
  end
end

class Tern
  def initialize(alterations_table, alterations_column, definitions_table)
    @alterations_table = alterations_table.to_sym
    @alterations_column = alterations_column.to_sym

    Definition.table_name = definitions_table.to_sym
    Definition.ensure_table_exists
    @existing_definitions = Definition.load_existing
    @target_definitions = load_target_definitions
  end

  def migrate(options={})
    sequences = options[:sequences] || ['default']
    DB.transaction do
      drop_existing_definitions(sequences)
      run_alterations(options[:version])
      create_target_definitions(sequences)
    end
  end

  private
    def run_alterations(version=nil)
      unless Dir.glob("alterations/[0-9]*.rb").empty?
        Sequel::Migrator.run(DB, 'alterations', :table => @alterations_table, :column => @alterations_column, :target => version)
      end
    end

    def drop_existing_definitions(sequences)
      sequences.each do |s|
        sequence = @existing_definitions[s]
        if sequence
          sequence.reverse.each do |definition|
            definition.drop
          end
        end
      end
    end

    def create_target_definitions(sequences)
      sequences.each do |s|
        sequence = @target_definitions[s]
        if sequence
          sequence.each do |definition|
            definition.create
          end
        end
      end
    end

    def load_target_definitions
      definition_sequences = YAML.load(File.read('definitions/sequence.yml'))
      
      definition_sequences.keys.each do |sequence|
        definition_sequences[sequence] = definition_sequences[sequence].map do |f|
          create_sql, drop_sql = File.read('definitions/' + f).split('---- CREATE above / DROP below ----')
          Definition.new nil, sequence, create_sql, drop_sql
        end
      end

      definition_sequences
    end
end
