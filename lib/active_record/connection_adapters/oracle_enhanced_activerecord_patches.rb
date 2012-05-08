# ActiveRecord 2.3 patches
if ActiveRecord::VERSION::MAJOR == 2 && ActiveRecord::VERSION::MINOR == 3
  require "active_record/associations"

  ActiveRecord::Associations::ClassMethods.module_eval do
    private
    def tables_in_string(string)
      return [] if string.blank?
      if self.connection.adapter_name == "OracleEnhanced"
        # always convert table names to downcase as in Oracle quoted table names are in uppercase
        # ignore raw_sql_ that is used by Oracle adapter as alias for limit/offset subqueries
        string.scan(/([a-zA-Z_][\.\w]+).?\./).flatten.map(&:downcase).uniq - ['raw_sql_']
      else
        string.scan(/([\.a-zA-Z_]+).?\./).flatten
      end
    end
  end

  ActiveRecord::Associations::ClassMethods::JoinDependency::JoinAssociation.class_eval do
    protected
    def aliased_table_name_for(name, suffix = nil)
      # always downcase quoted table name as Oracle quoted table names are in uppercase
      if !parent.table_joins.blank? && parent.table_joins.to_s.downcase =~ %r{join(\s+\w+)?\s+#{active_record.connection.quote_table_name(name).downcase}\son}
        @join_dependency.table_aliases[name] += 1
      end

      unless @join_dependency.table_aliases[name].zero?
        # if the table name has been used, then use an alias
        name = active_record.connection.table_alias_for "#{pluralize(reflection.name)}_#{parent_table_name}#{suffix}"
        table_index = @join_dependency.table_aliases[name]
        @join_dependency.table_aliases[name] += 1
        name = name[0..active_record.connection.table_alias_length-3] + "_#{table_index+1}" if table_index > 0
      else
        @join_dependency.table_aliases[name] += 1
      end

      name
    end
  end

end


# Rails 2.3 and 3.0 patch to avoid "ORA-01795: maximum number of expressions in a list is 1000" errors
# when including more than 1000 associated records in a preloaded query
# i.e. Post.all(:include=>:comments) when a Post has_many :comments
#      or Post.all(:include=>:tags) when a Post has_and_belongs_to_many :tags
# The has_many case is fairly clean and works through inheritance and super
# but the habtm case requires pasting the active record implementation here and overriding it
# so will need to be checked and updated if/when active record's implementation of
# preload_has_and_belongs_to_many_association changes in assocation_preload.rb
if [[2,3], [3,0]].include? [ActiveRecord::VERSION::MAJOR, ActiveRecord::VERSION::MINOR]
  require "active_record/association_preload"

  module ActiveRecord
    module AssociationPreload
      MAX_IDS_PER_ORACLE_QUERY = 1000

      # has_many patch for both Rails 2.3 and 3.0
      module OracleEnhancedAdapterPatch
        private

        # Make multiple requests of up to 1000 ids at a time to avoid ORA-01795: maximum number of expressions in a list is 1000
        def find_associated_records(ids, reflection, preload_options)
          associated_records = []
          ids.each_slice(MAX_IDS_PER_ORACLE_QUERY) do |safe_for_oracle_ids|
            associated_records += super(safe_for_oracle_ids, reflection, preload_options)
          end
          associated_records
        end
      end

      ActiveRecord::Base.class_eval do
        extend ActiveRecord::AssociationPreload::OracleEnhancedAdapterPatch
      end


      # habtm patch for Rails 2.3 and 3.0 (separate patches below)
      ClassMethods.module_eval do
        private
        # WARNING we are pasting the ActiveRecord implementations directly in here so this will likely break in a future version.
        # Sorry, I could not think of another way to extend preload_has_and_belongs_to_many_association more cleanly as it does not take
        # ids as a parameter.
        # There may need to be more if cases for 3.1 or even 3.0.2!
        # Keep a close eye on https://github.com/rails/rails/blob/master/activerecord/lib/active_record/association_preload.rb

        if [2,3] == [ActiveRecord::VERSION::MAJOR, ActiveRecord::VERSION::MINOR]
          # The Rails 2.3 method from association_preload.rb
          def preload_has_and_belongs_to_many_association(records, reflection, preload_options={})
            table_name = reflection.klass.quoted_table_name
            id_to_record_map, ids = construct_id_map(records)
            records.each {|record| record.send(reflection.name).loaded}
            options = reflection.options

            conditions = "t0.#{reflection.primary_key_name} #{in_or_equals_for_ids(ids)}"
            conditions << append_conditions(reflection, preload_options)

            # Make several queries with no more than 1000 ids in each one, combining the results into a single array
            associated_records = []
            ids.each_slice(MAX_IDS_PER_ORACLE_QUERY) do |safe_for_oracle_ids|
              associated_records += reflection.klass.with_exclusive_scope do
                reflection.klass.find(:all, :conditions => [conditions, safe_for_oracle_ids],
                  :include => options[:include],
                  :joins => "INNER JOIN #{connection.quote_table_name options[:join_table]} t0 ON #{reflection.klass.quoted_table_name}.#{reflection.klass.primary_key} = t0.#{reflection.association_foreign_key}",
                  :select => "#{options[:select] || table_name+'.*'}, t0.#{reflection.primary_key_name} as the_parent_record_id",
                  :order => options[:order])
              end
            end
            set_association_collection_records(id_to_record_map, reflection.name, associated_records, 'the_parent_record_id')
          end

        elsif [3,0] == [ActiveRecord::VERSION::MAJOR, ActiveRecord::VERSION::MINOR]
          # The Rails 3.0 method from association_preload.rb
          def preload_has_and_belongs_to_many_association(records, reflection, preload_options={})
            table_name = reflection.klass.quoted_table_name
            id_to_record_map, ids = construct_id_map(records)
            records.each {|record| record.send(reflection.name).loaded}
            options = reflection.options

            conditions = "t0.#{reflection.primary_key_name} #{in_or_equals_for_ids(ids)}"
            conditions << append_conditions(reflection, preload_options)

            # Make several queries with no more than 1000 ids in each one, combining the results into a single array
            associated_records = []
            ids.each_slice(MAX_IDS_PER_ORACLE_QUERY) do |safe_for_oracle_ids|
              associated_records += reflection.klass.unscoped.where([conditions, safe_for_oracle_ids]).
                  includes(options[:include]).
                  joins("INNER JOIN #{connection.quote_table_name options[:join_table]} t0 ON #{reflection.klass.quoted_table_name}.#{reflection.klass.primary_key} = t0.#{reflection.association_foreign_key}").
                  select("#{options[:select] || table_name+'.*'}, t0.#{reflection.primary_key_name} as the_parent_record_id").
                  order(options[:order]).to_a
            end

            set_association_collection_records(id_to_record_map, reflection.name, associated_records, 'the_parent_record_id')
          end
        end
      end
    end
  end
end
