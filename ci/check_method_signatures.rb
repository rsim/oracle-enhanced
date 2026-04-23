# frozen_string_literal: true

# Surfaces method-signature drift between oracle_enhanced and Rails.
#
# For every instance method defined inside an `OracleEnhanced::*` module or the
# `OracleEnhancedAdapter` class, this script finds the nearest non-OE Rails
# adapter ancestor that also defines that method and compares the parameter
# list (`Method#parameters`). Any drift in arity, parameter kind (req / opt /
# rest / keyreq / key / keyrest / block) or parameter name is reported, and
# the script exits non-zero so CI can catch it.
#
# This complements ci/check_method_visibility.rb: visibility checks public /
# private alignment, this one catches cases where a Rails method grows or
# renames a parameter and the OE override still has the old shape (as in
# rsim/oracle-enhanced#2578, where AbstractAdapter#empty_insert_statement_value
# gained a `primary_key` argument that the OE override did not accept).
#
# Anonymous argument-forwarding (`def foo(...)`) is skipped: by design it
# accepts whatever Rails passes, so it can never drift.
#
# What this does NOT catch (known limitations):
#
# - Methods Rails renames / relocates without keeping the old name.
# - Methods that only exist as class methods (`self.foo`) — only instance
#   methods are compared.
# - Semantic / body drift — argument shape can match while behavior differs.
# - Default-value drift — `Method#parameters` does not expose default values.
#
# Run locally:
#   bundle exec ruby -Ilib ci/check_method_signatures.rb

require "active_record"
require "active_record/connection_adapters/oracle_enhanced_adapter"

ADAPTER = ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter

# Drifts listed here are intentionally accepted, with a one-line reason. Keep
# this set small and give it a good justification — the whole point of the
# check is to flag *unintentional* drift.
IGNORED_DRIFTS = [
  # { method: :some_method, oe_owner: "Some::Module", rails_owner: "Some::Rails" },
].freeze

OE_NAMESPACE = /(^|::)OracleEnhanced(?:Adapter)?(?:::|$)/

# `def foo(...)` compiles to this parameter list. The method delegates all
# arguments verbatim, so by construction it cannot drift from Rails.
FORWARD_ALL = [[:rest, :*], [:keyrest, :**], [:block, :&]].freeze

def oe_owned?(owner)
  owner.name && owner.name.match?(OE_NAMESPACE)
end

def rails_owned?(owner)
  name = owner.name
  return false unless name
  return false if oe_owned?(owner)
  # Only consider Rails adapter-contract namespaces. ActiveSupport mixins
  # (Callbacks, Tryable, ...) and ActiveRecord non-adapter modules
  # (Migration, QueryCache helpers, ...) are deliberately out of scope for
  # this adapter-contract check.
  name.start_with?("ActiveRecord::ConnectionAdapters::") ||
    name.start_with?("Arel::")
end

def defines?(owner, method_name)
  owner.public_instance_methods(false).include?(method_name) ||
    owner.private_instance_methods(false).include?(method_name) ||
    owner.protected_instance_methods(false).include?(method_name)
end

def parameters_of(owner, method_name)
  return nil unless defines?(owner, method_name)
  owner.instance_method(method_name).parameters
end

# Find the nearest Rails (non-OE) ancestor that defines method_name, walking
# the class's ancestor list in MRO order. Returns [ancestor_owner, parameters]
# or nil.
def find_rails_counterpart(ancestors, method_name)
  ancestors.each do |owner|
    next unless rails_owned?(owner)
    params = parameters_of(owner, method_name)
    return [owner, params] if params
  end
  nil
end

POSITIONAL_KINDS = %i[req opt rest].freeze
KEYWORD_KINDS = %i[keyreq key].freeze
# :block is deliberately excluded: declaring `&block` vs not is internal,
# every Ruby method accepts a block via `yield` regardless of the signature.
# :keyrest presence is caller-visible (accepting/rejecting arbitrary kwargs).

def partition_params(params)
  positional = params.select { |kind, _| POSITIONAL_KINDS.include?(kind) }
  keyword    = params.select { |kind, _| KEYWORD_KINDS.include?(kind) }
  has_keyrest = params.any? { |kind, _| kind == :keyrest }
  [positional, keyword, has_keyrest]
end

