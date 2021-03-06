require 'set'
require 'json'
require 'pathname'
require 'fileutils'
require 'active_support/core_ext/string'
require './lib/wl_tool'

# This helper manage database connection for a peer. This is the wrapper of
# wepic for the database postgres or SQLite of webdamlog relation to store in
# tables.
#
# The class WLInstanceDatabase represent the object which provide methods to
# alter the database schema (add table)
#
# PENDING should be renamed in database_wrapper
#
module WLDatabase

  # The set of database on which the peer is connected. In our app there is
  # always exactly one.
  @@databases = Hash.new

  # FIXME accessor for class variable see if attr-redaer can work
  def self.databases
    @@databases
  end
  
  # This setup the database server (currently postgresql or sqlite3 (nothing to
  # do since their are just files)) @return [WLInstanceDatabase] the object
  # mapper for the new database created
  def self.setup_database_server
    unless @@databases[Conf.env['USERNAME']]
      db_name = Conf.db['database']
      # Connect to postgres database with admin user postgres that always exist.
      # Then create the first database for the manager
      if Conf.db['adapter'] == 'postgresql'
        if PostgresHelper.db_exists? db_name
          msg = "#{db_name} exists postgreSQL: create object relational mapper"
          WLLogger.logger.debug msg
        else
          msg = "Need to create the database #{db_name} in the database server postgreSQL"
          WLLogger.logger.debug msg
          if Conf.manager?
            PostgresHelper.create_manager_db Conf.db
          else
            PostgresHelper.create_user_db Conf.db
          end
        end
      end
      return WLDatabase.establish_orm_db_connection(Conf.env['USERNAME'], db_name, Conf.db)
    end
  end
  
  # Access a database loaded by the program using its database id. The id for
  # the database is usually the username of the user since there is only one db
  # per peer user.
  #
  def database(database_id)
    @@databases[database_id]
  end

  # Creates a new database object for the user using his database_id as key. If
  # database already exists, simply connects to it (no override).
  #
  def self.establish_orm_db_connection(database_id,db_name,configuration)
    @@databases[database_id] ||= WLInstanceDatabase.new(database_id,db_name,configuration)
    @@databases[database_id]
  end

  # #FIXME Do we want to destroy the object explicitly? classes?
  def close_connection(database_id)
    @@databases[database_id].destroy_classes
    @@databases.delete(database_id)
  end

  def destroy(database_id)
    @@databases[database_id].destroy_classes_and_database
    @@databases.delete(database_id)
  end

  def self.to_model_name table_name
    table_name.classify
  end

  def self.to_table_name model_name
    model_name.tableize
  end
  
  # #TODO Add namespace to WLSchema relation. The namespace is based on the
  # database_id #TODO: Datetime and binary format have to be managed to be
  # viewed properly.
  class WLInstanceDatabase
    include WLTool
    
    attr_accessor :id, :relation_classes, :configuration

    DATABASE_SCHEMA = WLDatabase.to_model_name("WLSchema")
    DATABASE_META = WLDatabase.to_model_name("DatabaseMeta")
    DATABASE_META_SCHEMA = {"id" => "string", "dbname" => "string", "configuration" => "string", "init" => "boolean"}

    # Creates a new database with a name defined by the user's id. If the
    # database already exists, simply connects to it.
    #
    def initialize(database_id,db_name,configuration)
      @id = database_id
      @db_name = db_name
      @configuration = configuration
      @initialized = initialized?
      unless @initialized
        create_schema
        if need_bootstrap?
          init_models
        end
        @initialized = true
      end      
    end

    def need_bootstrap?
      meta = DATABASE_META
      if table_exists_for_model? meta and !relation_classes[meta].where(:init=>true).first.nil?
        false
      else
        true
      end
    end

    # Test and check if database is initialized properly
    #
    # Force @initialized to nil to check if an old database may fit our model
    #
    def initialized?
      if @initialized.nil?
        if db_exists? @db_name
          if @relation_classes.nil? or @relation_classes.empty?
            @initialized = false
          else
            @relation_classes.each do |model| # each relation must have a model connected
              unless table_exists_for_model? model
                WLLogger.logger.warn "database #{@db_name} seems to be corrupted: #{model} has no table in the database"
                @initialized=false
              end
              @initialized = true
            end
            WLLogger.logger.warn "database #{@db_name} exists but there is no model to load"
            @initialized = false
          end
        else
          @initialized = false
        end

      else # @initialized.nil?
        
        if @initialized
          if @wlschema.nil? or !table_exists_for_model?(@wlschema)
            WLLogger.logger.warn "database #{@db_name}supposed to be initialized but it seems to be corrupted: wlschema not found"
            @initialized=false
          end
        end
        return @initialized
        
      end # @initialized.nil?
    end # initialized?

    # #Resets instance schemas and relation_classes attributes. #Remove all
    # generated model classes.
    def destroy_classes
      # #Remove all generated model classes
      @relation_classes.values.each do |class_object|
        delete_class(class_object)
      end
      delete_class(@wlschema)
      @initialized = false
      @relation_classes = Hash.new
    end
    
    # Removes the database file and generated model classes. Also resets
    # instance schemas and relation_classes attributes. Use
    # create_or_retrieve_database to reinitialize.
    def destroy_classes_and_database
      # #Remove all generated model classes
      destroy_classes
      # #Destroy the db
      case Conf.db['adapter']
      when 'sqlite3'
        path = Pathname.new(@db_name)
        rails_root = File.expand_path('.')
        file = path.absolute? ? path.to_s : File.join(rails_root, path)
        FileUtils.rm(file)
      when 'postgresql'
        conn = PGconn.open(:dbname => @db_name, :user => Conf.db['username'])
        sqldrop = "DROP DATABASE #{@db_name}"
        begin
          rs = conn.exec(sqldrop)
          p "#{sqldrop} succeed"
        rescue PG::Error => err
          p "Wepic Warning #{err.inspect}"
        end
        conn.close
      end
    end

    def db_exists? (db_name)
      case Conf.db['adapter']
      when 'sqlite3'
        return File.exists?(db_name)
      when 'postgresql'
        PostgresHelper.db_exists?(db_name)
      end
      
    end
    
    # Initialize @wlschema, the model that keep the schema of the database for
    # this peer. Since database schemas are different for every user, storing
    # them is a quick way of loading efficient methods into the newly created
    # instance.
    #
    # Also it creates the model for all the tables that @wlshema knows
    #
    def create_schema
      # The hash that keep the correspondence between the model class name and
      # the class themselves
      #
      @relation_classes ||= Hash.new
      unless @relation_classes.empty?
        WLLogger.logger.warn "try to recreate a object from the database but #{@relation_classes.length} models are left in memory #{@relation_classes}"
      end
      
      # The model of the schema itself stored in the database
      #
      # TODO write create_AR_model_class with a block to introduced validators
      # (validates_uniqueness_of :name) as in comments below
      #
      @wlschema = create_AR_model_class(DATABASE_SCHEMA, {"name"=>"string","schema"=>"binary"})
      #      @wlschema = create_class("#{relation_name}_#{@id}",ActiveRecord::Base) do
      #        @schema = {"name"=>"string","schema"=>"string"}
      #        @wl_database_instance = database_instance
      #        establish_connection @wl_database_instance.configuration
      #        attr_accessible :name, :schema
      #        validates_uniqueness_of :name
      #        self.table_name = relation_name
      #        if !connection.table_exists?(table_name)
      #          connection.create_table table_name, :force => true do |t|
      #            t.string :name
      #            t.string :schema
      #          end
      #        else
      #          WLLogger.logger.debug "try to create wlschema table in db #{@wl_database_instance.configuration} but it already exists"
      #        end
      #        def self.schema
      #          @schema
      #        end
      #        WLLogger.logger.debug "create a model #{self} with its table #{table_name} schema #{@schema} in database #{@wl_database_instance}"
      #      end
      @relation_classes[DATABASE_SCHEMA]=@wlschema
      # #Retrieve all the models #@wlschema.establish_connection @configuration
      @wlschema.all.each do |table|
        klass = create_AR_model_class(table.name, JSON.parse(table.schema))
        @relation_classes[klass.name] = klass
        @wlmeta = @relation_classes[klass.name] if klass.name == DATABASE_META
      end
    end

    def init_models
      # Create the meta data for the current database, useful on reload
      @wlmeta, relname, sch, instruction = create_model(DATABASE_META,DATABASE_META_SCHEMA)
      
      # bind to webdamlog but not created in the bootstrap program
      classname = "DescribedRule"
      com = WLTool::class_exists(classname , ActiveRecord::Base)
      if com.nil?
        load 'described_rule.rb'
        @relation_classes[classname] = Object.const_get(classname)
      else
        @relation_classes[classname] = com
      end
      
      # Init manually the builtins relations created when rails has parsed the
      # models. These are the relation to bind to webdalog relation that have
      # already been created in webdamlog thanks to wdl program file in
      # bootstrap
      classname = "Picture"
      pict = WLTool::class_exists(classname , ActiveRecord::Base)
      if pict.nil?
        load 'picture.rb'
        @relation_classes[classname] = Object.const_get(classname)
      else
        @relation_classes[classname] = pict
      end
      
      classname = "Contact"
      conn = WLTool::class_exists(classname, ActiveRecord::Base)
      if conn.nil?
        load 'contact.rb'
        @relation_classes[classname] = Object.const_get(classname)
      else
        @relation_classes[classname] = conn
      end
      # wdl linking

      classname = "PictureLocation"
      iml = WLTool::class_exists(classname , ActiveRecord::Base)
      if iml.nil?
        load 'picture_location.rb'
        @relation_classes[classname] = Object.const_get(classname)
      else
        @relation_classes[classname] = iml
      end

      classname = "Rating"
      rate = WLTool::class_exists(classname , ActiveRecord::Base)
      if rate.nil?
        load 'rating.rb'
        @relation_classes[classname] = Object.const_get(classname)
      else
        @relation_classes[classname] = rate
      end

      classname = "Comment"
      com = WLTool::class_exists(classname , ActiveRecord::Base)
      if com.nil?
        load 'comment.rb'
        @relation_classes[classname] = Object.const_get(classname)
      else
        @relation_classes[classname] = com
      end

      # The following relation are not linked to webdamlog
      classname = "User"
      peer = WLTool::class_exists(classname, ActiveRecord::Base)
      if peer.nil?
        load 'user.rb'
        @relation_classes[classname] = Object.const_get(classname)
      else
        @relation_classes[classname] = peer
      end
      
      classname = "Program"
      prog = WLTool::class_exists(classname, ActiveRecord::Base)
      if prog.nil?
        load 'program.rb'
        @relation_classes[classname] = Object.const_get(classname)
      else
        @relation_classes[classname] = prog
      end
    end

    # Some facts needed to store meta data saved in their respective
    # ActiveRecord
    def save_facts_for_meta_data
      @wlmeta.new(:id=>@id, :dbname=>@db_name, :configuration=>@configuration, :init=>true).save

      @wlschema.new(:name=>Picture.table_name, :schema=>Picture.schema.to_json).save
      @wlschema.new(:name=>Contact.table_name, :schema=>Contact.schema.to_json).save
      @wlschema.new(:name=>User.table_name, :schema=>User.schema.to_json).save
      @wlschema.new(:name=>Program.table_name, :schema=>Program.schema.to_json).save
      @wlschema.new(:name=>PictureLocation.table_name, :schema=>PictureLocation.schema.to_json).save
      @wlschema.new(:name=>Rating.table_name, :schema=>Rating.schema.to_json).save
      @wlschema.new(:name=>Comment.table_name, :schema=>Comment.schema.to_json).save
      @wlschema.new(:name=>DescribedRule.table_name, :schema=>DescribedRule.schema.to_json).save
      
      begin
        # FIXME
        unless Conf.peer['peer']['username'] == 'sigmod_peer'
          ContentHelper::query_create
        end
      rescue => error
        WLLogger.logger.warn "In ContentHelper::query_create an error occured : #{error.message}\nat\t:\t#{error.backtrace.join("\n")[0..20]}"
      end
    end

    # The create relation method will create a new relation in the database as
    # well as a new rails model class connected to that relation. It requires a
    # schema that will correspond to the table's relational schema.
    #
    # @options createwdl [boolean] :wdl set to true to create the binding with
    # webdamlog
    #
    # @return [Class, String, Hash, String] class created, name of relation,
    # Hash of the schema, webamlog instruction
    #
    def create_model(name,schema,options={})
      model_klass = create_AR_model_class(name, schema)

      if options[:wdl]
        # wdl binding
        model_klass.send :include, WrapperHelper::ActiveRecordWrapper
        # XXX when failed the model_klass should be garbage collected since we
        # don't keep any reference to it
        nm, sch, inst = model_klass.create_wdl_relation schema
        return nm if nm.is_a? WLBud::WLError
        model_klass.bind_wdl_relation
      end

      @relation_classes[name] = model_klass
      begin
        # new record in the wlshema table
        unless @wlschema.new(:name => model_klass.table_name,:schema => model_klass.schema.to_json).save        
          raise WLDatabaseError.new "Relation wlschema was not properly updated, record should be invalid according to the model"
        end
      rescue => error
        raise WLDatabaseError.new "Error in create_model with #{name} #{schema} #{error.message}"
      end
      return @relation_classes[name], nm, sch, inst
    end

    # Create the relation as a model and a table in the database. Return the
    # class of the model created if succeed. it should be called by
    # create_relation create_relation, relation
    #
    # @notice silently ignore empty fields that is if col_type or col_name is
    # not specified in schema it will be skipped and continue with other
    # attributes
    def create_AR_model_class(name, schema)
      raise WLDatabaseError.new "type error of name is #{name.class}" unless name.is_a? String
      raise WLDatabaseError.new "type error of schema is #{schema.class}" unless schema.is_a? Hash
      database_instance = self
      config = Conf.db
      model_name = WLDatabase.to_model_name(name)
      klass = create_class(model_name, ::AbstractDatabase) do
        @schema = schema
        @wl_database_instance = database_instance
        establish_connection config
        
        # By default we impose that no field could be nil
        schema.each_pair do |col_name,col_type|
          eval "validates :#{col_name}, :presence => true" unless col_name.empty?
        end

        if table_name.nil? or table_name.empty?
          self.table_name = WLDatabase.to_table_name(model_name)
        end
        
        if !connection.table_exists?(table_name)
          connection.create_table table_name, :force => true do |t|
            schema.each_pair do |col_name,col_type|
              eval("t.#{col_type} :#{col_name}") unless col_name.empty? or col_type.empty?
            end
            t.timestamps
          end
        else
          WLLogger.logger.debug "try to create #{table_name} table in db #{config} for model #{model_name} but it already exists"
        end
        def self.find(*args)
          super *args
        end        
        def self.all
          super
        end
        def self.inspect
          super
        end
        def self.delete (id)
          tuple = self.find(id)
          tuple.destroy
        end
        def self.schema
          @schema
        end
        WLLogger.logger.debug "Created a model #{model_name} with its table #{table_name} and schema #{@schema} in database #{config['database']}"
      end
      WLLogger.logger.debug "class #{klass} created by create_AR_model_class"
      return klass
    end
      
    # Test if the given model or relation name in @relation_classes has a
    # corresponding table in the current database
    #
    def table_exists_for_model?(relation_name)
      if @relation_classes.key? relation_name
        model = @relation_classes[relation_name]
      elsif relation_name.is_a? Class and relation_name.ancestors.includes? <= ActiveRecord::Base
        model = relation_name.table_name
      else
        WLLogger.logger.warn "#{relation_name} is not a model"
        return false
      end

      if model.respond_to? :connection and model.respond_to? :table_name
        return model.connection.table_exists?(model.table_name)
      else
        WLLogger.logger.warn "Relation name #{relation_name} has model #{model} expected to respond_to? :connection and :table_name"
        return false
      end
    end # table_exists_for_model?

  end # class WLInstanceDatabase

  class WLDatabaseError < StandardError
    
    def initialize(msg)
      super(msg)
      @msg = msg
      WLLogger.logger.fatal @msg      
    end

    def to_s
      "#{super} : #{@msg}"
    end
    
  end # class WLDatabaseError

end # module WLDatabase
