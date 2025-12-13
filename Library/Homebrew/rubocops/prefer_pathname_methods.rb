# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    # module FormulaAudit
    module Homebrew
      # https://www.rubydoc.info/gems/rubocop-rails/RuboCop/Cop/Rails/RootPathnameMethods
      # Checks for usages of File/Dir methods that operate on path strings
      # and suggests using the equivalent Pathname instance methods.
      #
      # Example:
      #
      # # bad
      # File.exist?('path/to/file')
      # File.read('path/to/file')
      # Dir.exist?('/path/to/dir')
      #
      # # good
      # Pathname('path/to/file').exist?
      # Pathname('path/to/file').read
      # Pathname('/path/to/dir').exist?
      #
      # class PreferPathnameMethods < FormulaCop
      class PreferPathnameMethods < Base
        extend AutoCorrector
        include RangeHelp

        MSG = "`%<rails_root>s` is a `Pathname`, so you can use `%<replacement>s`."

        DIR_GLOB_METHODS = T.let([:[], :glob].to_set.freeze, T::Set[Symbol])

        DIR_NON_GLOB_METHODS = T.let([
          :children,
          :delete,
          :each_child,
          :empty?,
          :entries,
          :exist?,
          :mkdir,
          :open,
          :rmdir,
          :unlink,
        ].to_set.freeze, T::Set[Symbol])

        DIR_METHODS = T.let((DIR_GLOB_METHODS + DIR_NON_GLOB_METHODS).freeze, T::Set[Symbol])

        FILE_METHODS = T.let([
          :atime,
          :basename,
          :binread,
          :binwrite,
          :birthtime,
          :blockdev?,
          :chardev?,
          :chmod,
          :chown,
          :ctime,
          :delete,
          :directory?,
          :dirname,
          :empty?,
          :executable?,
          :executable_real?,
          :exist?,
          :expand_path,
          :extname,
          :file?,
          :fnmatch,
          :fnmatch?,
          :ftype,
          :grpowned?,
          :join,
          :lchmod,
          :lchown,
          :lstat,
          :mtime,
          :open,
          :owned?,
          :pipe?,
          :read,
          :readable?,
          :readable_real?,
          :readlines,
          :readlink,
          :realdirpath,
          :realpath,
          :rename,
          :setgid?,
          :setuid?,
          :size,
          :size?,
          :socket?,
          :split,
          :stat,
          :sticky?,
          :symlink?,
          :sysopen,
          :truncate,
          :unlink,
          :utime,
          :world_readable?,
          :world_writable?,
          :writable?,
          :writable_real?,
          :write,
          :zero?,
        ].to_set.freeze, T::Set[Symbol])

        FILE_TEST_METHODS = T.let([
          :blockdev?,
          :chardev?,
          :directory?,
          :empty?,
          :executable?,
          :executable_real?,
          :exist?,
          :file?,
          :grpowned?,
          :owned?,
          :pipe?,
          :readable?,
          :readable_real?,
          :setgid?,
          :setuid?,
          :size,
          :size?,
          :socket?,
          :sticky?,
          :symlink?,
          :world_readable?,
          :world_writable?,
          :writable?,
          :writable_real?,
          :zero?,
        ].to_set.freeze, T::Set[Symbol])

        FILE_UTILS_METHODS = T.let([:chmod, :chown, :mkdir, :mkpath, :rmdir, :rmtree].to_set.freeze, T::Set[Symbol])

        RESTRICT_ON_SEND = T.let((DIR_METHODS + FILE_METHODS + FILE_TEST_METHODS + FILE_UTILS_METHODS).to_set.freeze,
                                 T::Set[Symbol])

        # @!method pathname_method(node)
        def_node_matcher :pathname_method, <<~PATTERN
          {
            (send (const {nil? cbase} :Dir) $DIR_METHODS $_ $...)
            (send (const {nil? cbase} {:IO :File}) $FILE_METHODS $_ $...)
            (send (const {nil? cbase} :FileTest) $FILE_TEST_METHODS $_ $...)
            (send (const {nil? cbase} :FileUtils) $FILE_UTILS_METHODS $_ $...)
          }
        PATTERN

        def_node_matcher :dir_glob?, <<~PATTERN
          (send
            (const {cbase nil?} :Dir) DIR_GLOB_METHODS ...)
        PATTERN

        def_node_matcher :pathname?, <<~PATTERN
          {
            $#any_pathname_receiver?
            (send $#any_pathname_receiver? {:join :/} ...)
            (dstr (begin $#any_pathname_receiver?) ...)
          }
        PATTERN

        # @!method any_pathname_receiver?(node)
        def_node_matcher :any_pathname_receiver?, <<~PATTERN
          {
            (send (const {cbase nil?} :Pathname) :pwd ...)
            (send nil? {:libexec :bin :prefix :buildpath})
          }
        PATTERN

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_send(node)
          evidence(node)
        end

        private

        sig { params(node: RuboCop::AST::SendNode, block: T.proc.returns(T.untyped)).returns(T.untyped) }
        def evidence(node)
          return if node.method?(:open) && node.parent&.send_type?
          return unless (_, path, = pathname_method(node))
          return unless pathname?(path)

          yield()
        end

        sig { params(path: T.untyped).returns(String) }
        def build_path_glob_replacement(path)
          # Handle dstr nodes like "#{Pathname.pwd}/bin/*"
          if path.dstr_type?
            # Extract the Pathname receiver from the begin node
            pathname_node = path.children.first.children.first
            receiver = pathname_node.source

            # Extract the rest of the path after the interpolation
            rest_of_path = path.children[1..].map do |child|
              child.str_type? ? child.value : "\#{#{child.source}}"
            end.join

            # Remove leading slash if present
            rest_of_path = rest_of_path.delete_prefix("/")

            "#{receiver}.glob(\"#{rest_of_path}\")"
          else
            receiver = range_between(path.source_range.begin_pos, path.children.first.loc.selector.end_pos).source
            argument = path.arguments.one? ? path.first_argument.source : join_arguments(path.arguments)
            "#{receiver}.glob(#{argument})"
          end
        end

        sig { params(path: T.untyped, method: T.untyped, args: T.untyped).returns(String) }
        def build_path_replacement(path, method, args)
          # Handle path joining with / operator like: prefix/"file.txt"
          # This needs to be wrapped in parens: (prefix/"file.txt").read
          return "(#{path.source}).#{method}" if path.send_type? && path.method?(:/)

          path_replacement = path.source
          if path.respond_to?(:arguments?) && path.arguments? && !path.parenthesized_call?
            path_replacement[" "] = "("
            path_replacement << ")"
          end

          replacement = "#{path_replacement}.#{method}"

          if args.any?
            formatted_args = args.map { |arg| arg.array_type? ? "*#{arg.source}" : arg.source }
            replacement += "(#{formatted_args.join(", ")})"
          end

          replacement
        end

        sig { params(arguments: T.untyped).returns(T::Boolean) }
        def include_interpolation?(arguments)
          arguments.any? do |argument|
            argument.children.any? { |child| child.respond_to?(:begin_type?) && child.begin_type? }
          end
        end

        sig { params(arguments: T.untyped).returns(String) }
        def join_arguments(arguments)
          joined_arguments = arguments.map do |arg|
            if arg.respond_to?(:value)
              arg.value
            else
              "\#{#{arg.source}}"
            end
          end.join("/")

          "\"#{joined_arguments}#\""
        end
      end
    end
  end
end
