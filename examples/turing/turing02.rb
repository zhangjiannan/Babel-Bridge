require File.join(File.dirname(__FILE__),"..","..","lib","babel_bridge")

class TuringParser < BabelBridge::Parser

  rule :add, :int, "+", :add
  rule :add, :int
  rule :int, /[-]?[0-9]+/
end

BabelBridge::Shell.new(TuringParser.new).start