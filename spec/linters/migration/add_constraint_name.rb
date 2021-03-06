module RuboCop
  module Cop
    module Migration
      class AddConstraintName < RuboCop::Cop::Cop
        # Postgres and MySQL have different naming conventions, so if we need to remove them we cannot predict accurately what the constraint name would be.
        MSG = 'Please explicitly name your index or constraint.'.freeze
        CONSTRAINT_METHODS = %i{
          add_unique_constraint add_constraint add_foreign_key add_index add_primary_key add_full_text_index add_spatial_index
          unique_constraint constraint foreign_key index primary_key full_text_index spatial_index
        }.freeze

        def on_block(node)
          node.each_descendant(:send) do |send_node|
            next unless CONSTRAINT_METHODS.include?(method_name(send_node))

            opts = send_node.children.last
            has_named_constraint = false

            if opts && opts.type == :hash
              opts.each_node(:pair) do |pair|
                if hash_key_type(pair) == :sym && hash_key_name(pair) == :name
                  has_named_constraint = true
                end
              end
            end

            add_offense(send_node, :expression) unless has_named_constraint
          end
        end

        private

        def method_name(node)
          node.children[1]
        end

        def hash_key_type(pair)
          pair.children[0].type
        end

        def hash_key_name(pair)
          pair.children[0].children[0]
        end
      end
    end
  end
end
