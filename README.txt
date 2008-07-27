= activerecord-oracle_enhanced-adapter

* http://rubyforge.org/projects/oracle-enhanced/

== DESCRIPTION:

Oracle "enhanced" ActiveRecord adapter contains useful additional methods for working with new and legacy Oracle databases
from Rails which are extracted from current real projects' monkey patches of original Oracle adapter.

See http://blog.rayapps.com/category/oracle-enhanced for more information.

Look ar RSpec tests under spec directory for usage examples.

== FEATURES/PROBLEMS:


== SYNOPSIS:

In Rails config/database.yml file use oracle_enhanced as adapter name.

Create config/initializers/oracle_advanced.rb file in your Rails application and put configuration options there.
The following configuration options are available:

* set to true if columns with DATE in their name should be emulated as Date (and not as Time which is default)
ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = true

* set to true if columns with ID at the end of column name should be emulated as Fixnum (and not as BigDecimal which is default)
ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_integers_by_column_name = true

* set to true if CHAR(1), VARCHAR2(1) columns or VARCHAR2 columns with FLAG or YN at the end of their name
  should be emulated as booleans (and do not use NUMBER(1) as type for booleans which is default)
ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = true

* specify other date and time formats that should be used when assigning string values to :date and :datetime columns, e.g.:
ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.string_to_date_format = "%d.%m.%Y"
ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.string_to_time_format = "%d.%m.%Y %H:%M:%S"

The following model class methods are available:
* specify which table columns should be ignored by ActiveRecord
ignore_table_columns :column1, :column2, :column3

* specify custom create, update and delete methods which should be used instead of Rails generated INSERT, UPDATE and DELETE statements
# should return ID of new record
set_create_method do
  plsql.employees_pkg.create_employee(
    :p_first_name => first_name,
    :p_last_name => last_name,
    :p_employee_id => nil
  )[:p_employee_id]
end
set_update_method do
  plsql.employees_pkg.update_employee(
    :p_employee_id => id,
    :p_first_name => first_name,
    :p_last_name => last_name
  )
end
set_delete_method do
  plsql.employees_pkg.delete_employee(
    :p_employee_id => id
  )
end

Oracle enhanced adapter is also compatible with composite_primary_keys gem.

See History.txt for other enhancements to original Oracle adapter.

== REQUIREMENTS:

* Works with ActiveRecord version 2.0 and 2.1 (which is included in Rails 2.0 and 2.1)
* Requires ruby-oci8 library to connect to Oracle
* Requires ruby-plsql gem to support custom create, update and delete methods

== INSTALL:

* sudo gem install activerecord-oracle_enhanced-adapter

== LICENSE:

(The MIT License)

Copyright (c) 2008 Graham Jenkins, Michael Schoen, Raimonds Simanovskis

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.