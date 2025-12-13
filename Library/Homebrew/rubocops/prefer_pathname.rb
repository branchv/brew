# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      # Use `prefix` and `libexec` IO methods instead of passing them to `File`.
      #
      # `prefix` and `libexec` are instances of `Pathname`
      # so we can apply many IO methods directly.
      #
      # This cop works best when used together with
      # `Style/FileRead` and `Style/FileWrite`.
      #
      # @safety
      #   This cop is unsafe for autocorrection because ``Dir``'s `children`, `each_child`, `entries`, and `glob`
      #   methods return string element, but these methods of `Pathname` return `Pathname` element.
      #
      # @example
      #   # bad
      #   File.open(prefix.join('bin', 'foo'))
      #   File.open(libexec.join('bin', 'bar'), 'w')
      #   File.read(prefix.join('README'))
      #   File.binread(prefix.join('data.bin'))
      #   File.write(libexec.join('config'), content)
      #   File.binwrite(prefix.join('data'), content)
      #   Dir.glob(prefix.join('**', '*.rb'))
      #   Dir[libexec.join('**', '*.sh')]
      #   Dir["#{prefix}/bin/*"]
      #   Dir[buildpath/"share/**/*.txt"]
      #
      #   # good
      #   prefix.join('bin', 'foo').open
      #   libexec.join('bin', 'bar').open('w')
      #   prefix.join('README').read
      #   prefix.join('data.bin').binread
      #   libexec.join('config').write(content)
      #   prefix.join('data').binwrite(content)
      #   prefix.glob('**/*.rb')
      #   libexec.glob('**/*.sh')
      #   prefix.glob('bin/*')
      #   buildpath.glob('share/**/*.txt')
      #
      class PreferPathname < Base
        extend AutoCorrector
        include RangeHelp

        MSG = "`%<pathname_receiver>s` is a `Pathname`, so you can use `%<replacement>s`."

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

        RESTRICT_ON_SEND = (DIR_METHODS + FILE_METHODS + FILE_TEST_METHODS + FILE_UTILS_METHODS).to_set.freeze

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

        def_node_matcher :pathname_receiver?, <<~PATTERN
          {
            $#formula_pathname_method?
            (send $#formula_pathname_method? :join ...)
          }
        PATTERN

        # @!method formula_pathname_method?(node)
        def_node_matcher :formula_pathname_method?, <<~PATTERN
          (send nil? {:prefix :bin :doc :include :info :lib :libexec :man :man1 :man2 :man3 :man4 :man5 :man6 :man7 :man8 :sbin :share :pkgshare :etc :pkgetc :var :buildpath :testpath})
        PATTERN

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_send(node)
          evidence(node) do |method, path, args, pathname_receiver|
            replacement = if dir_glob?(node)
              build_path_glob_replacement(path)
            else
              build_path_replacement(path, method, args)
            end

            message = format(MSG, pathname_receiver: pathname_receiver.source, replacement: replacement)
            add_offense(node, message: message) do |corrector|
              corrector.replace(node, replacement)
            end
          end

          # Check for Dir glob with interpolated pathname
          if dir_glob?(node) && node.first_argument&.dstr_type?
            check_interpolated_glob(node)
            return
          end

          # Check for Dir glob with pathname / operator (e.g., Dir[buildpath/"bin/*"])
          return unless dir_glob?(node) && node.first_argument

          check_pathname_slash_glob(node)
        end

        private

        sig { params(node: RuboCop::AST::SendNode).void }
        def check_pathname_slash_glob(node)
          arg = node.first_argument
          return unless arg.send_type? && arg.method?(:/)

          # Check if left side is a pathname method (e.g., buildpath)
          return unless formula_pathname_method?(arg.receiver)

          # Right side should be a string with the glob pattern
          return unless arg.first_argument&.str_type?

          pathname_name = arg.receiver.method_name
          glob_pattern = arg.first_argument.source

          replacement = "#{pathname_name}.glob(#{glob_pattern})"
          message = format(MSG, pathname_receiver: pathname_name, replacement: replacement)

          add_offense(node, message: message) do |corrector|
            corrector.replace(node, replacement)
          end
        end

        sig { params(node: RuboCop::AST::SendNode).void }
        def check_interpolated_glob(node)
          string_node = node.first_argument
          return unless string_node.children.first&.begin_type?

          interpolated_var = string_node.children.first.children.first
          return unless formula_pathname_method?(interpolated_var)

          pathname_name = interpolated_var.method_name
          glob_pattern = extract_glob_pattern(string_node)
          return unless glob_pattern

          replacement = "#{pathname_name}.glob(#{glob_pattern})"
          message = format(MSG, pathname_receiver: pathname_name, replacement: replacement)

          add_offense(node, message: message) do |corrector|
            corrector.replace(node, replacement)
          end
        end

        sig { params(node: RuboCop::AST::SendNode).void }
        def evidence(node)
          return if node.method?(:open) && node.parent&.send_type?
          return unless (method, path, args = pathname_method(node))
          return unless (pathname_receiver = pathname_receiver?(path))

          yield(method, path, args, pathname_receiver)
        end

        sig { params(path: T.untyped).returns(String) }
        def build_path_glob_replacement(path)
          receiver = range_between(path.source_range.begin_pos, path.children.first.loc.selector.end_pos).source

          argument = path.arguments.one? ? path.first_argument.source : join_arguments(path.arguments)

          "#{receiver}.glob(#{argument})"
        end

        sig { params(path: T.untyped, method: T.untyped, args: T.untyped).returns(String) }
        def build_path_replacement(path, method, args)
          path_replacement = path.source
          if path.arguments? && !path.parenthesized_call?
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
          quote = '"'

          "#{quote}#{joined_arguments}#{quote}"
        end

        sig { params(string_node: T.untyped).returns(T.nilable(String)) }
        def extract_glob_pattern(string_node)
          # Extract the glob pattern from a string like "#{libexec}/bin/*"
          # Pattern: (dstr (begin (send nil? :libexec)) (str "/bin/*"))
          parts = []
          string_node.children.each_with_index do |child, index|
            next if index.zero? && child.begin_type? # Skip the interpolated variable at the start

            if child.str_type?
              # Remove leading slash if it's right after the interpolated variable
              str_value = child.value
              str_value = str_value.delete_prefix("/") if index == 1 && str_value.start_with?("/")
              parts << str_value
            elsif child.begin_type?
              # Handle additional interpolations
              parts << "\#{#{child.children.first.source}}"
            end
          end

          return if parts.empty?

          pattern = parts.join
          # Use double quotes since we converted from an interpolated string
          "\"#{pattern}\""
        end
      end
    end
  end
end
