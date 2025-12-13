# frozen_string_literal: true

require "rubocops/prefer_pathname"

RSpec.describe RuboCop::Cop::Homebrew::PreferPathname, :config do
  # expect_offense requires unannotated format tokens
  # rubocop:disable Style/FormatStringToken
  {
    Dir:       described_class::DIR_NON_GLOB_METHODS,
    File:      described_class::FILE_METHODS,
    FileTest:  described_class::FILE_TEST_METHODS,
    FileUtils: described_class::FILE_UTILS_METHODS,
    IO:        described_class::FILE_METHODS,
  }.each do |receiver, methods|
    methods.each do |method|
      it "registers an offense when using `#{receiver}.#{method}(libexec)` (if arity exists)" do
        expect_offense(<<~RUBY, receiver: receiver, method: method)
          %{receiver}.%{method}(libexec)
          ^{receiver}^^{method}^^^^^^^^^ `libexec` is a `Pathname`, so you can use `libexec.%{method}`.
        RUBY

        expect_correction(<<~RUBY)
          libexec.#{method}
        RUBY
      end

      it "registers an offense when using `#{receiver}.#{method}(prefix.join(...))` (if arity exists)" do
        expect_offense(<<~RUBY, receiver: receiver, method: method)
          %{receiver}.%{method}(prefix.join('bin', 'foo'))
          ^{receiver}^^{method}^^^^^^^^^^^^^^^^^^^^^^^^^^^ `prefix` is a `Pathname`, so you can use `prefix.join('bin', 'foo').%{method}`.
        RUBY

        expect_correction(<<~RUBY)
          prefix.join('bin', 'foo').#{method}
        RUBY
      end

      it "registers an offense when using `#{receiver}.#{method}(libexec.join(...), ...)` (if arity exists)" do
        expect_offense(<<~RUBY, receiver: receiver, method: method)
          %{receiver}.%{method}(libexec.join('bin', 'bar'), 20, 5)
          ^{receiver}^^{method}^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `libexec` is a `Pathname`, so you can use `libexec.join('bin', 'bar').%{method}(20, 5)`.
        RUBY

        expect_correction(<<~RUBY)
          libexec.join('bin', 'bar').#{method}(20, 5)
        RUBY
      end
    end
  end
  # rubocop:enable Style/FormatStringToken

  context "when using `Dir.glob`" do
    it "registers an offense when using `Dir.glob(prefix.join(\"**/*.rb\"))`" do
      expect_offense(<<~RUBY)
        Dir.glob(prefix.join("**/*.rb"))
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `prefix` is a `Pathname`, so you can use `prefix.glob("**/*.rb")`.
      RUBY

      expect_correction(<<~RUBY)
        prefix.glob("**/*.rb")
      RUBY
    end

    it "registers an offense when using `::Dir.glob(libexec.join('**/*.rb'))`" do
      expect_offense(<<~RUBY)
        ::Dir.glob(libexec.join('**/*.rb'))
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `libexec` is a `Pathname`, so you can use `libexec.glob('**/*.rb')`.
      RUBY

      expect_correction(<<~RUBY)
        libexec.glob('**/*.rb')
      RUBY
    end

    it "registers an offense when using `Dir.glob(prefix.join('**/\#{path}/*.rb'))`" do
      expect_offense(<<~'RUBY')
        Dir.glob(prefix.join("**/#{path}/*.rb"))
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `prefix` is a `Pathname`, so you can use `prefix.glob("**/#{path}/*.rb")`.
      RUBY

      expect_correction(<<~'RUBY')
        prefix.glob("**/#{path}/*.rb")
      RUBY
    end

    it "registers an offense when using `Dir.glob(libexec.join(\"**\", \"*.rb\"))`" do
      expect_offense(<<~RUBY)
        Dir.glob(libexec.join("**", "*.rb"))
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `libexec` is a `Pathname`, so you can use `libexec.glob("**/*.rb")`.
      RUBY

      expect_correction(<<~RUBY)
        libexec.glob("**/*.rb")
      RUBY
    end

    context "when double-quoted string literals are preferred" do
      let(:other_cops) do
        super().merge("Style/StringLiterals" => { "EnforcedStyle" => "double_quotes" })
      end

      it "registers an offense when using `Dir.glob(prefix.join('**', '*.rb'))`" do
        expect_offense(<<~RUBY)
          Dir.glob(prefix.join('**', '*.rb'))
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `prefix` is a `Pathname`, so you can use `prefix.glob("**/*.rb")`.
        RUBY

        expect_correction(<<~RUBY)
          prefix.glob("**/*.rb")
        RUBY
      end
    end

    it "registers an offense when using `Dir.glob(libexec.join('**', \"\#{path}\", '*.rb'))`" do
      expect_offense(<<~'RUBY')
        Dir.glob(libexec.join('**', "#{path}", '*.rb'))
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `libexec` is a `Pathname`, so you can use `libexec.glob("**/#{path}/*.rb")`.
      RUBY

      expect_correction(<<~'RUBY')
        libexec.glob("**/#{path}/*.rb")
      RUBY
    end

    it "registers an offense when using `env` argument within `Dir.glob`" do
      expect_offense(<<~RUBY)
        Dir.glob(prefix.join("data", "files", env, "*.txt")).sort.each do |file|
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `prefix` is a `Pathname`, so you can use `prefix.glob("data/files/\#{env}/*.txt")`.
          load file
        end
      RUBY

      expect_correction(<<~'RUBY')
        prefix.glob("data/files/#{env}/*.txt").sort.each do |file|
          load file
        end
      RUBY
    end
  end

  context "when using Dir.[] on Ruby 2.5 or higher", :ruby25 do
    it "registers offense when using `Dir[libexec.join(...)]`" do
      expect_offense(<<~RUBY)
        Dir[libexec.join('spec/support/**/*.rb')]
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `libexec` is a `Pathname`, so you can use `libexec.glob('spec/support/**/*.rb')`.
      RUBY

      expect_correction(<<~RUBY)
        libexec.glob('spec/support/**/*.rb')
      RUBY
    end

    it "registers offense when using `Dir[\"#\{libexec}/bin/*\"]`" do
      expect_offense(<<~'RUBY')
        Dir["#{libexec}/bin/*"]
        ^^^^^^^^^^^^^^^^^^^^^^^ `libexec` is a `Pathname`, so you can use `libexec.glob("bin/*")`.
      RUBY

      expect_correction(<<~RUBY)
        libexec.glob("bin/*")
      RUBY
    end

    it "registers offense when using `Dir[\"#\{prefix}/share/**/*.txt\"]`" do
      expect_offense(<<~'RUBY')
        Dir["#{prefix}/share/**/*.txt"]
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `prefix` is a `Pathname`, so you can use `prefix.glob("share/**/*.txt")`.
      RUBY

      expect_correction(<<~RUBY)
        prefix.glob("share/**/*.txt")
      RUBY
    end

    it "registers offense when using `Dir[buildpath/\"bin/*\"]`" do
      expect_offense(<<~RUBY)
        Dir[buildpath/"bin/*"]
        ^^^^^^^^^^^^^^^^^^^^^^ `buildpath` is a `Pathname`, so you can use `buildpath.glob("bin/*")`.
      RUBY

      expect_correction(<<~RUBY)
        buildpath.glob("bin/*")
      RUBY
    end

    it "registers offense when using `Dir[prefix/\"share/**/*.txt\"]`" do
      expect_offense(<<~RUBY)
        Dir[prefix/"share/**/*.txt"]
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `prefix` is a `Pathname`, so you can use `prefix.glob("share/**/*.txt")`.
      RUBY

      expect_correction(<<~RUBY)
        prefix.glob("share/**/*.txt")
      RUBY
    end

    it "registers offense when using `Dir[libexec/\"tools/*\"]`" do
      expect_offense(<<~RUBY)
        Dir[libexec/"tools/*"]
        ^^^^^^^^^^^^^^^^^^^^^^ `libexec` is a `Pathname`, so you can use `libexec.glob("tools/*")`.
      RUBY

      expect_correction(<<~RUBY)
        libexec.glob("tools/*")
      RUBY
    end
  end

  it "does not register an offense when using `File.read(prefix.join(...).join(...))`" do
    expect_no_offenses(<<~RUBY)
      File.read(prefix.join('data').join('file.txt'))
    RUBY
  end

  it "does not register an offense when using `File.open(prefix.join(...)).read`" do
    expect_no_offenses(<<~RUBY)
      File.open(prefix.join('data', 'file.txt')).read
    RUBY
  end

  it "does not register an offense when using `File.open(libexec.join(...)).binread`" do
    expect_no_offenses(<<~RUBY)
      File.open(libexec.join('bin', 'tool')).binread
    RUBY
  end

  it "does not register an offense when using `File.open(prefix.join(...)).write(content)`" do
    expect_no_offenses(<<~RUBY)
      File.open(prefix.join('data', 'output.txt')).write(content)
    RUBY
  end

  it "does not register an offense when using `File.open(libexec.join(...)).binwrite(content)`" do
    expect_no_offenses(<<~RUBY)
      File.open(libexec.join('bin', 'data')).binwrite(content)
    RUBY
  end

  it "registers an offense when using `File.open(prefix.join(...), ...)` inside an iterator" do
    expect_offense(<<~RUBY)
      files.map { |file| File.open(prefix.join('data', file), 'wb') }
                         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `prefix` is a `Pathname`, so you can use `prefix.join('data', file).open('wb')`.
    RUBY

    expect_correction(<<~RUBY)
      files.map { |file| prefix.join('data', file).open('wb') }
    RUBY
  end

  it "registers an offense when using `File.open libexec.join ...` without parens" do
    expect_offense(<<~RUBY)
      file = File.open libexec.join 'docs', 'readme.pdf'
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `libexec` is a `Pathname`, so you can use `libexec.join('docs', 'readme.pdf').open`.
    RUBY

    expect_correction(<<~RUBY)
      file = libexec.join('docs', 'readme.pdf').open
    RUBY
  end

  it "registers an offense when using only [] syntax" do
    expect_offense(<<~RUBY)
      File.join(prefix, ['app', 'models'])
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `prefix` is a `Pathname`, so you can use `prefix.join(*['app', 'models'])`.
    RUBY

    expect_correction(<<~RUBY)
      prefix.join(*['app', 'models'])
    RUBY
  end

  it "registers an offense when using a leading string and an array using [] syntax" do
    expect_offense(<<~RUBY)
      File.join(libexec, "bin", ["tools", "helper"])
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `libexec` is a `Pathname`, so you can use `libexec.join("bin", *["tools", "helper"])`.
    RUBY

    expect_correction(<<~RUBY)
      libexec.join("bin", *["tools", "helper"])
    RUBY
  end

  it "registers an offense when using an array using [] syntax and a trailing string" do
    expect_offense(<<~RUBY)
      File.join(prefix, ["app", "models"], "user.rb")
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `prefix` is a `Pathname`, so you can use `prefix.join(*["app", "models"], "user.rb")`.
    RUBY

    expect_correction(<<~RUBY)
      prefix.join(*["app", "models"], "user.rb")
    RUBY
  end

  it "registers an offense when using only %w[] syntax" do
    expect_offense(<<~RUBY)
      File.join(libexec, %w[bin tools])
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `libexec` is a `Pathname`, so you can use `libexec.join(*%w[bin tools])`.
    RUBY

    expect_correction(<<~RUBY)
      libexec.join(*%w[bin tools])
    RUBY
  end

  it "registers an offense when using a leading string and an array using %w[] syntax" do
    expect_offense(<<~RUBY)
      File.join(prefix, "app", %w[models user])
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `prefix` is a `Pathname`, so you can use `prefix.join("app", *%w[models user])`.
    RUBY

    expect_correction(<<~RUBY)
      prefix.join("app", *%w[models user])
    RUBY
  end

  it "registers an offense when using an array using %w[] syntax and a trailing string" do
    expect_offense(<<~RUBY)
      File.join(libexec, %w[bin tools], "helper.sh")
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `libexec` is a `Pathname`, so you can use `libexec.join(*%w[bin tools], "helper.sh")`.
    RUBY

    expect_correction(<<~RUBY)
      libexec.join(*%w[bin tools], "helper.sh")
    RUBY
  end
end
