require 'pathname'

module BabelBridge
# primary object used by the client
# Used to generate the grammer with .rule methods
# Used to parse with .parse
class Parser

  # Parser sub-class grammaer definition
  # These methods are used in the creation of a Parser Sub-Class to define
  # its grammar
  class <<self
    attr_accessor :rules, :module_name, :root_rule, :delimiter_pattern

    def rules
      @rules||={}
    end

    # Add a rule to the parser
    #
    # rules can be specified as:
    #   rule :name, to_match1, to_match2, etc...
    #
    # Can define rules INSIDE class:
    #   class MyParser < BabelBridge::Parser
    #     rule :name, to_match1, to_match2, etc...
    #   end
    #
    # Or can define rules OUTSIDE class:
    #   class MyParser < BabelBridge::Parser
    #   end
    #   MyParser.rule :name, to_match1, to_match2, etc...
    #
    # The first rule added is the root-rule for the parser.
    # You can override by:
    #   class MyParser < BabelBridge::Parser
    #     root_rule = :new_root_rool
    #   end
    #
    # The block is executed in the context of the rule-varient's node type, a subclass of: RuleNode
    # This allows you to add whatever functionality you want to a your nodes in the final parse tree.
    # Also note you can override the on_post_match method. This allows you to restructure the parse tree as it is parsed.
    def rule(name,*pattern,&block)
      rule = self.rules[name] ||= Rule.new(name,self)
      @root_rule ||= name
      options =  pattern[-1].kind_of?(Hash) ? pattern.pop : {}
      rule.add_variant options.merge(:pattern => pattern), &block
    end

    # options
    # => right_operators: list of all operators that should be evaluated right to left instead of left-to-write
    #       typical example is the "**" exponentiation operator which should be evaluated right-to-left.
    def binary_operators_rule(name,operand_rule_name,operators,options={},&block)
      right_operators = options[:right_operators]
      rule name, many(operand_rule_name,Tools::array_to_or_regexp(operators)).delimiter_name(:operators).as(:operands) do
        self.class_eval &block if block
        class <<self
          attr_accessor :operators_from_rule, :right_operators
          def operator_processor
            @operator_processor||=BinaryOperatorProcessor.new(operators_from_rule,self,right_operators)
          end
        end
        self.right_operators = right_operators
        self.operators_from_rule = operators

        def operator
          @operator||=operator_node.to_s.to_sym
        end

        def operator_processor
          self.class.operator_processor
        end

        # Override the on_post_match method to take the results of the "many" match
        # and restructure it into a binary tree of nodes based on the precidence of
        # the "operators".
        # TODO - Should on_post_match be run after the whole tree matches? If not, will this screw up caching?
        def post_match_processing
          super
          operator_processor.generate_tree operands, operators, parent
        end
      end
    end

    def node_class(name,&block)
      klass=self.rules[name].node_class
      return klass unless block
      klass.class_eval &block
    end

    def [](i)
      rules[i]
    end

    # rule can be symbol-name of one of the rules in rules_array or one of the actual Rule objects in that array
    def root_rule=(rule)
      raise "Symbol required" unless rule.kind_of?(Symbol)
      raise "rule #{rule.inspect} not found" unless rules[rule]
      @root_rule=rule
    end

    def ignore_whitespace
      delimiter /\s*/
    end

    def delimiter(*pattern)
      @delimiter = pattern
    end

    def delimiter_pattern
      @delimiter_pattern ||= @delimiter && PatternElement.new(@delimiter, :parser_class => self, :delimiter => true)
    end
  end

  def delimiter_pattern
    self.class.delimiter_pattern
  end

  def rules
    self.class.rules
  end

  #*********************************************
  # pattern construction tools
  #
  # Ex:
  #   # match 'keyword'
  #   # (succeeds if keyword is matched; advances the read pointer)
  #   rule :sample_rule, "keyword"
  #   rule :sample_rule, match("keyword")
  #
  #   # don't match 'keyword'
  #   # (succeeds only if keyword is NOT matched; does not advance the read pointer)
  #   rule :sample_rule, match!("keyword")
  #   rule :sample_rule, dont.match("keyword")
  #
  #   # optionally match 'keyword'
  #   # (always succeeds; advances the read pointer if keyword is matched)
  #   rule :sample_rule, match?("keyword")
  #   rule :sample_rule, optionally.match("keyword")
  #
  #   # ensure we could match 'keyword'
  #   # (succeeds only if keyword is matched, but does not advance the read pointer)
  #   rule :sample_rule, could.match("keyword")
  #
  #*********************************************
  class <<self
    def many(m,delimiter=nil)  PatternElementHash.new.match.many(m).delimiter(delimiter) end
    def many?(m,delimiter=nil) PatternElementHash.new.optionally.match.many(m).delimiter(delimiter) end

    def match(*args)  PatternElementHash.new.match(*args) end
    def match?(*args) PatternElementHash.new.optionally.match(*args) end
    def match!(*args) PatternElementHash.new.dont.match(*args) end

    def any(*args) PatternElementHash.new.any(args) end
    def any?(*args) PatternElementHash.new.optionally.any(args) end
    def any!(*args) PatternElementHash.new.dont.any(args) end

    def dont; PatternElementHash.new.dont end
    def optionally; PatternElementHash.new.optionally end
    def could; PatternElementHash.new.could end
    def custom_parser(&block); PatternElementHash.new.parser(lambda &block) end
  end


  #*********************************************
  #*********************************************
  # parser instance implementation
  # this methods are used for each actual parse run
  # they are tied to an instnace of the Parser Sub-class to you can have more than one
  # parser active at a time
  attr_accessor :failure_index
  attr_accessor :expecting_list
  attr_accessor :src, :source_file
  attr_accessor :parse_cache
  attr_accessor :failed_parse # gets set if the entire input was not matched

  def relative_source_file
    source_file && @relative_source_file ||= Pathname.new(File.expand_path(source_file)).relative_path_from(Pathname.getwd)
  end

  # options:
  #     :source_file => string
  def initialize(options={})
    @source_file = options[:source_file]
    reset_parser_tracking
  end

  def reset_parser_tracking
    @matching_negative_depth = 0
    @parsing_did_not_match_entire_input = false
    @src = nil
    @failure_index = 0
    @expecting_list = {}
    @parse_cache = {}
  end

  def cached(rule_class,offset)
    (parse_cache[rule_class]||={})[offset]
  end

  def cache_match(rule_class,match)
    (parse_cache[rule_class]||={})[match.offset]=match
  end

  def cache_no_match(rule_class,offset)
    (parse_cache[rule_class]||={})[offset]=:no_match
  end

  def log_parsing_failure(index,expecting)
    if matching_negative?
      # ignored
    elsif index>failure_index
      @expecting_list = {expecting[:pattern] => expecting}
      @failure_index = index
    elsif index == failure_index
      @expecting_list[expecting[:pattern]] = expecting
    else
      # ignored
    end
  end

  def matching_negative
    @matching_negative_depth||=0
    @matching_negative_depth+=1
  end

  def unmatching_negative
    @matching_negative_depth-=1
  end

  def matching_negative?
    (@matching_negative_depth||0) > 0
  end

  # parse a string, return the root node of the parse tree.
  # If nil is returned, parsing failed. Call .parser_failure_info after failure for a human-readable description of the failure.
  # src: the string to parse
  # options:
  #   rule: lets you specify the root rule for matching
  #   partial_match: allow partial matching
  def parse(src, options={})
    rule = options[:rule] || self.class.root_rule
    reset_parser_tracking
    @start_time = Time.now
    self.src = src
    root_node = RootNode.new(self)
    raise "No root rule defined." unless rule
    ret = rules[rule].parse(root_node)
    if ret
      if ret.next<src.length && !options[:partial_match] # parse only succeeds if the whole input is matched
        if ret.next >= @failure_index
          @parsing_did_not_match_entire_input=true
          @failure_index = ret.next
          @failed_parse = ret
        end
        ret=nil
      else
        reset_parser_tracking
      end
    end
    @end_time=Time.now
    ret
  end

  def parse_time
    @end_time-@start_time
  end

  # options[:verbose] => false
  def node_list_string(node_list,common_root=[],options={})
    return unless node_list
    if options[:verbose]
      node_list[common_root.length..-1]
    else
      [node_list[-1]]
    end.select do |p|
      p.class.to_s.index(BabelBridge.to_s)!=0
    end.map do |p|
      "#{p.relative_class_name}"
    end.join(" > ")
  end

  def nodes_interesting_parse_path(node)
    path = node.parent_list
    path << node
    path.pop while path[-1] && !path[-1].kind_of?(RuleNode)
    path
  end


  # options[:verbose] => false
  def expecting_output(options={})
    return "" if expecting_list.length==0
    common_root=nil
    expecting_list.values.each do |e|
      node=e[:node]
      pl=nodes_interesting_parse_path(node)
      pl.pop # ignore the node itself
      if common_root
        common_root.each_index do |i|
          if pl[i]!=common_root[i]
            common_root=common_root[0..i-1]
            break
          end
        end
      else
        common_root=pl
      end
    end
    <<ENDTXT

Parse path at failure:
  #{node_list_string(common_root,[],:verbose=>true)}

Expecting#{expecting_list.length>1 ? ' one of' : ''}:
#{Tools.uniform_tabs(Tools.indent(expecting_list.values.collect do |a|
    list=node_list_string(nodes_interesting_parse_path(a[:node]),common_root,options)
    "#{a[:pattern]}\t #{list}"
  end.sort.join("\n"),"  "))}
ENDTXT
  end

  #option: :verbose => true
  def parser_failure_info(options={})
    return unless src
    verbose = options[:verbose]
    bracketing_lines=5
    line,col = Tools.line_column(src, failure_index)
    ret=<<-ENDTXT
Parsing error at line #{line} column #{col} offset #{failure_index}

Source:
...
#{(failure_index==0 ? "" : src[0..(failure_index-1)]).last_lines(bracketing_lines)}<HERE>#{src[(failure_index)..-1].first_lines(bracketing_lines)}
...
ENDTXT

    if @parsing_did_not_match_entire_input
      ret+="\nParser did not match entire input.\n"
      if verbose
        ret+="\nParsed:\n#{Tools::indent failed_parse.inspect||"(nothing)"}\n"
      end
    end

    ret+expecting_output
  end
end
end
