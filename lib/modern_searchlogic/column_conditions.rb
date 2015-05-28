module ModernSearchlogic
  module ColumnConditions
    module ClassMethods
      def respond_to_missing?(method, *)
        super || !!searchlogic_column_condition_method_block(method.to_s)
      end

      private

      def searchlogic_suffix_condition(suffix, options = {}, &method_block)
        raise "Not sure how to handle suffix condition that takes #{method_block.arity} args" if method_block.arity > 2
        searchlogic_suffix_conditions << [suffix, options, method_block]
      end

      def searchlogic_column_prefix(prefix, &method_block)
        searchlogic_column_prefixes << [prefix, method_block]
      end

      def searchlogic_arel_alias(searchlogic_suffix, arel_method, options = {})
        searchlogic_suffix_condition "_#{searchlogic_suffix}", options do |column_name, val|
          arel_table[column_name].__send__(arel_method, val)
        end
      end

      def searchlogic_suffix_condition_match(method_name)
        searchlogic_suffix_conditions.each do |suffix, options, method_block|
          if match = method_name.match(/\A(#{column_names_regexp}(?:_or_#{column_names_regexp})*)#{suffix}(?:_(any|all))?\z/)
            expected_args_length = method_block.arity - 1
            column_names = match[1].split('_or_')
            any_or_all = match[2] && (match[2] == 'any' ? :or : :and)
            next if expected_args_length.zero? && any_or_all

            return lambda do |*args|
              if any_or_all && !options[:array_args]
                args = Array.wrap(args).flatten
              elsif !any_or_all && options[:array_args]
                args = [Array.wrap(args).flatten]
              end

              if expected_args_length == 1
                if !any_or_all && (args.length.zero? || args.length > 1)
                  raise ArgumentError, "wrong number of arguments (#{args.length} for 1)"
                end

                arel_conditions = args.map do |arg|
                  column_names.map { |n| instance_exec(n, arg, &method_block) }.reduce(:or)
                end

                arel_conditions = any_or_all ? arel_conditions.reduce(any_or_all) : arel_conditions.first
              elsif expected_args_length.zero?
                if args.length.nonzero?
                  raise ArgumentError, "wrong number of arguments (#{args.length}) for 0"
                end

                arel_conditions = column_names.map { |n| instance_exec(n, &method_block) }.reduce(:or)
              end

              where(arel_conditions)
            end
          end
        end

        nil
      end

      def searchlogic_prefix_match(method_name)
        searchlogic_column_prefixes.each do |prefix, method_block|
          if match = method_name.match(/\A#{prefix}(#{column_names_regexp})\z/)
            return lambda { |*args| instance_exec(match[1], *args, &method_block) }
          end
        end

        nil
      end

      def searchlogic_association_finder_match(method_name)
        reflect_on_all_associations.each do |a|
          if method_name =~ /\A#{a.name}_(\S+)\z/ && a.klass.respond_to?($1)
            association_scope_name = $1
            return lambda do |*args|
              scope = a.klass.__send__(association_scope_name, *args)
              unless ActiveRecord::Relation === scope
                raise ArgumentError, "Expected #{association_scope_name.inspect} to return an ActiveRecord::Relation"
              end

              joins(a.name).merge(scope)
            end
          end
        end

        nil
      end

      def searchlogic_column_condition_method_block(method)
        method = method.to_s
        searchlogic_prefix_match(method) ||
          searchlogic_suffix_condition_match(method) ||
          searchlogic_association_finder_match(method)
      end

      def column_names_regexp
        "(?:#{column_names.join('|')})"
      end

      def method_missing(method, *args, &block)
        return super unless method_block = searchlogic_column_condition_method_block(method.to_s)

        singleton_class.__send__(:define_method, method, &method_block)

        __send__(method, *args, &block)
      end
    end

    def self.included(base)
      base.extend ClassMethods

      base.class_eval do
        class_attribute :searchlogic_suffix_conditions
        self.searchlogic_suffix_conditions = []

        class_attribute :searchlogic_column_prefixes
        self.searchlogic_column_prefixes = []

        searchlogic_arel_alias :equals, :eq
        searchlogic_arel_alias :eq, :eq
        searchlogic_arel_alias :is, :eq
        searchlogic_arel_alias :does_not_equal, :not_eq
        searchlogic_arel_alias :ne, :not_eq
        searchlogic_arel_alias :not_eq, :not_eq
        searchlogic_arel_alias :greater_than, :gt
        searchlogic_arel_alias :gt, :gt
        searchlogic_arel_alias :less_than, :lt
        searchlogic_arel_alias :lt, :lt
        searchlogic_arel_alias :greater_than_or_equal_to, :gteq
        searchlogic_arel_alias :gte, :gteq
        searchlogic_arel_alias :less_than_or_equal_to, :lteq
        searchlogic_arel_alias :lte, :lteq
        searchlogic_arel_alias :in, :in, :array_args => true
        searchlogic_arel_alias :not_in, :not_in, :array_args => true

        searchlogic_suffix_condition '_like' do |column_name, val|
          arel_table[column_name].matches("%#{val}%")
        end

        searchlogic_suffix_condition '_begins_with' do |column_name, val|
          arel_table[column_name].matches("#{val}%")
        end

        searchlogic_suffix_condition '_ends_with' do |column_name, val|
          arel_table[column_name].matches("%#{val}")
        end

        searchlogic_suffix_condition '_not_like' do |column_name, val|
          arel_table[column_name].does_not_match("%#{val}%")
        end

        searchlogic_suffix_condition '_not_begin_with' do |column_name, val|
          arel_table[column_name].does_not_match("#{val}%")
        end

        searchlogic_suffix_condition '_not_end_with' do |column_name, val|
          arel_table[column_name].does_not_match("%#{val}")
        end

        searchlogic_suffix_condition '_blank' do |column_name|
          arel_table[column_name].eq(nil).or(arel_table[column_name].eq(''))
        end

        searchlogic_suffix_condition '_present' do |column_name|
          arel_table[column_name].not_eq(nil).and(arel_table[column_name].not_eq(''))
        end

        null_matcher = lambda { |column_name| arel_table[column_name].eq(nil) }
        searchlogic_suffix_condition '_null', &null_matcher
        searchlogic_suffix_condition '_nil', &null_matcher

        not_null_matcher = lambda { |column_name| arel_table[column_name].not_eq(nil) }
        searchlogic_suffix_condition '_not_null', &not_null_matcher
        searchlogic_suffix_condition '_not_nil', &not_null_matcher

        searchlogic_column_prefix 'descend_by_' do |column_name|
          order(column_name => :desc)
        end

        searchlogic_column_prefix 'ascend_by_' do |column_name|
          order(column_name => :asc)
        end
      end
    end
  end
end
