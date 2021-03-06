=begin
Copyright 2011 Shane Brinkman-Davis
See README for licence information.
http://babel-bridge.rubyforge.org/
=end

module BabelBridge

# used when a PatternElement matchs the empty string
# Example: when the PatternElement is optional and doesn't match
# not subclassed
class EmptyNode < Node
  def inspect(options={})
    "EmptyNode" if options[:verbose]
  end

  def matches; [self]; end
end

end
