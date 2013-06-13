# #!/usr/bin/env ruby

# Interface to use the webdamlog engine from an external application such as a
# rail application

require_relative 'wlbud'
require_relative 'wlbud/wlerror'

module WLRunner
  include WLBud

  public

  # Create a new webdamlog engine object ready to be run
  def self.create (username, pg_file, port, options={})
    klass = WLEnginePool.create username, port
    obj = klass.new(username, pg_file, {:port => port, :rule_dir => options[:rule_dir]})
    obj.extend WLRunner
    return obj
  end

  def delete
    self.stop if self.running_async
    WLEnginePool.delete self.class
  end

  def run_engine
    run_bg
  end

  # TODO should be called in callback when adding contact
  #
  # @return [String,String] peername, address as added in webdamlog
  def update_add_peer peername, ip, port
    return self.wl_program.add_peer peername, ip, port
  end

  # add collection with declaration as a string or WLRule object
  def update_add_collection wl_relation
    name, schema = ""
    sync_do do
      name, schema = self.add_collection(wl_relation)
    end
    return name, schema
  end

  # Add new facts with declarations Hash, WLFacts or String representing a
  # webdamlog fact in a program
  #
  # @return [Hash, Hash] valid and error, valid is a list of facts that have
  # been successfully inserted, err is a list of facts that has not been insert
  # due to error in the format !{["relation_name", [tuple]] => "error message"}
  def update_add_fact facts
    fct, err = {}
    sync_do do
      begin
        fct, err = self.add_facts facts
      rescue WLError => e
        err = e
      end
    end
    return fct, err
  end

  # XXX doc and customize return value if needed
  def update_add_rule rule
    sync_do do
      self.add_rule rule
    end
  end

  # Helpers to check syntax of one line of webdamlog program
  #
  # @return [Array] array of WLBud::WLVocabulary or WLErrorGrammarParsing
  def parse pg
    ret = []
    begin
      ret = self.wl_program.parse_lines pg, false
    rescue WLError=> err
      ret << err
    end
    return ret
  end

  private

  class WLEnginePool
    class << self

      attr_reader :engines

      # Create the new class to instantiate to be a webdamlog engine
      def create username, port
        @engines ||= {}
        ano_klass = Class.new WLBud::WL
        klass_name = create_new_class_name(username, port)
        klass = Object.const_set(klass_name, ano_klass)
        @engines[klass.object_id] = [klass_name, klass]
        return klass
      end
      
      # Remove WLRunner from the pool
      def delete obj
        raise(WLBud::WLErrorRunner, "try to delete from the pool the class of an engine which is not a Class object type") unless obj.is_a? Class
        klass_name, klass = @engines[obj.object_id]
        @engines.delete(obj.object_id)
        Object.send(:remove_const, klass_name) unless klass_name.nil? or !Object.const_defined?(klass_name)
      end

      def create_new_class_name username, port
        return "ClassWLEngineOf#{username}On#{port}".split('_').collect!{ |w| w.capitalize }.join.to_sym
      end
    end
  end # end class WLEnginePool

end

