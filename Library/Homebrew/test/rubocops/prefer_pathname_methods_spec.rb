# frozen_string_literal: true

require "rubocops/prefer_pathname_methods"

RSpec.describe RuboCop::Cop::Homebrew::PreferPathnameMethods do
  subject(:cop) { described_class.new }

  context "when using a Pathname" do
    it "reports an offense for `Dir#glob`" do
      expect_offense(<<~RUBY)
        Dir.glob("\#{Pathname.pwd}/bin/*")
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Homebrew/PreferPathnameMethods: `Pathname.pwd` is a `Pathname`, so you can use `Pathname.pwd.glob("bin/*")`.
      RUBY

      expect_correction(<<~RUBY)
        Pathname.pwd.glob("bin/*")
      RUBY
    end

    it "reports an offense for `Dir#[`" do
      expect_offense(<<~RUBY)
        Dir["\#{Pathname.pwd}/bin/*"]
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Homebrew/PreferPathnameMethods: `Pathname.pwd` is a `Pathname`, so you can use `Pathname.pwd.glob("bin/*")`.
      RUBY

      expect_correction(<<~RUBY)
        Pathname.pwd.glob("bin/*")
      RUBY
    end

    it "reports an offense for `File#read`" do
      expect_offense(<<~RUBY)
        File.read(prefix/"file.txt")
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Homebrew/PreferPathnameMethods: `prefix` is a `Pathname`, so you can use `(prefix/"file.txt").read`.
      RUBY

      expect_correction(<<~RUBY)
        (prefix/"file.txt").read
      RUBY
    end
  end
end
