require File.join(File.dirname(__FILE__),"..","..","lib","babel_bridge")
# A turing complete programming language
# Example program that computes the power of two of the value stored in the [0] register:
# => [0]=32;[1]=1;while [0]>0 do [1] = [1] * 2; [0] = [0]-1; end;[1]

# TODO: add variables and functions

class TuringParser < BabelBridge::Parser
  ignore_whitespace
  # TODO: add "whole_words" option to convert all literal matching patterns that are words into /word\b/


  def store
    @store||=[]
  end

  rule :statements, many(:statement,";"), match?(";") do
    def evaluate
      ret = nil
      statement.each do |s|
        ret = s.evaluate
      end
      ret
    end
  end

  rule :statement, "if", :statement, "then", :statements, :else_clause?, "end" do
    def evaluate
      if statement.evaluate
        statements.evaluate
      else 
        else_clause.evaluate if else_clause
      end
    end
  end
  rule :else_clause, "else", :statements

  rule :statement, "while", :statement, "do", :statements, "end" do
    def evaluate
      while statement.evaluate
        statements.evaluate
      end
    end
  end

  binary_operators_rule :statement, :operand, [[:/, :*], [:+, :-], [:<, :<=, :>, :>=, :==]] do
    def evaluate
      case operator
      when :<, :<=, :>, :>=, :==
        (left.evaluate.send operator, right.evaluate) ? 1 : nil
      else
        left.evaluate.send operator, right.evaluate
      end
    end
  end

  rule :operand, "(", :statement, ")"
  
  rule :operand, "[", :statement, "]", "=", :statement do
    def evaluate
      parser.store[statement[0].evaluate] = statement[1].evaluate
    end
  end

  rule :operand, "[", :statement, "]" do
    def evaluate
      parser.store[statement.evaluate]
    end
  end

  rule :operand, /[-]?[0-9]+/ do
    def evaluate
      to_s.to_i
    end
  end
end

BabelBridge::Shell.new(TuringParser.new).start