# Compare two `Method#parameters` lists. Returns an array of drift category
# symbols: :arity, :kind, :name. An empty array means the signatures match.
#
# Parameter *names* are only caller-visible for keyword args (`:keyreq`,
# `:key`); for positional / rest / keyrest / block they are internal and
# deliberately ignored. Keyword args are compared as a set (by name) because
# `Method#parameters` preserves declaration order but callers invoke them by
# name regardless of order. Block-parameter presence is ignored entirely.
def compare_parameters(oe_params, rails_params)
  drifts = []
  oe_pos, oe_kw, oe_keyrest = partition_params(oe_params)
  rails_pos, rails_kw, rails_keyrest = partition_params(rails_params)

  drifts << :arity if oe_pos.length != rails_pos.length

  [oe_pos.length, rails_pos.length].min.times do |i|
    oe_kind, = oe_pos[i]
    rails_kind, = rails_pos[i]
    drifts << :kind if oe_kind != rails_kind && !drifts.include?(:kind)
  end

  oe_kw_by_name    = oe_kw.to_h { |kind, name| [name, kind] }
  rails_kw_by_name = rails_kw.to_h { |kind, name| [name, kind] }

  if oe_kw_by_name.keys.sort != rails_kw_by_name.keys.sort
    missing = rails_kw_by_name.keys - oe_kw_by_name.keys
    extra   = oe_kw_by_name.keys - rails_kw_by_name.keys
    drifts << :arity if (missing + extra).any? && oe_kw_by_name.size != rails_kw_by_name.size && !drifts.include?(:arity)
    drifts << :name  if oe_kw_by_name.size == rails_kw_by_name.size && !drifts.include?(:name)
  end

  (oe_kw_by_name.keys & rails_kw_by_name.keys).each do |name|
    if oe_kw_by_name[name] != rails_kw_by_name[name]
      drifts << :kind unless drifts.include?(:kind)
    end
  end

  if oe_keyrest != rails_keyrest && !drifts.include?(:kind)
    drifts << :kind
  end

  drifts
end

def ignored?(drift)
  IGNORED_DRIFTS.any? do |pat|
    pat[:method].to_s == drift[:method].to_s &&
      pat[:oe_owner] == drift[:oe_owner] &&
      pat[:rails_owner] == drift[:rails_owner]
  end
end

drifts = []
ancestors = ADAPTER.ancestors
oe_ancestors = ancestors.select { |owner| oe_owned?(owner) }

oe_ancestors.each do |oe_owner|
  own_methods = oe_owner.public_instance_methods(false) +
                oe_owner.private_instance_methods(false) +
                oe_owner.protected_instance_methods(false)

  own_methods.sort.each do |method_name|
    oe_params = parameters_of(oe_owner, method_name)
    next if oe_params.nil?
    next if oe_params == FORWARD_ALL

    rails_pair = find_rails_counterpart(ancestors, method_name)
    next unless rails_pair

    rails_owner, rails_params = rails_pair
    # When Rails itself uses anonymous forwarding the true contract is set by
    # whatever calls it, not by the reflected signature, so we can't compare.
    next if rails_params == FORWARD_ALL

    categories = compare_parameters(oe_params, rails_params)
    next if categories.empty?

    drift = {
      method: method_name,
      oe_owner: oe_owner.name,
      oe_params: oe_params,
      rails_owner: rails_owner.name,
      rails_params: rails_params,
      categories: categories,
    }
    drifts << drift unless ignored?(drift)
  end
end

if drifts.empty?
  puts "OK: every overridden method matches the Rails counterpart's signature."
  exit 0
end

puts "Signature drift detected (#{drifts.size} method#{drifts.size == 1 ? '' : 's'}):"
drifts.sort_by { |d| [d[:oe_owner], d[:method].to_s] }.each do |d|
  puts "  - #{d[:method]} (#{d[:categories].join(', ')})"
  puts "      #{d[:oe_owner]}: #{d[:oe_params].inspect}"
  puts "      #{d[:rails_owner]}: #{d[:rails_params].inspect}"
end
puts
puts "If the drift is intentional (Rails changed its contract and we are tracking"
puts "the old behavior deliberately), add an entry to IGNORED_DRIFTS in this"
puts "script with a one-line comment explaining why. Otherwise, reconcile"
puts "oracle_enhanced with Rails by updating the method signature to match."
exit 1
