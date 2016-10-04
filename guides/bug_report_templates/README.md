### How to execute your testcase

Test cases are always helpful to report issues. Here are two executable test cases.

One is Minitest, another one is RSpec. Since Rails uses Minitest by default, Oracle enhanced adapter
uses RSpec. You can use whichever you prefer as long as it represents your issue correctly.

```ruby
$ git clone https://github.com/rsim/oracle-enhanced
$ cd oracle-enhanced/guides/bug_report_templates/
```
#### Minitest
- Execute the `active_record_gem.rb` to see if it works

```ruby
$ ruby active_record_gem.rb
```
- Update the `active_record_gem.rb` to include your test case

#### RSpec
- Execute the `active_record_gem_spec.rb` to see if it works

```ruby
$ cd oracle-enhanced-your-testcase
$ rspec active_record_gem_spec.rb
```
- Update the `active_record_gem_spec.rb` to include your test case

## Acknowledgements

This project is based on [Rails bug_report_templated](https://github.com/rails/rails/tree/master/guides/bug_report_templates)

Thanks to everyone who contributes to these projects.
