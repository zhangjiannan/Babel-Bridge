=begin
Copyright 2011 Shane Brinkman-Davis
See README for licence information.
http://babel-bridge.rubyforge.org/
=end

module BabelBridge

  # this is just so we can distinguish between normal arrays and arrays of matches
  # - since a match can be an Array in the case of Poly-matches
  class MultiMatchesArray < Array
  end

  # base class for all parse-tree nodes
  class Node
    attr_accessor :src,:offset,:match_length,:parent,:parser

    def to_s
      text
    end

    def node_init(parent_or_parser)
      self.match_length=0
      case parent_or_parser
      when Parser then
        self.parser=parent_or_parser
        self.offset=0
        self.src=parser.src
      when Node then
        self.parent=parent_or_parser
        self.parser=parent.parser
        self.offset=parent.next
        self.src=parent.src
        raise "parent node does not have parser set" unless parser
      else
        raise "parent_or_parser(#{parent_or_parser.class}) must be a Node or a Parser"
      end
    end

    def initialize(parent)
      node_init(parent)
    end

    #********************
    # info methods
    #********************
    def next; offset+match_length end       # index of first character after match
    def text; src[offset,match_length] end  # the substring in src matched

    # length returns the number of sub-nodes
    def length
      0
    end

    def parent_list
      return parent ? parent.parent_list+[parent] : []
    end

    def node_path
      "#{parent && (parent.node_path+' > ')}#{self.class}(#{offset})"
    end

    #*****************************
    # Array interface implementation
    #*****************************
    def matches # override this with function that returns array of matches to be used for Array indexing and iteration
      []
    end

    include Enumerable
    def length
      matches.length
    end

    def <<(node)
      matches<<node
    end

    def add_delimiter(node)
      delimiter_matches<<node
    end

    def [](i)
      matches[i]
    end

    def each(&block)
      matches.each(&block)
    end
  end

  class RootNode < Node
  end

  # non-terminal node
  # subclassed automatically by parser.rule for each unique non-terminal
  class NonTerminalNode < Node
    attr_accessor :matches,:match_names

    def match_names
      @match_names ||= []
    end
    def matches
      @matches ||= []
    end

    # length returns the number of sub-nodes
    def length
      matches.length
    end

    def matches_by_name
      @matches_by_name||= begin
        raise "matches.length #{matches.length} != match_names.length #{match_names.length}" unless matches.length==match_names.length
        mbn={}
        mn=match_names
        matches.each_with_index do |match,i|
          name=mn[i]
          next unless name
          if current=mbn[name] # name already used
            # convert to MultiMatchesArray if not already
            mbn[name]=MultiMatchesArray.new([current]) if !current.kind_of? MultiMatchesArray
            # add to array
            mbn[name]<<match
          else
            mbn[name]=match
          end
        end
        mbn
      end
    end

    def inspect(options={})
      return "#{self.class}" if matches.length==0
      matches_inspected=matches.collect{|a|a.inspect(options)}.compact
      if matches_inspected.length==0 then nil
      elsif matches_inspected.length==1
        m=matches_inspected[0]
        ret="#{self.class} > "+matches_inspected[0]
        if options[:simple]
          ret=if m["\n"] then m
          else
            # just show the first and last nodes in the chain
            ret.gsub(/( > [A-Z][a-zA-Z0-9:]+ > (\.\.\. > )?)/," > ... > ")
          end
        end
        ret
      else
        (["#{self.class}"]+matches_inspected).join("\n").gsub("\n","\n  ")
      end
    end

    #********************
    # alter methods
    #********************
    def reset_matches_by_name
      @matches_by_name=nil
    end

    # defines where to forward missing methods to; override for custom behavior
    def forward_to
      matches[0]
    end

    def method_missing(method_name, *args)  #method_name is a symbol
      unless matches_by_name.has_key? method_name
        if f=forward_to
          return f.send(method_name,*args)
        end
        raise "#{self.class}: missing method #{method_name.inspect} / doesn't match named pattern element: #{matches_by_name.keys.inspect}"
      end
      case ret=matches_by_name[method_name]
      when EmptyNode then nil
      else ret
      end
    end

    # adds a match with name (optional)
    # returns self so you can chain add_match or concat methods
    def add_match(match,name=nil)
      reset_matches_by_name
      matches<<match
      match_names<<name

      self.match_length=match.next - offset
      self
    end

    # concatinate all matches from another node
    # returns self so you can chain add_match or concat methods
    def concat(node)
      names=node.match_names
      node.matches.each_with_index { |match,i| add_match(match,names[i])}
      self
    end
  end

  # generated by a :poly PatternElement
  # Not subclassed
  class ManyNode < Node
    attr_accessor :matches,:delimiter_matches
    def initialize(parent)
      node_init(parent)
      self.matches=[]
      self.delimiter_matches=[]
    end

    def match_length; self.next-offset end

    def next
      if m=matches[-1]
        m_next=m.next
        if d=delimiter_matches[-1]
          d_next=d.next
          m_next > d_next ? m_next : d_next
        else
          m_next
        end
      else
        parent.next
      end
    end

    def inspect_helper(list,options)
      simple=options[:simple]
      ret=list.collect {|a|a.inspect(options)}.compact
      ret= if ret.length==0 then simple ? nil : "[]"
      elsif ret.length==1 && !ret[0]["\n"] then (simple ? ret[0] : "[#{ret[0]}]")
      else (simple ? ret : ["[",ret,"]"]).flatten.join("\n") #.gsub("\n","\n  ")
      end
      ret
    end

    def inspect(options={})
      if options[:simple]
        c=[]
        matches.each_with_index {|n,i| c<<n;c<<delimiter_matches[i]}
        c=c.compact
        inspect_helper(c,options)
      else
        ret=inspect_helper(matches,options)
        ret+=" delimiters="+inspect_helper(delimiter_matches,options) if delimiter_matches.length>0
        ret
      end
    end

    def method_missing(method_name, *args)  #method_name is a symbol
      self.map {|match| match.send(method_name,*args)}
    end

  end

  # used for String and Regexp PatternElements
  # not subclassed
  class TerminalNode < Node
    attr_accessor :pattern
    def initialize(parent,match_length,pattern)
      node_init(parent)
      self.match_length=match_length
      self.pattern=pattern
    end

    def inspect(options={})
      "#{text.inspect}" unless options[:simple] && text[/^\s*$/] # if simple && node only matched white-space, return nil
    end

    def matches; [self]; end
  end

  # used when a PatternElement matchs the empty string
  # Example: when the PatternElement is optional and doesn't match
  # not subclassed
  class EmptyNode < Node
    def inspect(options={})
      "EmptyNode" unless options[:simple]
    end
  end
end
