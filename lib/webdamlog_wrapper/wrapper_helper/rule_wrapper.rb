# Wrapper to synchronize rules added in this model with rules in the wdl engine
# This model rely on the {WrapperHelper::ActiveRecordWrapper} wrapper that
# should have been included previously
module WrapperHelper::RuleWrapper

  module ClassMethods
    def bind_wdl_relation
      super
      enginelogger.debug("WrapperHelper::RuleWrapper #{self} has now methods from wrappers #{self.ancestors[0..2]}...")
    end
  end

  def self.included(base)
    base.extend(ClassMethods)

    attr_reader :inst

    # Check that WrapperHelper::ActiveRecordWrapper has been added before
    # inclusion of this module
    unless base.ancestors.include? WrapperHelper::ActiveRecordWrapper
      error.add(:wrapper, "wrong inclusion of WrapperHelper::RuleWrapper it should have been inserted after inclusion of WrapperHelper::ActiveRecordWrapper")
    end
    unless base.respond_to? :engine
      error.add(:wrapper, "base class should have an engine linked before inclusion of WrapperHelper::RuleWrapper")
    end

    # Override save method of previous wrapper usually active_record_wrapper to
    # add rule into the wdl engine before chaining to active_record_wrapper save
    self.send :define_method, :save do |*args|
      if args.first == :skip_ar_wrapper # skip when you want to call the original save of ActiveRecord in ClassMethods::send_deltas
        super(:skip_ar_wrapper)
      else
        # check if the rule is valid before adding into Webdamlog
        unless  ContentHelper::already_exists?(self.wdlrule)
          errors.add(:exists,"Statement already exists!")
          return false
        else
          engine = self.class.engine
          # FIXME maybe duplicate of validator juste above
          ret = engine.parse(self.wdlrule)
          if ret.is_a? WLBud::WLError
            WLLogger.logger.error "wrapper fail to parse the rule: #{ret} in #{self.wdlrule}"
            errors.add(:wdlparser, "wrapper fail to parse the rule: #{ret} in #{self.wdlrule}")
            return false
          else            
            ret.each do |inst|
              if inst.is_a? WLBud::WLRule
                begin
                  wdl_string = inst.show_wdl_format
                  # FIXME HACKY replace of _at_by @ because of internal
                  # webdamlog format return _at_ and wdl program expect @
                  wdl_string.gsub!("_at_", "@")
                  rule_id, rule_string = engine.update_add_rule(wdl_string) # Update add rule
                  unless rule_id.nil? # if rule is fully non-local hence local rule resulting will be empty
                    rule_string.gsub!("_at_", "@")
                    self.wdl_rule_id = rule_id
                    self.wdlrule = rule_string
                    self.role = 'rule'
                  else
                    self.wdl_rule_id = 'delegated'
                    self.wdlrule = wdl_string
                    self.role = 'rule'
                  end
                  super()
                rescue WLBud::WLError => err
                  WLLogger.logger.error "wrapper fail to insert the rule: #{wdl_string}  in the webdamlog engine reason: #{err}"
                  errors.add(:wdlengine, "wrapper fail to insert the rule: #{wdl_string}  in the webdamlog engine reason:: #{err}")
                  return false
                end
                # FIXME some temporary code to makes rules with relation works
                # ideally the rulewrapper should not do that king of stuff but
                # delegate to a proper wrapper (maybe a relation classes
                # wrapper) HACKY
              elsif inst.is_a? WLBud::WLCollection
                # TODO add collection into the right model for wepic to see them
                # FIXME should be only one database but still
                schema = {}
                budschema = inst.schema
                list = budschema.keys.first.map { |it| it.to_s } + budschema.values.first.map { |it| it.to_s }
                list.reject! { |item| item.empty? }
                list.each { |key| schema[key]="text" }
                begin
                  klass, relname, sch, instruction = WLDatabase.databases.values.first.create_model(inst.relname, schema, {wdl: true})
                rescue WLBud::WLError => err
                  errors.add(:wdlengine, "wrapper fail to create the collection in the webdamlog engine: #{err}")
                  return false
                end
                if klass
                  self.class.enginelogger.debug("WrapperHelper::RuleWrapper has created a new relation in webdamlog #{inst} linked to #{klass}")
                  # FIXME id is the object_id it should be some kind of id
                  # generated in WLCollection in the fashion of wrlrule_id in
                  # WLRule
                  self.wdl_rule_id = klass.object_id
                  self.wdlrule = instruction
                  self.role = "extensional"
                  super()
                else
                  errors.add(:wrapper, "impossible to create model for #{inst} via rule wrapper")
                  return false
                end
              else
                errors.add(:wrapper, "impossible to create model for #{inst} via rule wrapper")
                return false
              end # if inst.is_a? WLBud::WLRule
            end # ret.each do |inst|
          end # if ret.is_a? WLError
        end # unless self.valid?
      end # if args.first == :skip_ar_wrapper
    end # base.send :define_method, :save    
  end # self.included(base)  
end # module WrapperHelper::RuleWrapper
