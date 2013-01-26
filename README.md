Summary
-------

Babel Bridge let's you generate parsers 100% in Ruby code. It is a memoizing Parsing Expression Grammar (PEG) generator like Treetop, but it doesn't require special file-types or new syntax. Overall focus is on simplicity and usability over performance.

Example
-------

``` ruby
require "babel_bridge"

class MyParser < BabelBridge::Parser

  # match "foo" optionally followed by the :bar
  rule :foo, "foo", :bar?

  # match "bar"
  rule :bar, "bar"
end

MyParser.new.parse("foo") # matches "foo"
#  => FooNode1 > "foo"

MyParser.new.parse("foobar") # matches "foobar"
# => FooNode1
#  "foo"
#  BarNode1 > "bar"
```

Babel Bridge is a parser-generator for Parsing Expression Grammars

Goals
-----

* Allow expression 100% in ruby
* Productivity through Simplicity and Understandability first
* Performance second

Features
--------

``` ruby

  # returns the BabelBridge::Rule instance for that rule
  rule = MyParser[:foo]
  # => rule :foo, "foo", :bar?

  # nice human-readable view of the rule with extra info:
  rule.to_s
  # rule :foo, node_class: MyParser::FooNode
  #         variant_class: MyParser::FooNode1, pattern: "foo", :bar?

  # returns the code necessary for generating the rule and all its variants
  # (minus any class_eval code)
  rule.inspect
  # => rule :foo, "foo", :bar?

  # returns the Node class for a rule
  MyParser.node_class(:foo)
  # => MyParser::FooNode

  MyParser.node_class(:foo) do
    # class_eval inside the rule's Node-class
  end

  # create one more instances of your parser
  parser = MyParser.new

  # parses Text starting with the MyParser.root_rule
  # The root_rule is defined automatically by the first rule defined, but can be set by:
  #   MyParser.root_rule=v
  # where v is the symbol name of the rule or the actual rule object from MyParser[rule]
  text = "foobar"
  parser.parse(text)

  # do a one-time parse with :bar set as the root-rule
  text = "bar"
  parser.parse(text, :rule => :bar)

  # relax requirement to match entire input
  parser.parse "foobar and then something", :partial_match => true

  # parse failure
  parser.parse "foo is not immediately followed by bar"

  # human readable parser failure info
  puts parser.parser_failure_info
```

Parser failure info output:
```
Parsing error at line 1 column 4 offset 3

Source:
...
foo<HERE> is not immediately followed by bar
...

Parser did not match entire input.

Parse path at failure:
  FooNode1

Expecting:
  "bar" BarNode1
```
NOTE: This is an evolving feature, this output is as-of 0.5.1 and may not match the current version.

Defining Rules
--------------

Inside the parser class, a rule is defined as follows:

``` ruby
  class MyParser < BabelBridge::Parser
    rule :rule_name, pattern
  end
```

Where:

* :rule_name    is a symbol
* pattern       see Patterns below

You can also add new rules outside the class definition by:

``` ruby
  MyParser.rule :rule_name, pattern
```

Patterns
--------

Patterns are an list of pattern elements, matched in order:

Example:

``` ruby
  rule :my_rule, "match", "this", "in", "order"  # matches "matchthisinorder"
```

Pattern Elements
----------------

Pattern elements are basic-pattern-element or extended-pattern-element ( expressed as a hash). Internally, they are "compiled" into instances of PatternElement with optimized lambda functions for parsing.

``` ruby
  # basic-pattern-element:
    :my_rule      # matches the Rule named :my_rule
    :my_rule?     # optional: optionally matches Rule :my_rule
    :my_rule!     # negative: success only if it DOESN'T match Rule :my_rule
    "string"      # matches the string exactly
    /regex/       # matches the regex exactly
    true          # always matches the empty string (useful as a no-op if you don't want to change the length of your pattern)

  # extended-pattern-element:

    # A Hash with :match or :parser set and zero or more additional options:

    :match => basic_element
    #  provide one of the basic elements above
    #  NOTE: Optional and Negative options are preserved, but they are overridden by any such directives in the Hash-Element

    :parser => lambda {|parent_node| ... }
    #  Custom lambda function for parsing the input.
    #  Return "nil" if could not find a parse, otherwise return a new Node, typically the TerminalNode
    #  Make sure the returned node.next value is the index where you wish parsing to resume

    :as => :my_name
    #  Assign a name to an element for later programatic reference:
    #    rule_variant_node_class_instance.my_name

    :optionally => true
    #  PEG equivelent: term?
    #  turn this into an optional-match element
    #  optional elements cannot be negative

    :dont => true
    #  PEG equivalent: !term
    #  turn this into a Negative-match element
    #  negative elements cannot be optional

    :could => true
    #  PEG equivalent: &term

    :many => PatternElement
    #  PEG equivalent: term+ (for "term*", use optionally + many)
    #  accept 1 or more reptitions of this element delimited by PatternElement
    #  NOTE: PatternElement can be "true" for no delimiter (since "true" matches the empty string)

    :delimiter => PatternElement
    #  pattern to match between the :many patterns

    :post_delimiter => true           # use the :delimiter PatternElement for final match
    :post_delimiter => PatternElement # use custom post_delimiter PatternElement for final match
    #  if true, then poly will match a delimiter after the last poly-match
```

Structure
---------

* Each Rule defines a subclass of Node
* Each RuleVariant defines a subclass of the parent Rule's node-class

  Therefor you can easily define code to be shared across all variants as well
  as define code specific to one variant.
